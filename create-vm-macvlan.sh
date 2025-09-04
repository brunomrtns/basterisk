#!/bin/bash

set -e

PARENT_PATH=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)

source "${PARENT_PATH}/wait_system_ready"

VM_NAME="asterisk"
JASTERISK_TAR_PATH="/home/bruno/Downloads/jasterisk.tar"
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
sudo incus restart ${VM_NAME} >/dev/null 2>&1 &

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
VM_IP=$(sudo incus list ${VM_NAME} -c 4 --format csv | cut -d' ' -f1)

if [ -n "$VM_IP" ] && [ "$VM_IP" != "-" ]; then
    echo "✅ Success! IPv4: $VM_IP"
else
    echo "❌ MACVLAN falhou (WiFi não suporta). Use proxy."
    exit 1
fi

if [ -z "$VM_IP" ] || [ "$VM_IP" = "-" ]; then
    echo "❌ MACVLAN com WiFi falhou. Use cabo ethernet ou proxy."
    exit 1
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
fi
echo "VM IP: ${VM_IP}"
sleep 5

echo "🔍 Testando conectividade UDP direta com a VM..."

sudo incus exec ${VM_NAME} -- bash -c "
    apt update -y && apt install -y netcat-openbsd tcpdump > /dev/null 2>&1
"

TEST_ID="direct-test-$(date +%s)-$$"
echo "ID do teste: $TEST_ID"

echo "Iniciando captura de pacotes UDP na VM..."
sudo incus exec ${VM_NAME} -- bash -c "
    timeout 10 tcpdump -i any udp port 5060 -A -n > /tmp/udp_test.log 2>&1 &
    echo \$! > /tmp/tcpdump.pid
" &

sleep 3


echo "Enviando pacote de teste direto para VM: ${VM_IP}:5060"
echo "DIRECT_TEST_${TEST_ID}_SUCCESS" | nc -u -w2 ${VM_IP} 5060 2>/dev/null || echo "Comando nc executado"

sleep 4


sudo incus exec ${VM_NAME} -- bash -c "pkill tcpdump 2>/dev/null || true"
sleep 1

PACKET_FOUND=$(sudo incus exec ${VM_NAME} -- bash -c "
    if [ -f /tmp/udp_test.log ]; then
        grep -c 'DIRECT_TEST_${TEST_ID}_SUCCESS' /tmp/udp_test.log 2>/dev/null || echo '0'
    else
        echo '0'
    fi
")

echo "Pacotes com ID encontrados: $PACKET_FOUND"

if [ "$PACKET_FOUND" -ge 1 ]; then
    echo "✅ Conectividade UDP direta funcionando! Pacote chegou à VM."
    echo "Log do tcpdump mostrando pacote:"
    sudo incus exec ${VM_NAME} -- grep -A2 -B2 "DIRECT_TEST_${TEST_ID}_SUCCESS" /tmp/udp_test.log 2>/dev/null || true
else
    echo "⚠️  Teste UDP direto falhou, mas isso pode ser normal com MACVLAN do host."
    echo "A VM pode estar acessível de outros dispositivos da rede."
fi

sudo incus exec ${VM_NAME} -- mkdir -p /opt/asterisk-installer

echo "Enviando jasterisk.tar para a VM..."
cat $JASTERISK_TAR_PATH | sudo incus exec ${VM_NAME} -- tee /opt/asterisk-installer/jasterisk.tar > /dev/null

echo "Instalando Asterisk..."
sudo incus exec ${VM_NAME} -- bash -c "
	apt update -y && \
    apt upgrade -y && \
    apt autoremove -y && \
    apt autoclean -y && \ 
    apt install -y tree nano && \
    cd /opt/asterisk-installer && \
    tar xvf jasterisk.tar && \
    cd jasterisk/jasterisk && \
    chmod +x INSTALL.sh && \
    ./INSTALL.sh
"

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

echo ""
echo "✅ Asterisk instalado com MACVLAN + Rota configurada!"
echo ""
echo "📋 Informações de conectividade:"
echo "   VM IP na rede local: ${VM_IP}"
echo "   SIP TCP/UDP: ${VM_IP}:${HOST_UDP_PORT}"
echo "   RTP UDP: ${VM_IP}:${HOST_RTP_START_PORT}-${HOST_RTP_END_PORT}"
echo "   Interface física: ${PARENT_IF}"
echo "   Gateway: ${GATEWAY:-'não detectado'}"
echo ""
echo "🔧 Para configurar o softphone:"
echo "   Servidor SIP: ${VM_IP}"
echo "   Porta: ${HOST_UDP_PORT}"
echo "   Protocolo: UDP"
echo "   Ramal: 3001-3199 (use qualquer disponível)"
echo "   Senha: Teste123"
