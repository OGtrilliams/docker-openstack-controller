cat Dockerfile 
FROM centos:latest

MAINTAINER Treva Williams <tribecca@tribecc.us>

ENV \
  FORCE_INSTALL=no \
  STORE_BACKEND=file \
  SITE_BRANDING="Cloud Assessments - Openstack Dashboard" \
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
  TIME_ZONE=America/Chicago \
  UUID=b3d14bb5-b523-4f24-aa56-0ab3fac96dc6 \
  METADATA_SECRET=metadatasecret \
  HA_MODE=L3_HA

RUN \
yum -y update && yum -y install centos-release-openstack-newton && yum -y install python-openstackclient mariadb-server python2-PyMySQL mongodb-server mongodb-clients python-pymongo rabbitmq-server openstack-keystone httpd memcached mod_wsgi python-memcached openstack-glance python2-glanceclient openstack-nova-api openstack-nova-cert openstack-nova-conductor openstack-nova-consoleauth openstack-nova-novncproxy openstack-nova-scheduler python2-novaclient openstack-neutron openstack-neutron-ml2 python2-neutronclient openstack-cinder-api openstack-cinder-scheduler openstack-cinder-backup openstack-cinder-volume python2-cinderclient python-rbd ceph ceph-common openstack-dashboard

VOLUME ["/data"]
ADD entrypoint.sh /
ADD config/wsgi-keystone.conf /usr/share/keystone/wsgi-keystone.conf

EXPOSE 80 3306 5000 5672 6080 8774 8776 9292 9696 35357

ENTRYPOINT ["/entrypoint.sh"]
