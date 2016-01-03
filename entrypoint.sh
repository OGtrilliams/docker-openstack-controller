#!/bin/bash

# Start RabbitMQ server
echo 'Start RabbitMQ server...'
service rabbitmq-server start

# Change password for RabbitMQ server
while true; do
  if [ "$RABBIT_PASS" ]; then
    rabbitmqctl change_password guest $RABBIT_PASS
    if [ $? == 0 ]; then
      break
    else
      echo "Waiting for RabbitMQ Server password change..."; sleep 1
    fi
  fi
done

# Configure packages
if [ ! -d /data/mysql/mysql ]; then
  INSTALL=1

  sed -Ei 's/^(bind-address|log)/#&/' /etc/mysql/my.cnf && \
  sed -i "s/^datadir.*/datadir = \/data\/mysql/" /etc/mysql/my.cnf

  echo 'Running mysql_install_db...'
  mysql_install_db
  echo 'Finished mysql_install_db...'

  tempSqlFile='/tmp/mysql-setup.sql'
  echo "DELETE FROM mysql.user;" > "$tempSqlFile"
  echo "CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >> "$tempSqlFile"
  echo "GRANT ALL ON *.* TO 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >> "$tempSqlFile"
  echo "DROP DATABASE IF EXISTS test;" >> "$tempSqlFile"

  # Create users & databases
  if [ "$KEYSTONE_DBPASS" ]; then
    echo "CREATE USER 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';" >> "$tempSqlFile"
    echo "CREATE DATABASE IF NOT EXISTS \`keystone\`;" >> "$tempSqlFile"
    echo "GRANT ALL ON \`keystone\`.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';" >> "$tempSqlFile"
  fi
  if [ "$GLANCE_DBPASS" ]; then
    echo "CREATE USER 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';" >> "$tempSqlFile"
    echo "CREATE DATABASE IF NOT EXISTS \`glance\`;" >> "$tempSqlFile"
    echo "GRANT ALL ON \`glance\`.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';" >> "$tempSqlFile"
  fi
  if [ "$NOVA_DBPASS" ]; then
    echo "CREATE USER 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';" >> "$tempSqlFile"
    echo "CREATE DATABASE IF NOT EXISTS \`nova\`;" >> "$tempSqlFile"
    echo "GRANT ALL ON \`nova\`.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';" >> "$tempSqlFile"
  fi
  if [ "$NEUTRON_DBPASS" ]; then
    echo "CREATE USER 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';" >> "$tempSqlFile"
    echo "CREATE DATABASE IF NOT EXISTS \`neutron\`;" >> "$tempSqlFile"
    echo "GRANT ALL ON \`neutron\`.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';" >> "$tempSqlFile"
  fi
  if [ "$CINDER_DBPASS" ]; then
    echo "CREATE USER 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';" >> "$tempSqlFile"
    echo "CREATE DATABASE IF NOT EXISTS \`cinder\`;" >> "$tempSqlFile"
    echo "GRANT ALL ON \`cinder\`.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';" >> "$tempSqlFile"
  fi
  echo 'FLUSH PRIVILEGES;' >> "$tempSqlFile"

  mysqld --init-file="$tempSqlFile" &
else
  mysqld &
fi

# Keystone setup
echo 'Keystone setup...'

sed -i "s#^connection.*#connection = mysql://keystone:$KEYSTONE_DBPASS@$CONTROLLER_HOST/keystone#" /etc/keystone/keystone.conf
if [ "$ADMIN_TOKEN" ]; then
  sed -i "s/^#admin_token.*/admin_token = $ADMIN_TOKEN/" /etc/keystone/keystone.conf
fi
sed -i "s/^#provider.*/provider = keystone.token.providers.uuid.Provider/" /etc/keystone/keystone.conf
sed -i "s/^#driver=keystone.token.*/driver=keystone.token.persistence.backends.sql.Token/" /etc/keystone/keystone.conf
sed -i "s/^#driver=keystone.contrib.revoke.*/driver = keystone.contrib.revoke.backends.sql.Revoke/" /etc/keystone/keystone.conf

su -s /bin/sh -c "keystone-all &" keystone

