FROM ubuntu:14.04

MAINTAINER EnnWeb Cloud <cloud@ennweb.com>

ENV \
  DEBIAN_FRONTEND=noninteractive \
  FORCE_INSTALL=no \
  STORE_BACKEND=file \
  SITE_BRANDING="Openstack Dashboard" \
  RABBIT_USER=openstack \
  RABBIT_PASS=rabbitpass \
  MYSQL_SETUP=local \
  MYSQL_HOST=controller \
  MYSQL_USER=root \
  MYSQL_PASS=mysqlpass \
  CONTROLLER_HOST=controller \
  CONTROLLER_IP=0.0.0.0 \
  ADMIN_TOKEN=ADMIN \
  REGION_NAME=RegionOne \
  KEYSTONE_DBPASS=openstack \
  KEYSTONE_PASS=keystonepass \
  GLANCE_DBPASS=openstack \
  GLANCE_PASS=glancepass \
  NOVA_DBPASS=openstack \
  NOVA_PASS=novapass \
  NEUTRON_DBPASS=openstack \
  NEUTRON_PASS=neutronpass \
  CINDER_DBPASS=openstack \
  CINDER_PASS=cinderpass \
  ADMIN_PASS=adminpass \
  DEMO_PASS=demopass \
  TIME_ZONE=Europe/London \
  UUID=b3d14bb5-b523-4f24-aa56-0ab3fac96dc6 \
  METADATA_SECRET=metadatasecret \
  HA_MODE=L3_HA

RUN \
  apt-get update && \
  apt-get install -y software-properties-common && \
  add-apt-repository  -y cloud-archive:liberty && \
  apt-get update && apt-get -y dist-upgrade && \
  apt-get install -y python-openstackclient mariadb-server python-pymysql mongodb-server mongodb-clients python-pymongo \
    rabbitmq-server keystone apache2 libapache2-mod-wsgi memcached python-memcache glance python-glanceclient \
    nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient neutron-server \
    neutron-plugin-ml2 python-neutronclient conntrack cinder-api cinder-scheduler cinder-backup cinder-volume python-cinderclient \
    python-rbd python-ceph ceph-common openstack-dashboard && \
  apt-get remove -y --auto-remove openstack-dashboard-ubuntu-theme && \
  apt-get autoclean && \
  apt-get autoremove && \
  rm -rf /var/lib/apt/lists/*

VOLUME ["/data"]

ADD entrypoint.sh /
ADD config/wsgi-keystone.conf /etc/apache2/sites-available/wsgi-keystone.conf

EXPOSE 80 3306 5000 5672 6080 8774 8776 9292 9696 35357

ENTRYPOINT ["/entrypoint.sh"]
