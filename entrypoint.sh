#!/bin/bash

# Check installation
if [ ! -d /data/mysql/mysql ]; then
  INSTALL=1
fi

# Start RabbitMQ server
echo 'Start RabbitMQ server...'
service rabbitmq-server start
rabbitmqctl add_user openstack $RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# Setup mysql
sed -i "s/^datadir.*/datadir = \/data\/mysql/" /etc/mysql/my.cnf
echo "[mysqld]" > /etc/mysql/conf.d/mysqld.cnf
echo "bind-address = 0.0.0.0" >> /etc/mysql/conf.d/mysqld.cnf
echo "default-storage-engine = innodb" >> /etc/mysql/conf.d/mysqld.cnf
echo "innodb_file_per_table" >> /etc/mysql/conf.d/mysqld.cnf
echo "collation-server = utf8_general_ci" >> /etc/mysql/conf.d/mysqld.cnf
echo "init-connect = 'SET NAMES utf8'" >> /etc/mysql/conf.d/mysqld.cnf
echo "character-set-server = utf8" >> /etc/mysql/conf.d/mysqld.cnf

if [[ $INSTALL -eq 1 ]]; then
  mysql_install_db
  service mysql start

  mysql -e "DELETE FROM mysql.user"
  mysql -e "GRANT ALL ON *.* TO 'root'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION"
  mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
  mysql -e "DROP DATABASE IF EXISTS test"

  # Create users & databases
  mysql -e "CREATE DATABASE keystone"
  mysql -e "GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS'"

  mysql -e "CREATE DATABASE glance"
  mysql -e "GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS'"

  mysql -e "CREATE DATABASE nova"
  mysql -e "GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS'"

  mysql -e "CREATE DATABASE neutron"
  mysql -e "GRANT ALL ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS'"

  mysql -e "CREATE DATABASE cinder"
  mysql -e "GRANT ALL ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS'"

  mysql -e "FLUSH PRIVILEGES"
else
  service mysql start
fi

# Run mongodb service
echo 'Mongodb setup...'
if [[ $INSTALL -eq 1 ]]; then
  mkdir -p /data/mongodb
  chown mongodb. /data/mongodb
  sed -i "s/^dbpath.*/dbpath=\/data\/mongodb/" /etc/mongodb.conf
  # sed -i "s/^bind_ip.*/bind_ip = 0.0.0.0/" /etc/mongodb.conf
  echo "smallfiles = true" >> /etc/mongodb.conf
fi
service mongodb start

# Keystone setup
echo 'Keystone setup...'

echo "manual" > /etc/init/keystone.override
sed -i "s#^connection.*#connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@$CONTROLLER_HOST/keystone#" /etc/keystone/keystone.conf
sed -i "s/^#servers.*/servers = localhost:11211/" /etc/keystone/keystone.conf
sed -i "s/^#provider.*/provider = uuid\n\ndriver = memcache/" /etc/keystone/keystone.conf
sed -i "s/^\[revoke\].*/[revoke]\n\ndriver = sql/" /etc/keystone/keystone.conf
if [ "$ADMIN_TOKEN" ]; then
  sed -i "s/^#admin_token.*/admin_token = $ADMIN_TOKEN/" /etc/keystone/keystone.conf
fi

if [[ $INSTALL -eq 1 ]]; then
  su -s /bin/sh -c "keystone-manage db_sync" keystone
  ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled
fi

service memcached restart
service apache2 restart

