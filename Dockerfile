FROM ubuntu:14.04

MAINTAINER EnnWeb Cloud <cloud@ennweb.com>

ENV DEBIAN_FRONTEND noninteractive
ENV FORCE_INSTALL 1
ENV CONTROLLER_HOST controller
ENV HA_MODE L3_HA
ENV TIME_ZONE Europe/London
ENV ADMIN_TOKEN ADMIN
ENV REGION_NAME RegionOne
ENV RABBIT_USER openstack
ENV RABBIT_PASS rabbitpass
ENV MYSQL_SETUP local
ENV MYSQL_HOST controller
ENV MYSQL_USER root
ENV MYSQL_PASS mysqlpass
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
ENV ADMIN_PASS adminpass
ENV DEMO_PASS demopass
ENV METADATA_SECRET metadatasecret

RUN \
  apt-get update && \
  apt-get install -y software-properties-common && \
  add-apt-repository  -y cloud-archive:liberty && \
  apt-get update && apt-get -y dist-upgrade && \
  apt-get install -y python-openstackclient mariadb-server python-pymysql mongodb-server mongodb-clients python-pymongo \
    rabbitmq-server keystone apache2 libapache2-mod-wsgi memcached python-memcache glance python-glanceclient \
    nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient neutron-server \
    neutron-plugin-ml2 python-neutronclient openstack-dashboard && \
  apt-get remove -y --auto-remove openstack-dashboard-ubuntu-theme && \
  apt-get autoclean && \
  apt-get autoremove && \
  rm -rf /var/lib/apt/lists/*

VOLUME ["/data"]

ADD entrypoint.sh /
ADD config/wsgi-keystone.conf /etc/apache2/sites-available/wsgi-keystone.conf

EXPOSE 80 3306 5000 5672 6080 8774 8776 9292 9696 35357

ENTRYPOINT ["/entrypoint.sh"]
