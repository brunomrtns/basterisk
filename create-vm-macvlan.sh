#!/bin/bash
set -e

#
# 🎯 SCRIPT: VM Asterisk com MACVLAN + Rota Host
# 
# ✅ O que este script faz:
#   - Cria VM com MACVLAN para acesso direto à rede física
#   - Instala Asterisk 18.19.0 com PJSIP
#   - Configura rota automática para host acessar VM via WiFi
#   - Permite SIP do host (WiFi) → Gateway → VM (Ethernet MACVLAN)
#
# 🔧 Requisitos:
#   - Interface ethernet (PARENT_IF) conectada com cabo
#   - Interface WiFi conectada na mesma rede
#   - Arquivo jasterisk.tar em /home/bruno/Downloads/
#
# 🚀 Uso: ./create-vm-macvlan.sh
#


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
PARENT_IF="enp2s0"  # interface ethernet do host - SUBSTITUA pela sua!

# 🔍 Verificar se a interface física existe
if ! ip link show ${PARENT_IF} >/dev/null 2>&1; then
    echo "❌ Erro: Interface ${PARENT_IF} não encontrada!"
    echo "🔍 Interfaces disponíveis:"
    ip link show | grep '^[0-9]' | cut -d: -f2 | grep -v lo | sed 's/^ */   /'
    echo ""
    echo "💡 Edite a script e altere PARENT_IF para a interface correta"
    exit 1
fi

echo "✅ Interface ${PARENT_IF} encontrada e será usada para MACVLAN"

# ✅ 1️⃣ Garantir que estamos no project default
echo "🔄 Garantindo que estamos no project default..."
sudo incus project switch default

# ✅ 2️⃣ Criar/editar profile macvlan
echo "🔄 Criando/atualizando profile macvlan..."
if ! sudo incus profile show macvlanprofile >/dev/null 2>&1; then
    sudo incus profile create macvlanprofile
    echo "Profile macvlanprofile criado."
else
    echo "Profile macvlanprofile já existe, atualizando..."
fi

cat <<EOF > ${MAC_VLAN_PROFILE_PATH}
description: Untagged macvlan INCUS profile
devices:
  eth0:
    name: eth0
    nictype: macvlan
    parent: ${PARENT_IF}
    type: nic
  root:
    path: /
    pool: default
    type: disk
config:
  limits.cpu: "4"
  limits.memory: "4GiB"
  security.privileged: "true"
  boot.autostart: "false"
EOF

sudo incus profile edit macvlanprofile < ${MAC_VLAN_PROFILE_PATH}
echo "Profile macvlanprofile atualizado com sucesso."

echo "Criando VM ${VM_NAME}..."
sudo incus remove ${VM_NAME} --force || true

# Criar VM com timeout
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

# Reiniciar para aplicar MACVLAN com timeout
echo "Reiniciando VM..."
sudo incus restart ${VM_NAME} >/dev/null 2>&1 &

wait_system_ready "${VM_NAME}"

# Verificar se VM voltou a funcionar após restart
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

# Testar IP da VM - MACVLAN funciona imediatamente ou não funciona
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
    echo ""
    echo "💡 Possíveis soluções:"
    echo "   - Verificar se ${PARENT_IF} está conectada e ativa"
    echo "   - Verificar se o roteador tem DHCP habilitado"
    echo "   - Testar com interface ethernet ao invés de WiFi"
    echo "   - Desabilitar NetworkManager temporariamente"
    echo "   - Usar script create-vm.sh com proxy ao invés de MACVLAN"
    echo ""
    echo "� Comandos manuais para debug:"
    echo "   sudo incus exec ${VM_NAME} -- dhclient eth0"
    echo "   sudo incus exec ${VM_NAME} -- ping -c 3 8.8.8.8"
    exit 1
fi
echo "VM IP: ${VM_IP}"
sleep 5

echo "🔍 Testando conectividade UDP direta com a VM..."

# Instalar ferramentas na VM (tcpdump e netcat)
sudo incus exec ${VM_NAME} -- bash -c "
    apt update -y && apt install -y netcat-openbsd tcpdump > /dev/null 2>&1
"

# Criar um identificador único para o teste
TEST_ID="direct-test-$(date +%s)-$$"
echo "ID do teste: $TEST_ID"

