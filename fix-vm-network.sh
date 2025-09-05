#!/bin/bash

set -e

[ "$(id -u)" -ne 0 ] && echo "Este script deve ser executado como root." && exit 1

iptables -L FORWARD -v -n
iptables -P FORWARD ACCEPT
iptables -A FORWARD -i incusbr0 -o enp2s0 -j ACCEPT
iptables -A FORWARD -o incusbr0 -i enp2s0 -m state --state RELATED,ESTABLISHED -j ACCEPT