if [[ $INSTALL -eq 1 ]]; then
  su -s /bin/sh -c "keystone-manage db_sync" keystone

  # Creation of Tenant & User & Role
  echo 'Creation of Tenant / User / Role...'

  export SERVICE_TOKEN=$ADMIN_TOKEN
  export SERVICE_ENDPOINT=http://$CONTROLLER_HOST:35357/v2.0

  # Tenant / User / User-role create for admin
  keystone tenant-create --name admin --description "Admin Tenant"
  keystone user-create --name admin --pass $ADMIN_PASS --email $ADMIN_EMAIL
  keystone role-create --name admin
  keystone user-role-add --user admin --tenant admin --role admin

  # Tenant / User create for demo
  keystone tenant-create --name demo --description "Demo Tenant"
  keystone user-create --name demo --tenant demo --pass $DEMO_PASS --email $DEMO_EMAIL

  # Tenant create for service
  keystone tenant-create --name $ADMIN_TENANT_NAME --description "Service Tenant"

  # Service create for Identity
  name=`keystone service-list | awk '/ identity / {print $2}'`
  if [ -z $name ]; then
    keystone service-create --name keystone --type identity --description "OpenStack Identity"
  fi

  # Endpoint create for keystone service
  name=`keystone service-list | awk '/ identity / {print $2}'`
  endpoint=`keystone endpoint-list | awk '/ '$name' / {print $2}'`
  if [ -z "$endpoint" ]; then
    keystone endpoint-create --region $REGION_NAME --publicurl http://$CONTROLLER_HOST:5000/v2.0 --internalurl http://$CONTROLLER_HOST:5000/v2.0 --adminurl http://$CONTROLLER_HOST:35357/v2.0 --service_id $name
  fi

  ## FOR GLANCE
  keystone user-create --name glance --pass $GLANCE_PASS
  keystone user-role-add --user glance --tenant $ADMIN_TENANT_NAME --role admin

  name=`keystone service-list | awk '/ image / {print $2}'`
  if [ -z $name ]; then
    keystone service-create --name glance --type image --description "OpenStack Image Service"
  fi
  name=`keystone service-list | awk '/ image / {print $2}'`
  endpoint=`keystone endpoint-list | awk '/ '$name' / {print $2}'`
  if [ -z "$endpoint" ]; then
    keystone endpoint-create --region $REGION_NAME --publicurl http://$CONTROLLER_HOST:9292 --internalurl http://$CONTROLLER_HOST:9292 --adminurl http://$CONTROLLER_HOST:9292 --service_id $name
  fi

  ## FOR NOVA
  keystone user-create --name nova --pass $NOVA_PASS
  keystone user-role-add --user nova --tenant $ADMIN_TENANT_NAME --role admin

  name=`keystone service-list | awk '/ compute / {print $2}'`
  if [ -z $name ]; then
    keystone service-create --name nova --type compute --description "OpenStack Compute"
  fi
  name=`keystone service-list | awk '/ compute / {print $2}'`
  endpoint=`keystone endpoint-list | awk '/ '$name' / {print $2}'`
  if [ -z "$endpoint" ]; then
    keystone endpoint-create --region $REGION_NAME --publicurl http://$CONTROLLER_HOST:8774/v2/%\(tenant_id\)s --internalurl http://$CONTROLLER_HOST:8774/v2/%\(tenant_id\)s --adminurl http://$CONTROLLER_HOST:8774/v2/%\(tenant_id\)s --service_id $name
  fi

  ## FOR NEUTRON
  keystone user-create --name neutron --pass $NEUTRON_PASS
  keystone user-role-add --user neutron --tenant $ADMIN_TENANT_NAME --role admin

  name=`keystone service-list | awk '/ network / {print $2}'`
  if [ -z $name ]; then
    keystone service-create --name neutron --type network --description "OpenStack Networking"
  fi
  name=`keystone service-list | awk '/ network / {print $2}'`
  endpoint=`keystone endpoint-list | awk '/ '$name' / {print $2}'`
  if [ -z "$endpoint" ]; then
    keystone endpoint-create --region $REGION_NAME --publicurl http://$CONTROLLER_HOST:9696 --internalurl http://$CONTROLLER_HOST:9696 --adminurl http://$CONTROLLER_HOST:9696 --service_id $name
  fi
fi

# Glance setup
echo 'Glance setup...'
GLANCE_API=/etc/glance/glance-api.conf
GLANCE_REGISTRY=/etc/glance/glance-registry.conf
GLANCE_CACHE=/etc/glance/glance-cache.conf

### /etc/glance/glance-api.conf modify for MySQL & RabbitMQ
sed -i "s/# rpc_backend.*/rpc_backend = 'rabbit'/" $GLANCE_API
sed -i "s/rabbit_host.*/rabbit_host = controller/" $GLANCE_API
sed -i "s/rabbit_password.*/rabbit_password = $RABBIT_PASS/" $GLANCE_API
sed -i "s/sqlite_db.*/connection = mysql:\/\/glance:$GLANCE_DBPASS@$CONTROLLER_HOST\/glance/" $GLANCE_API
sed -i "s/backend = sqlalchemy.*/backend = mysql/" $GLANCE_API

### /etc/glance/glance-registry.conf for MySQL & RabbitMQ
sed -i "s/sqlite_db.*/connection = mysql:\/\/glance:$GLANCE_DBPASS@$CONTROLLER_HOST\/glance/" $GLANCE_REGISTRY
sed -i "s/backend = sqlalchemy.*/backend = mysql/" $GLANCE_REGISTRY

