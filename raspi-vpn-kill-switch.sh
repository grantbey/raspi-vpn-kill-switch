#!/bin/bash

clear

if [ "$#" -ne 1 ]; then
    echo "$0 <interface name>"
    exit -1
fi

IFACE=$1
echo "Using interface: $1"

echo "Killing previous instances of openvpn"
killall -9 openvpn

echo "Flushing iptables rules"
iptables -F
iptables -t nat -F
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

echo "Current IP: `curl -s ifconfig.co`"

# Temporarily block forwarding so nothing leaks if we restart this script
# Disable all ipv6 networking
sysctl -w net.ipv4.ip_forward=0
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sysctl -w net.ipv6.conf.eth0.disable_ipv6=1

echo "Blocking all traffic by default"
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# allow traffic from established connections
echo "Allowing already established traffic"
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# allow ssh
echo "Allowing incoming/outgoing SSH established on all interfaces"
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 22 -j ACCEPT

echo "Allowing DHCP traffic"
iptables -A INPUT -j ACCEPT -p udp --dport 67:68 --sport 67:68
iptables -A OUTPUT -j ACCEPT -p udp --dport 67:68 --sport 67:68

echo "Allowing loopback interface and ping"
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o tun0 -p icmp -j ACCEPT

echo "Allowing traffic on the local network"
# Set your local network IP range here to allow local connections
iptables -A OUTPUT -d 192.168.1.0/24 -j ACCEPT
iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT

echo "Allowing VPN DNS traffic"
# This is the DNS server of my VPN provider
iptables -A OUTPUT -d 10.4.0.1 -j ACCEPT

echo "Allowing openvpn traffic"
# I found this group method didn't work
# iptables -A OUTPUT -j ACCEPT -m owner --gid-owner openvpn
# Alternately, I simply allowed traffic destined for my VPN server on the specified port
# This information should come from your VPN provider
iptables -A OUTPUT -p udp -m udp -d 134.19.179.186 --dport 2018 -j ACCEPT
iptables -A OUTPUT -o tun0 -j ACCEPT
iptables -A INPUT -i tun0 -j ACCEPT

echo "Starting openvpn"
openvpn --verb 0 --daemon --config /usr/src/openvpn/AirVPN_Netherlands_UDP-2018.ovpn &

echo "Waiting for VPN to initialize"
sleep 10

echo "Current IP: `curl -s ifconfig.co`"

echo "Updating myanonymouse dynamic seedbox IP"
/usr/src/dynamic-ip/update-ip.sh
