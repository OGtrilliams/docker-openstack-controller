FROM ubuntu:14.04

MAINTAINER EnnWeb Cloud <cloud@ennweb.com>

ENV MYSQL_ROOT_PASSWORD openstack

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
  sed -Ei 's/^(bind-address|log)/#&/' /etc/mysql/my.cnf && \
  sed -i "s/^datadir.*/datadir = \/data/mysql" /etc/mysql/my.cnf

VOLUME ["/data"]

Add entrypoint.sh /

EXPOSE 3306 35357 9292 5000 5672 8774 8776 6080 9696 80

ENTRYPOINT ["/entrypoint.sh"]