### /etc/glance/glance-api.conf modify for Keystone Service
sed -i "s/^identity_uri.*/identity_uri = http:\/\/$CONTROLLER_HOST:35357/" $GLANCE_API
sed -i "s/^admin_tenant_name.*/admin_tenant_name = $ADMIN_TENANT_NAME/" $GLANCE_API
sed -i "s/^admin_user.*/admin_user = glance/" $GLANCE_API
sed -i "s/^admin_password.*/admin_password = $GLANCE_PASS/" $GLANCE_API
sed -i "s/^#flavor.*/flavor = keystone/" $GLANCE_API
sed -i "s/^#container_formats.*/container_formats=ami,ari,aki,bare,ovf,ova,docker/" $GLANCE_API

### /etc/glance/glance-registry.conf for Keystone Service
sed -i "s/^identity_uri.*/identity_uri = http:\/\/$CONTROLLER_HOST:35357/" $GLANCE_REGISTRY
sed -i "s/^admin_tenant_name.*/admin_tenant_name = $ADMIN_TENANT_NAME/" $GLANCE_REGISTRY
sed -i "s/^admin_user.*/admin_user = glance/" $GLANCE_REGISTRY
sed -i "s/^admin_password.*/admin_password = $GLANCE_PASS/" $GLANCE_REGISTRY
sed -i "s/^#flavor.*/flavor = keystone/" $GLANCE_REGISTRY

### glance image directory / files owner:group change
chown -R glance:glance /var/lib/glance

# excution for glance service

if [[ $INSTALL -eq 1 ]]; then
  su -s /bin/sh -c "glance-manage db_sync" glance
fi
su -s /bin/sh -c "glance-registry &" glance
su -s /bin/sh -c "glance-api &" glance

## Nova setup
echo 'Nova setup...'
NOVA_CONF=/etc/nova/nova.conf

echo "" >> $NOVA_CONF
echo "rpc_backend = rabbit" >> $NOVA_CONF
echo "rabbit_host = $CONTROLLER_HOST" >> $NOVA_CONF
echo "rabbit_password = $RABBIT_PASS" >> $NOVA_CONF
echo "" >> $NOVA_CONF
echo "my_ip = $CONTROLLER_HOST" >> $NOVA_CONF
echo "vncserver_listen = $CONTROLLER_HOST" >> $NOVA_CONF
echo "vncserver_proxyclient_address = $CONTROLLER_HOST" >> $NOVA_CONF
echo "" >> $NOVA_CONF
echo "auth_strategy = keystone" >> $NOVA_CONF
echo "" >> $NOVA_CONF

######## Neutron Setup Start ####################
echo "network_api_class = nova.network.neutronv2.api.API" >> $NOVA_CONF
echo "security_group_api = neutron" >> $NOVA_CONF
echo "linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver" >> $NOVA_CONF
#echo "libvirt_vif_driver = nova.virt.libvirt.vif.NeutronLinuxBridgeVIFDriver" >> $NOVA_CONF

echo "fixed_ip_disassociate_timeout=30" >> $NOVA_CONF
echo "enable_instance_password=False" >> $NOVA_CONF

echo "firewall_driver = nova.virt.firewall.NoopFirewallDriver" >> $NOVA_CONF
echo "" >> $NOVA_CONF
######## Neutron Setup End ####################

echo "" >> $NOVA_CONF
echo "[keystone_authtoken]" >> $NOVA_CONF
echo "auth_uri = http://$CONTROLLER_HOST:5000/v2.0" >> $NOVA_CONF
echo "identity_uri = http://$CONTROLLER_HOST:35357" >> $NOVA_CONF
echo "admin_tenant_name = $ADMIN_TENANT_NAME"  >> $NOVA_CONF
echo "admin_user = nova" >> $NOVA_CONF
echo "admin_password = $NOVA_PASS" >> $NOVA_CONF
echo "" >> $NOVA_CONF

######### Neutron Setup Start ######################
echo "[neutron]" >> $NOVA_CONF
echo "url = http://$CONTROLLER_HOST:9696" >> $NOVA_CONF
echo "auth_strategy = keystone" >> $NOVA_CONF
echo "admin_auth_url = http://$CONTROLLER_HOST:35357/v2.0" >> $NOVA_CONF
echo "admin_tenant_name = $ADMIN_TENANT_NAME" >> $NOVA_CONF
echo "admin_username = neutron" >> $NOVA_CONF
echo "admin_password = $NEUTRON_PASS" >> $NOVA_CONF
echo "service_metadata_proxy = True" >> $NOVA_CONF
echo "metadata_proxy_shared_secret = METADATA_SECRET" >> $NOVA_CONF
######### Neutron Setup End ######################