if [[ $INSTALL -eq 1 ]]; then
  # Creation of Tenant & User & Role
  echo 'Creation of Tenant / User / Role...'

  export OS_TOKEN=$ADMIN_TOKEN
  export OS_URL=http://$CONTROLLER_HOST:35357/v3
  export OS_IDENTITY_API_VERSION=3

  openstack service create --name keystone --description "OpenStack Identity" identity
  openstack endpoint create --region $REGION_NAME identity public http://$CONTROLLER_HOST:5000/v3
  openstack endpoint create --region $REGION_NAME identity internal http://$CONTROLLER_HOST:5000/v3
  openstack endpoint create --region $REGION_NAME identity admin http://$CONTROLLER_HOST:35357/v3

  openstack project create --domain default --description "$ADMIN_PROJECT" admin
  openstack user create --domain default --password $ADMIN_PASS admin
  openstack role create admin
  openstack role add --project admin --user admin admin

  openstack project create --domain default --description "Service Project" service
  openstack project create --domain default --description "Demo Project" demo
  openstack user create --domain default --password $DEMO_PASS demo
  openstack role create user
  openstack role add --project demo --user demo user

  openstack user create --domain default --password $GLANCE_PASS glance
  openstack role add --project service --user glance admin

  openstack service create --name glance --description "OpenStack Image Service" image
  openstack endpoint create --region $REGION_NAME image public http://$CONTROLLER_HOST:9292
  openstack endpoint create --region $REGION_NAME image internal http://$CONTROLLER_HOST:9292
  openstack endpoint create --region $REGION_NAME image admin http://$CONTROLLER_HOST:9292

  openstack user create --domain default --password $NOVA_PASS nova
  openstack role add --project service --user nova admin

  openstack service create --name nova --description "OpenStack Compute" compute
  openstack endpoint create --region $REGION_NAME compute public http://$CONTROLLER_HOST:8774/v2/%\(tenant_id\)s
  openstack endpoint create --region $REGION_NAME compute internal http://$CONTROLLER_HOST:8774/v2/%\(tenant_id\)s
  openstack endpoint create --region $REGION_NAME compute admin http://$CONTROLLER_HOST:8774/v2/%\(tenant_id\)s

  openstack user create --domain default --password $NEUTRON_PASS neutron
  openstack role add --project service --user neutron admin

  openstack service create --name neutron --description "OpenStack Networking" network
  openstack endpoint create --region $REGION_NAME network public http://$CONTROLLER_HOST:9696
  openstack endpoint create --region $REGION_NAME network internal http://$CONTROLLER_HOST:9696
  openstack endpoint create --region $REGION_NAME network admin http://$CONTROLLER_HOST:9696
fi

# Glance setup
echo 'Glance setup...'
GLANCE_API=/etc/glance/glance-api.conf
GLANCE_REGISTRY=/etc/glance/glance-registry.conf

### /etc/glance/glance-api.conf modify for MySQL & RabbitMQ
sed -i "s/sqlite_db.*/connection = mysql+pymysql:\/\/glance:$GLANCE_DBPASS@$CONTROLLER_HOST\/glance/" $GLANCE_API
sed -i "s/^#auth_uri.*/auth_uri = http:\/\/$CONTROLLER_HOST:5000\/v3/" $GLANCE_API
sed -i "s/^#identity_uri.*/identity_uri = http:\/\/$CONTROLLER_HOST:35357/" $GLANCE_API
sed -i "s/^#admin_tenant_name.*/admin_tenant_name = service/" $GLANCE_API
sed -i "s/^#admin_user.*/admin_user = glance/" $GLANCE_API
sed -i "s/^#admin_password.*/admin_password = $GLANCE_PASS/" $GLANCE_API
sed -i "s/^#flavor.*/flavor = keystone/" $GLANCE_API
sed -i "s/^#default_store.*/default_store = file/" $GLANCE_API
sed -i "s/^#filesystem_store_datadir =.*/filesystem_store_datadir = \/data\/glance/" $GLANCE_API
sed -i "s/^#notification_driver.*/notification_driver = noop/" $GLANCE_API

### /etc/glance/glance-registry.conf for MySQL & RabbitMQ
sed -i "s/#connection =.*/connection = mysql+pymysql:\/\/glance:$GLANCE_DBPASS@$CONTROLLER_HOST\/glance/" $GLANCE_REGISTRY
sed -i "s/^#auth_uri.*/auth_uri = http:\/\/$CONTROLLER_HOST:5000\/v3/" $GLANCE_REGISTRY
sed -i "s/^#identity_uri.*/identity_uri = http:\/\/$CONTROLLER_HOST:35357/" $GLANCE_REGISTRY
sed -i "s/^#admin_tenant_name.*/admin_tenant_name = service/" $GLANCE_REGISTRY
sed -i "s/^#admin_user.*/admin_user = glance/" $GLANCE_REGISTRY
sed -i "s/^#admin_password.*/admin_password = $GLANCE_PASS/" $GLANCE_REGISTRY
sed -i "s/^#flavor.*/flavor = keystone/" $GLANCE_REGISTRY
sed -i "s/^#notification_driver.*/notification_driver = noop/" $GLANCE_API

# excution for glance service
if [[ $INSTALL -eq 1 ]]; then
  mkdir -p /data/glance
  chown glance:glance /data/glance
  su -s /bin/sh -c "glance-manage db_sync" glance
fi
service glance-registry restart
service glance-api restart

## Nova setup
echo 'Nova setup...'
NOVA_CONF=/etc/nova/nova.conf

echo "my_ip = 0.0.0.0" >> $NOVA_CONF
echo "auth_strategy = keystone" >> $NOVA_CONF
echo "network_api_class = nova.network.neutronv2.api.API" >> $NOVA_CONF
echo "security_group_api = neutron" >> $NOVA_CONF
echo "linuxnet_interface_driver = nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver" >> $NOVA_CONF
echo "firewall_driver = nova.virt.firewall.NoopFirewallDriver" >> $NOVA_CONF
echo "enabled_apis=osapi_compute,metadata" >> $NOVA_CONF
echo "rpc_backend = rabbit" >> $NOVA_CONF