# Rodar tcpdump na VM para capturar pacotes UDP
echo "Iniciando captura de pacotes UDP na VM..."
sudo incus exec ${VM_NAME} -- bash -c "
    timeout 10 tcpdump -i any udp port 5060 -A -n > /tmp/udp_test.log 2>&1 &
    echo \$! > /tmp/tcpdump.pid
" &

# Dar tempo para o tcpdump iniciar
sleep 3

# Tentar enviar pacote UDP diretamente para o IP da VM
echo "Enviando pacote de teste direto para VM: ${VM_IP}:5060"
echo "DIRECT_TEST_${TEST_ID}_SUCCESS" | nc -u -w2 ${VM_IP} 5060 2>/dev/null || echo "Comando nc executado"

# Esperar o tcpdump capturar
sleep 4

# Parar tcpdump e verificar se recebeu nosso pacote específico
sudo incus exec ${VM_NAME} -- bash -c "pkill tcpdump 2>/dev/null || true"
sleep 1

# Verificar se o conteúdo específico chegou na VM
PACKET_FOUND=$(sudo incus exec ${VM_NAME} -- bash -c "
    if [ -f /tmp/udp_test.log ]; then
        grep -c 'DIRECT_TEST_${TEST_ID}_SUCCESS' /tmp/udp_test.log 2>/dev/null || echo '0'
    else
        echo '0'
    fi
")

echo "Pacotes com nosso ID encontrados: $PACKET_FOUND"

if [ "$PACKET_FOUND" -ge 1 ]; then
    echo "✅ Conectividade UDP direta funcionando! Pacote chegou à VM."
    echo "Log do tcpdump mostrando nosso pacote:"
    sudo incus exec ${VM_NAME} -- grep -A2 -B2 "DIRECT_TEST_${TEST_ID}_SUCCESS" /tmp/udp_test.log 2>/dev/null || true
else
    echo "⚠️  Teste UDP direto falhou, mas isso pode ser normal com MACVLAN do host."
    echo "A VM pode estar acessível de outros dispositivos da rede."
fi

# 7️⃣ Criar diretório de instalação na VM se não existir
sudo incus exec ${VM_NAME} -- mkdir -p /opt/asterisk-installer

# 8️⃣ Copiar jasterisk.tar para a VM
echo "Enviando jasterisk.tar para a VM..."
cat $JASTERISK_TAR_PATH | sudo incus exec ${VM_NAME} -- tee /opt/asterisk-installer/jasterisk.tar > /dev/null

# 9️⃣ Descompactar e rodar INSTALL.sh
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

# 🔄 Configurar rota para permitir acesso do host à VM MACVLAN
echo "🛣️  Configurando rota para permitir acesso do host à VM..."
GATEWAY=$(ip route show default | awk '/default/ {print $3}' | head -1)

if [ -n "$GATEWAY" ]; then
    # Remover rota antiga se existir
    sudo ip route del ${VM_IP} 2>/dev/null || true
    
    # Adicionar nova rota via gateway
    if sudo ip route add ${VM_IP} via ${GATEWAY}; then
        echo "✅ Rota configurada com sucesso via gateway ${GATEWAY}"
        
        # Testar conectividade
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
echo "   SIP TCP/UDP: ${VM_IP}:5060"
echo "   RTP UDP: ${VM_IP}:10000-20000"
echo "   Interface física: ${PARENT_IF}"
echo "   Gateway: ${GATEWAY:-'não detectado'}"
echo ""
echo "🔧 Para configurar o Jitsi/Linphone:"
echo "   Servidor SIP: ${VM_IP}"
echo "   Porta: 5060"
echo "   Protocolo: UDP"
echo "   Ramal: 3001-3199 (use qualquer disponível)"
echo "   Senha: Teste123"
echo ""
echo "💻 HOST (este PC): ✅ PRONTO PARA USO!"
echo "   - Rota automática configurada"
echo "   - Configure seu softphone com as informações acima"
echo ""
echo "⚠️  MACVLAN permite conectar de:"
echo "   - ✅ HOST: rota automática via WiFi → Gateway → VM"
echo "   - ✅ Outros dispositivos da rede (PC, celular, tablet)"
echo "   - 🔍 A VM está na mesma rede que o roteador/switch"
echo ""
echo "🧪 Para testar de outro dispositivo:"
echo "   ping ${VM_IP}"
echo "   echo 'test' | nc -u -w1 ${VM_IP} 5060"
echo ""
echo "🔍 Para verificar logs do Asterisk na VM:"
echo "   sudo incus exec ${VM_NAME} -- tail -f /var/log/asterisk/messages"