# Database Section
echo "" >> $NOVA_CONF
echo "[database]" >> $NOVA_CONF
echo "connection=mysql://nova:$NOVA_DBPASS@$CONTROLLER_HOST/nova" >> $NOVA_CONF

# Glance Section
echo "" >> $NOVA_CONF
echo "[glance]" >> $NOVA_CONF
echo "host = $CONTROLLER_HOST" >> $NOVA_CONF

# apache2 & memcached service starting for Horizon Service
if [ "$TIME_ZONE" ]; then
  sed -i "s|^TIME_ZONE.*|TIME_ZONE = \"$TIME_ZONE\"|" /etc/openstack-dashboard/local_settings.py
fi

# For related dashboard service start
service memcached start
service apache2 start

# Nova service start
if [[ $INSTALL -eq 1 ]]; then
  su -s /bin/sh -c "nova-manage db sync" nova
fi

su -s /bin/sh -c "nova-api --config-file=$NOVA_CONF &" nova
su -s /bin/sh -c "nova-cert --config-file=$NOVA_CONF &" nova
su -s /bin/sh -c "nova-consoleauth --config-file=$NOVA_CONF &" nova
su -s /bin/sh -c "nova-scheduler --config-file=$NOVA_CONF &" nova
su -s /bin/sh -c "nova-conductor --config-file=$NOVA_CONF &" nova
su -s /bin/sh -c "nova-novncproxy --config-file=$NOVA_CONF &" nova

## Neutron Setup
echo 'Neutron Setup...'
NEUTRON_CONF=/etc/neutron/neutron.conf
ML2_CONF=/etc/neutron/plugins/ml2/ml2_conf.ini

export OS_TENANT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://$CONTROLLER_HOST:5000/v2.0/
export OS_NO_CACHE=1

### /etc/neutron/neutron.conf modify
sed -i "s/# connection = mysql.*/connection = mysql:\/\/neutron:$NEUTRON_DBPASS@$CONTROLLER_HOST\/neutron/" $NEUTRON_CONF
sed -i "s/connection = sqlite:.*/#connection = sqlite:/" $NEUTRON_CONF
sed -i "s/#rpc_backend=rabbit.*/rpc_backend=rabbit/" $NEUTRON_CONF
sed -i "s/#rabbit_host=localhost.*/rabbit_host=$CONTROLLER_HOST/" $NEUTRON_CONF
sed -i "s/#rabbit_password=guest.*/rabbit_password=$RABBIT_PASS/" $NEUTRON_CONF
sed -i "s/# auth_strategy = keystone.*/auth_strategy = keystone/" $NEUTRON_CONF

sed -i "s/^auth_host.*/auth_uri = http:\/\/$CONTROLLER_HOST:5000\/v2.0/" $NEUTRON_CONF
sed -i "s/^auth_port.*/identity_uri = http:\/\/$CONTROLLER_HOST:35357/" $NEUTRON_CONF

sed -i "s/admin_tenant_name.*/admin_tenant_name = $ADMIN_TENANT_NAME/" $NEUTRON_CONF
sed -i "s/^admin_user.*/admin_user = neutron/" $NEUTRON_CONF
sed -i "s/^admin_password.*/admin_password = $NEUTRON_PASS/" $NEUTRON_CONF
sed -i "s/# service_plugins.*/service_plugins = router/" $NEUTRON_CONF
sed -i "s/# allow_overlapping_ips.*/allow_overlapping_ips = True/" $NEUTRON_CONF
sed -i "s/# notify_nova_on_port_status_changes.*/notify_nova_on_port_status_changes = True/" $NEUTRON_CONF
sed -i "s/# notify_nova_on_port_data_changes.*/notify_nova_on_port_data_changes = True/" $NEUTRON_CONF
sed -i "s/# nova_url.*/nova_url = http:\/\/$CONTROLLER_HOST:8774\/v2/" $NEUTRON_CONF
sed -i "s/# nova_admin_auth_url.*/nova_admin_auth_url = http:\/\/$CONTROLLER_HOST:35357\/v2.0/" $NEUTRON_CONF
sed -i "s/# nova_region_name.*/nova_region_name = $REGION_NAME/" $NEUTRON_CONF
sed -i "s/# nova_admin_username.*/nova_admin_username = nova/" $NEUTRON_CONF
sed -i "s/# nova_admin_password.*/nova_admin_password = $NOVA_PASS/" $NEUTRON_CONF
NOVA_SERVICE_ID=$(keystone tenant-list | awk '/ '$ADMIN_TENANT_NAME' / {print $2}')
sed -i "s/# nova_admin_tenant_id.*/nova_admin_tenant_id = $NOVA_SERVICE_ID/" $NEUTRON_CONF

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
su -s /bin/sh -c "neutron-server --config-file $NEUTRON_CONF --config-file $ML2_CONF" neutron