echo "" >> $NOVA_CONF
echo "[database]" >> $NOVA_CONF
echo "connection = mysql+pymysql://nova:$NOVA_DBPASS@$CONTROLLER_HOST/nova" >> $NOVA_CONF

echo "" >> $NOVA_CONF
echo "[oslo_messaging_rabbit]" >> $NOVA_CONF
echo "rabbit_host = $CONTROLLER_HOST" >> $NOVA_CONF
echo "rabbit_userid = openstack" >> $NOVA_CONF
echo "rabbit_password = $RABBIT_PASS" >> $NOVA_CONF

echo "" >> $NOVA_CONF
echo "[keystone_authtoken]" >> $NOVA_CONF
echo "auth_uri = http://$CONTROLLER_HOST:5000" >> $NOVA_CONF
echo "auth_url = http://$CONTROLLER_HOST:35357" >> $NOVA_CONF
echo "auth_plugin = password" >> $NOVA_CONF
echo "project_domain_id = default" >> $NOVA_CONF
echo "user_domain_id = default" >> $NOVA_CONF
echo "admin_tenant_name = service" >> $NOVA_CONF
echo "username = nova" >> $NOVA_CONF
echo "password = $NOVA_PASS" >> $NOVA_CONF

echo "" >> $NOVA_CONF
echo "[vnc]" >> $NOVA_CONF
echo "enabled = True" >> $NOVA_CONF
echo "vncserver_listen = 0.0.0.0" >> $NOVA_CONF
echo "vncserver_proxyclient_address = $CONTROLLER_HOST" >> $NOVA_CONF
echo "novncproxy_base_url = http://$CONTROLLER_HOST:6080/vnc_auto.html" >> $NOVA_CONF

echo "" >> $NOVA_CONF
echo "[glance]" >> $NOVA_CONF
echo "host = $CONTROLLER_HOST" >> $NOVA_CONF

echo "" >> $NOVA_CONF
echo "[oslo_concurrency]" >> $NOVA_CONF
echo "lock_path = /var/lib/nova/tmp" >> $NOVA_CONF

echo "" >> $NOVA_CONF
echo "[neutron]" >> $NOVA_CONF
echo "url = http://$CONTROLLER_HOST:9696" >> $NOVA_CONF
echo "auth_url = http://$CONTROLLER_HOST:35357" >> $NOVA_CONF
echo "auth_plugin = password" >> $NOVA_CONF
echo "project_domain_id = default" >> $NOVA_CONF
echo "user_domain_id = default" >> $NOVA_CONF
echo "region_name = $REGION_NAME" >> $NOVA_CONF
echo "project_name = service" >> $NOVA_CONF
echo "username = neutron" >> $NOVA_CONF
echo "password = $NEUTRON_PASS" >> $NOVA_CONF
echo "service_metadata_proxy = True" >> $NOVA_CONF
echo "metadata_proxy_shared_secret = $METADATA_SECRET" >> $NOVA_CONF

# Nova service start
if [[ $INSTALL -eq 1 ]]; then
  su -s /bin/sh -c "nova-manage db sync" nova
fi

service nova-api restart
service nova-cert restart
service nova-consoleauth restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart

## Neutron Setup
echo 'Neutron Setup...'
NEUTRON_CONF=/etc/neutron/neutron.conf
ML2_CONF=/etc/neutron/plugins/ml2/ml2_conf.ini

