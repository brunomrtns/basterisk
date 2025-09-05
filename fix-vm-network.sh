#!/bin/bash

set -e

# Checa se está sendo executado como root
[ "$(id -u)" -ne 0 ] && echo "Este script deve ser executado como root." && exit 1

# Detecta interface ativa que não seja loopback nem a bridge do Incus
OUT_IF=$(ip -br a | awk '$2=="UP" && $1!="lo" && $1!="incusbr0" {print $1; exit}')

if [ -z "$OUT_IF" ]; then
    echo "Não foi possível detectar a interface de rede ativa."
    exit 1
fi

echo "Interface de saída detectada: $OUT_IF"

# Regras de iptables
iptables -L FORWARD -v -n
iptables -P FORWARD ACCEPT

iptables -A FORWARD -i incusbr0 -o "$OUT_IF" -j ACCEPT
iptables -A FORWARD -o incusbr0 -i "$OUT_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
