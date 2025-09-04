#!/bin/bash
set -e

PARENT_PATH=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)

# Importar funções comuns
source "${PARENT_PATH}/utils/common_functions.sh"

VM_NAME="asterisk"
JASTERISK_TAR_URL="https://github.com/brunomrtns/basterisk/releases/download/1.0.0/basterisk.tar"
JASTERISK_FALLBACK="/home/bruno/Downloads/basterisk.tar"
JASTERISK_TAR_LOCAL="${PARENT_PATH}/basterisk.tar"
HOST_UDP_PORT="5060"
HOST_RTP_START_PORT="4020"
HOST_RTP_END_PORT="4099"
MAC_VLAN_PROFILE_PATH="${PARENT_PATH}/macvlanprofile.yml"
PARENT_IF="enp2s0"  

if ! ip link show ${PARENT_IF} >/dev/null 2>&1; then
    echo "❌ Erro: Interface ${PARENT_IF} não encontrada!"
    echo "🔍 Interfaces disponíveis:"
    ip link show | grep '^[0-9]' | cut -d: -f2 | grep -v lo | sed 's/^ */   /'
    echo ""
    echo "💡 Edite a script e altere PARENT_IF para a interface correta"
    exit 1
fi

echo "✅ Interface ${PARENT_IF} encontrada e será usada para MACVLAN"

echo "🔄 Garantindo que estamos no project default..."
sudo incus project switch default

echo "🔄 Criando/atualizando profile macvlan..."
if ! sudo incus profile show macvlanprofile >/dev/null 2>&1; then
    sudo incus profile create macvlanprofile
    echo "Profile macvlanprofile criado."
fi

sudo incus profile edit macvlanprofile < ${MAC_VLAN_PROFILE_PATH}
echo "Profile macvlanprofile atualizado com sucesso."

echo "Criando VM ${VM_NAME}..."
sudo incus remove ${VM_NAME} --force || true

echo "Lançando VM Ubuntu Jammy..."
timeout 60 sudo incus launch images:ubuntu/jammy ${VM_NAME} --profile macvlanprofile --vm || {
    echo "❌ Timeout na criação da VM!"
    echo "💡 Possíveis problemas:"
    echo "   - MACVLAN conflitando com NetworkManager"
    echo "   - Interface ${PARENT_IF} não suporta MACVLAN"
    echo "   - Recursos insuficientes"
    exit 1
}

wait_system_ready "${VM_NAME}"

echo "Reiniciando VM..."
nohup sudo incus restart ${VM_NAME} >/dev/null 2>&1 &

wait_system_ready "${VM_NAME}"

echo "Verificando se VM reiniciou corretamente..."
for i in {1..15}; do
    STATUS=$(sudo incus list ${VM_NAME} -c s --format csv)
    if [ "$STATUS" = "RUNNING" ]; then
        echo "✅ VM reiniciada com sucesso!"
        break
    fi
    echo "Aguardando VM reiniciar: $STATUS (tentativa $i/15)"
    sleep 2
done

if [ "$STATUS" != "RUNNING" ]; then
    echo "❌ VM não conseguiu reiniciar corretamente"
    sudo incus list ${VM_NAME}
    exit 1
fi

echo "Verificando se MACVLAN conseguiu IPv4..."
sleep 3
VM_IP=$(get_vm_ip "${VM_NAME}" "list")
if [ $? -ne 0 ]; then
    echo "❌ MACVLAN falhou (WiFi não suporta). Use proxy."
    echo ""
    echo "🔍 Diagnóstico completo:"
    echo "1. Status da VM:"
    sudo incus list ${VM_NAME}
    echo ""
    echo "2. Interfaces na VM:"
    sudo incus exec ${VM_NAME} -- ip addr show 2>/dev/null || echo "   VM não acessível"
    echo ""
    echo "3. Interface física do host:"
    ip addr show ${PARENT_IF}
    echo ""
    echo "4. DHCP lease (se disponível):"
    sudo journalctl -u NetworkManager --no-pager -n 20 | grep -i dhcp || echo "   Nenhum log DHCP encontrado"
    exit 1
else
    echo "✅ Success! IPv4: $VM_IP"
fi
echo "VM IP: ${VM_IP}"
sleep 5

# Instalar dependências básicas
install_vm_basics "${VM_NAME}"

# Testar conectividade UDP direta
test_udp_connectivity "${VM_NAME}" "${VM_IP}" "5060" "direct"

# Instalar Asterisk
install_asterisk "${VM_NAME}" "${JASTERISK_TAR_LOCAL}"

# Configurar rota para acesso do host à VM
echo "🛣️  Configurando rota para permitir acesso do host à VM..."
GATEWAY=$(ip route show default | awk '/default/ {print $3}' | head -1)

if [ -n "$GATEWAY" ]; then
    sudo ip route del ${VM_IP} 2>/dev/null || true
    if sudo ip route add ${VM_IP} via ${GATEWAY}; then
        echo "✅ Rota configurada com sucesso via gateway ${GATEWAY}"
        if ping -c 2 -W 3 ${VM_IP} > /dev/null 2>&1; then
            echo "🎯 Conectividade do host para VM confirmada!"
        else
            echo "⚠️  Rota criada, mas ping falhou (normal em alguns casos)"
        fi
    else
        echo "⚠️  Falha ao criar rota, use: sudo ip route add ${VM_IP} via ${GATEWAY}"
    fi
else
    echo "⚠️  Gateway não encontrado automaticamente"
fi

# Exibir informações finais
show_final_info "${VM_IP}" "macvlan" "" "${HOST_UDP_PORT}" "${HOST_RTP_START_PORT}" "${HOST_RTP_END_PORT}" "${VM_NAME}"
