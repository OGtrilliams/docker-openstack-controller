FROM ubuntu:14.04

MAINTAINER EnnWeb Cloud <cloud@ennweb.com>

ENV CONTROLLER_HOST controller
ENV HA_MODE L3_HA
ENV TIME_ZONE Europe/London
ENV ADMIN_TOKEN ADMIN
ENV REGION_NAME RegionOne
ENV RABBIT_PASS rabbitpass
ENV MYSQL_ROOT_PASSWORD mysqlpass
ENV KEYSTONE_DBPASS openstack
ENV KEYSTONE_PASS keystonepass
ENV GLANCE_DBPASS openstack
ENV GLANCE_PASS glancepass
ENV NOVA_DBPASS openstack
ENV NOVA_PASS novapass
ENV NEUTRON_DBPASS openstack
ENV NEUTRON_PASS neutronpass
ENV CINDER_DBPASS openstack
ENV CINDER_PASS cinderpass
ENV ADMIN_TENANT_NAME service
ENV ADMIN_EMAIL admin@localhost
ENV ADMIN_PASS adminpass
ENV DEMO_EMAIL demo@localhost
ENV DEMO_PASS demopass

RUN \
  { \
    echo "mysql-server-5.5 mysql-server/root_password password $MYSQL_ROOT_PASSWORD"; \
    echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"; \
    echo "mysql-server-5.5 mysql-server/root_password seen true"; \
    echo "mysql-server-5.5 mysql-server/root_password_again seen true"; \
  } | debconf-set-selections && \
  apt-get update && \
  apt-get -y install software-properties-common python-software-properties && \
  add-apt-repository -y cloud-archive:liberty && \
  apt-get update && \
  apt-get -y dist-upgrade && \
  apt-get install -y mysql-server python-mysqldb rabbitmq-server keystone python-keyring glance nova-api \
    nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient apache2 \
    memcached libapache2-mod-wsgi openstack-dashboard neutron-server neutron-plugin-ml2 python-neutronclient && \
  apt-get remove --auto-remove openstack-dashboard-ubuntu-theme && \
  sed -Ei 's/^(bind-address|log)/#&/' /etc/mysql/my.cnf && \
  sed -i "s/^datadir.*/datadir = \/data\/mysql/" /etc/mysql/my.cnf

VOLUME ["/data"]

Add entrypoint.sh /

EXPOSE 3306 35357 9292 5000 5672 8774 8776 6080 9696 80

ENTRYPOINT ["/entrypoint.sh"]