### /etc/neutron/neutron.conf modify
sed -i "s/^connection =.*/connection = mysql+pymysql:\/\/neutron:$NEUTRON_DBPASS@$CONTROLLER_HOST\/neutron/" $NEUTRON_CONF
sed -i "s/^# rpc_backend=rabbit.*/rpc_backend=rabbit/" $NEUTRON_CONF
sed -i "s/^# rabbit_host = localhost.*/rabbit_host=$CONTROLLER_HOST/" $NEUTRON_CONF
sed -i "s/^# rabbit_userid = guest.*/rabbit_userid = openstack/" $NEUTRON_CONF
sed -i "s/^# rabbit_password = guest.*/rabbit_password = $RABBIT_PASS/" $NEUTRON_CONF
sed -i "s/^# auth_strategy = keystone.*/auth_strategy = keystone/" $NEUTRON_CONF
sed -i "s/^auth_uri =.*/auth_uri = http:\/\/$CONTROLLER_HOST:5000/" $NEUTRON_CONF
sed -i "s/^identity_uri =.*/auth_url = http:\/\/$CONTROLLER_HOST:35357/" $NEUTRON_CONF
sed -i "s/^admin_tenant_name =.*/\nauth_plugin = password\nproject_domain_id = default\nuser_domain_id = default\nproject_name = service/" $NEUTRON_CONF
sed -i "s/^admin_user =.*/username = neutron/" $NEUTRON_CONF
sed -i "s/^admin_password =.*/password = $NEUTRON_PASS/" $NEUTRON_CONF
sed -i "s/# notify_nova_on_port_status_changes.*/notify_nova_on_port_status_changes = True/" $NEUTRON_CONF
sed -i "s/# notify_nova_on_port_data_changes.*/notify_nova_on_port_data_changes = True/" $NEUTRON_CONF
sed -i "s/# nova_url.*/nova_url = http:\/\/$CONTROLLER_HOST:8774\/v2/" $NEUTRON_CONF
sed -i "s/^\[nova\]/[nova]\n\nauth_url = http:\/\/$CONTROLLER_HOST:35357\nauth_plugin = password\nproject_domain_id = default\nuser_domain_id = default\nregion_name = $REGION_NAME\nproject_name = service\nusername = nova\npassword = $NOVA_PASS/" $NEUTRON_CONF
sed -i "s/^# service_plugins.*/service_plugins = router/" $NEUTRON_CONF
sed -i "s/# allow_overlapping_ips.*/allow_overlapping_ips = True/" $NEUTRON_CONF

# DVR Setup / L3 HA
if [ $HA_MODE == "DVR" ]; then
  sed -i "s/^# router_distributed.*/router_distributed = True/" $NEUTRON_CONF
fi

# L3 HA Setup
if [ $HA_MODE == "L3_HA" ]; then
  sed -i "s/^# router_distributed.*/router_distributed = False/" $NEUTRON_CONF
  sed -i "s/^# l3_ha = False.*/l3_ha = True/" $NEUTRON_CONF
  sed -i "s/^# max_l3_agents_per_router.*/max_l3_agents_per_router = 0/" $NEUTRON_CONF
fi

# L3 Agent Failover
sed -i "s/^# allow_automatic_l3agent_failover.*/allow_automatic_l3agent_failover = True/" $NEUTRON_CONF

### /etc/neutron/plugin/ml2/ml2_conf.ini modify
sed -i "s/# type_drivers.*/type_drivers = flat,vxlan/" $ML2_CONF
sed -i "s/# tenant_network_types.*/tenant_network_types = vxlan/" $ML2_CONF
sed -i "s/# mechanism_drivers.*/mechanism_drivers = openvswitch,l2population/" $ML2_CONF
sed -i "s/# vni_ranges.*/vni_ranges = 1:1000/" $ML2_CONF
sed -i "s/# vxlan_group.*/vxlan_group = 239.1.1.1/" $ML2_CONF
sed -i "s/# enable_security_group.*/enable_security_group = True/" $ML2_CONF
sed -i "s/# enable_ipset.*/enable_ipset = True/" $ML2_CONF
echo "firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver" >> $ML2_CONF

if [[ $INSTALL -eq 1 ]]; then
  su -s /bin/sh -c "neutron-db-manage --config-file $NEUTRON_CONF --config-file $ML2_CONF upgrade liberty" neutron
fi

echo 'Neutron service starting...'
service neutron-server restart

## Horizon Setup
echo 'Horizon setup...'
HORIZON_CONF=/etc/openstack-dashboard/local_settings.py
sed -i "s/^OPENSTACK_HOST.*/OPENSTACK_HOST = \"$CONTROLLER_HOST\"/" $HORIZON_CONF
sed -i "s/^OPENSTACK_KEYSTONE_DEFAULT_ROLE.*/OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"/" $HORIZON_CONF
sed -i "s/enable_router': True/enable_router': False/" $HORIZON_CONF
sed -i "s/enable_quotas': True/enable_quotas': False/" $HORIZON_CONF
sed -i "s/enable_lb': True/enable_lb': False/" $HORIZON_CONF
sed -i "s/enable_firewall': True/enable_firewall': False/" $HORIZON_CONF
sed -i "s/enable_vpn': True/enable_vpn': False/" $HORIZON_CONF
sed -i "s/enable_fip_topology_check': True/enable_fip_topology_check': False/" $HORIZON_CONF
sed -i "s#^TIME_ZONE.*#TIME_ZONE = \"$TIME_ZONE\"#" $HORIZON_CONF
rm -rf /var/www/html/index.html
echo "RewriteEngine on\nRewriteCond %{REQUEST_URI} ^/\$\nRewriteRule (.*) /horizon [R=301,L]"

service apache2 reload

## Setup complete
echo 'Setup complete!...'

while true
  do sleep 1
done
