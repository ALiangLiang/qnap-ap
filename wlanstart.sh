#!/bin/bash -e

# Check if running in privileged mode
if [ ! -w "/sys" ] ; then
    echo "[Error] Not running in privileged mode."
    exit 1
fi

# Default values
true ${INTERFACE:=wlan0}
true ${SUBNET:=192.168.254.0}
true ${AP_ADDR:=192.168.254.1}
true ${SSID:=qnapap}
true ${CHANNEL:=11}
true ${WPA_PASSPHRASE:=passw0rd}
true ${HW_MODE:=g}
true ${DRIVER:=rtl871xdrv}
true ${MODE:=host}
true ${TZ:=Etc/UTC}
true ${LOGGING:=0}

# Attach interface to container in guest mode
if [ "$MODE" == "guest"  ]; then
    echo "Attaching interface to container"

    CONTAINER_ID=$(cat /proc/self/cgroup | grep -o  -e "/docker/.*" | head -n 1| sed "s/\/docker\/\(.*\)/\\1/")
    CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' ${CONTAINER_ID})
    CONTAINER_IMAGE=$(docker inspect -f '{{.Config.Image}}' ${CONTAINER_ID})

    docker run -t --privileged --net=host --pid=host --rm --entrypoint /bin/sh ${CONTAINER_IMAGE} -c "
        PHY=\$(echo phy\$(iw dev ${INTERFACE} info | grep wiphy | tr ' ' '\n' | tail -n 1))
        iw phy \$PHY set netns ${CONTAINER_PID}
    "

    ip link set ${INTERFACE} name wlan0

    INTERFACE=wlan0
fi

cat > "/etc/hostapd/hostapd.conf" <<EOF
# Basic configuration
interface=${INTERFACE}
ssid=${SSID}
channel=${CHANNEL}

# WPA and WPA2 configuration
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${WPA_PASSPHRASE}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
beacon_int=100
wmm_enabled=1
eap_reauth_period=360000000

# Hardware configuration
driver=${DRIVER}
ieee80211n=1
hw_mode=${HW_MODE}
device_name=RTL8192CU
manufacturer=Realtek

# CTRL-Interface
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0

# Logging
logger_syslog=-1
logger_syslog_level=3
logger_stdout=-1
logger_stdout_level=2

wpa_group_rekey=600
wpa_ptk_rekey=600
wpa_gmk_rekey=86400
EOF

# unblock wlan
rfkill unblock wlan

echo "Setting interface ${INTERFACE}"

# Setup interface and restart DHCP service 
ip link set ${INTERFACE} up
ip addr flush dev ${INTERFACE}
ip addr add ${AP_ADDR}/24 dev ${INTERFACE}

# NAT settings
echo "NAT settings ip_dynaddr, ip_forward"

for i in ip_dynaddr ip_forward ; do 
  if [ $(cat /proc/sys/net/ipv4/$i) ]; then
    echo $i already 1 
  else
    echo "1" > /proc/sys/net/ipv4/$i
  fi
done

cat /proc/sys/net/ipv4/ip_dynaddr 
cat /proc/sys/net/ipv4/ip_forward

if [ "${OUTGOINGS}" ] ; then
   ints="$(sed 's/,\+/ /g' <<<"${OUTGOINGS}")"
   for int in ${ints}
   do
      echo "Setting iptables for outgoing traffics on ${int}..."
      iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -o ${int} -j MASQUERADE > /dev/null 2>&1 || true
      iptables -t nat -A POSTROUTING -s ${SUBNET}/24 -o ${int} -j MASQUERADE
   done
else
   echo "Setting iptables for outgoing traffics on all interfaces..."
   iptables -t nat -D POSTROUTING -s ${SUBNET}/24 -j MASQUERADE > /dev/null 2>&1 || true
   iptables -t nat -A POSTROUTING -s ${SUBNET}/24 -j MASQUERADE
fi
echo "Configuring DHCP server .."

cat > "/etc/dhcp/dhcpd.conf" <<EOF
option domain-name-servers 8.8.8.8, 8.8.4.4;
option subnet-mask 255.255.255.0;
option routers ${AP_ADDR};
subnet ${SUBNET} netmask 255.255.255.0 {
  range ${SUBNET::-1}100 ${SUBNET::-1}200;
}
EOF

echo "Starting DHCP server .."
dhcpd ${INTERFACE}

echo "Starting HostAP daemon ..."
if [ "$LOGGING" == "1" ]; then
  /usr/local/bin/hostapd /etc/hostapd/hostapd.conf -dd | TZ=$TZ ts "%b %d %H:%M:%S : " | tee /var/log/hostapd.log
else
  /usr/local/bin/hostapd /etc/hostapd/hostapd.conf -dd | TZ=$TZ ts "%b %d %H:%M:%S : "
fi
