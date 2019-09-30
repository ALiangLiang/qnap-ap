FROM ubuntu:16.04

MAINTAINER Wei-Liang Liou <me@aliangliang.top>

RUN apt update &&\
    apt install -y bash rfkill iptables isc-dhcp-server docker iproute2 iw wget make gcc moreutils tzdata
RUN wget https://github.com/jenssegers/RTL8188-hostapd/archive/v2.0.tar.gz -O - | tar -zxv
RUN cd /RTL8188-hostapd-2.0/hostapd &&\
    make &&\
    make install
RUN echo "" > /var/lib/dhcp/dhcpd.leases

ADD wlanstart.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]
