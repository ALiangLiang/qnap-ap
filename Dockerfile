FROM ubuntu:16.04

MAINTAINER Wei-Liang Liou <me@aliangliang.top>

WORKDIR /root
RUN apt update &&\
    apt install -y bash rfkill iptables isc-dhcp-server docker iproute2 iw wget make gcc
RUN wget https://github.com/jenssegers/RTL8188-hostapd/archive/v2.0.tar.gz -O - | tar -zxvf &&\
    cd /root/RTL8188-hostapd-2.0/hostapd &&\
    make &&\
    make install
RUN echo "" > /var/lib/dhcp/dhcpd.leases
ADD wlanstart.sh /bin/wlanstart.sh

ENTRYPOINT [ "/bin/wlanstart.sh" ]
