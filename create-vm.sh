#!/bin/bash
set -e

PARENT_PATH=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)

VM_NAME="asterisk"
JASTERISK_TAR_PATH="/home/bruno/Downloads/jasterisk.tar"
HOST_UDP_PORT="5060"
HOST_RTP_START_PORT="4020"
HOST_RTP_END_PORT="4099"


if ! sudo incus network show incusbr0 >/dev/null 2>&1; then
    echo "Criando rede incusbr0..."
    sudo incus network create incusbr0 bridge.driver=linux
    sudo incus network set incusbr0 ipv4.address auto
    sudo incus network set incusbr0 ipv4.nat true
    sudo incus network set incusbr0 ipv6.address none
else
    echo "Rede incusbr0 já existe, pulando..."
fi

echo "Criando VM ${VM_NAME}..."
sudo incus remove ${VM_NAME} --force || true
sudo incus launch images:ubuntu/jammy ${VM_NAME} --profile macvlanprofile -c limits.cpu=4 -c security.privileged=true -c limits.memory=4GiB -c boot.autostart=false --vm



if ! sudo incus config device list ${VM_NAME} | grep -q "^eth0"; then
    echo "Adicionando eth0 à rede incusbr0..."
    sudo incus config device add ${VM_NAME} eth0 nic network=incusbr0
else
    echo "eth0 já está configurada, pulando..."
fi


sudo incus restart ${VM_NAME}


echo "Aguardando VM inicializar..."
sleep 10


echo "Obtendo IP da VM..."
VM_IP=""
for i in {1..30}; do
    VM_IP=$(sudo incus list ${VM_NAME} -c 4 --format csv | cut -d' ' -f1)
    if [ -n "$VM_IP" ] && [ "$VM_IP" != "-" ]; then
        echo "IP da VM: $VM_IP"
        break
    fi
    echo "Aguardando IP da VM... (tentativa $i/30)"
    sleep 2
done

if [ -z "$VM_IP" ] || [ "$VM_IP" = "-" ]; then
    echo "❌ Erro: Não foi possível obter o IP da VM"
    exit 1
fi

echo "VM IP: ${VM_IP}"
sleep 10


echo "Configurando port forwarding..."


sudo incus config device remove ${VM_NAME} sip-tcp 2>/dev/null || true
sudo incus config device remove ${VM_NAME} sip-udp 2>/dev/null || true
sudo incus config device remove ${VM_NAME} rtp 2>/dev/null || true


echo "Adicionando proxy device SIP TCP..."
sudo incus config device add ${VM_NAME} sip-tcp proxy listen=tcp:0.0.0.0:${HOST_UDP_PORT} connect=tcp:${VM_IP}:5060


echo "Adicionando proxy device SIP UDP..."
sudo incus config device add ${VM_NAME} sip-udp proxy listen=udp:0.0.0.0:${HOST_UDP_PORT} connect=udp:${VM_IP}:5060


echo "Adicionando proxy device RTP UDP..."
sudo incus config device add ${VM_NAME} rtp proxy listen=udp:0.0.0.0:${HOST_RTP_START_PORT}-${HOST_RTP_END_PORT} connect=udp:${VM_IP}:10000-20000


sudo incus exec ${VM_NAME} -- mkdir -p /opt/asterisk-installer


echo "Enviando jasterisk.tar para a VM..."
cat $JASTERISK_TAR_PATH | sudo incus exec ${VM_NAME} -- tee /opt/asterisk-installer/jasterisk.tar > /dev/null

echo "🔍 Testando conectividade do proxy UDP..."


sudo incus exec ${VM_NAME} -- bash -c "
    apt update -y && apt install -y netcat-openbsd tcpdump > /dev/null 2>&1
"


TEST_ID="proxy-test-$(date +%s)-$$"
echo "ID do teste: $TEST_ID"


echo "Iniciando captura de pacotes UDP na VM..."
sudo incus exec ${VM_NAME} -- bash -c "
    timeout 10 tcpdump -i any udp port 5060 -A -n > /tmp/udp_test.log 2>&1 &
    echo \$! > /tmp/tcpdump.pid
" &


sleep 3


echo "Enviando pacote de teste: host:${HOST_UDP_PORT} → VM:5060"
echo "PROXY_TEST_${TEST_ID}_SUCCESS" | nc -u -w2 127.0.0.1 ${HOST_UDP_PORT} 2>/dev/null || echo "Comando nc executado"


sleep 4


sudo incus exec ${VM_NAME} -- bash -c "pkill tcpdump 2>/dev/null || true"
sleep 1


PACKET_FOUND=$(sudo incus exec ${VM_NAME} -- bash -c "
    if [ -f /tmp/udp_test.log ]; then
        grep -c 'PROXY_TEST_${TEST_ID}_SUCCESS' /tmp/udp_test.log 2>/dev/null || echo '0'
    else
        echo '0'
    fi
")

echo "Pacotes com nosso ID encontrados: $PACKET_FOUND"

if [ "$PACKET_FOUND" -ge 1 ]; then
    echo "✅ Proxy UDP funcionando! Nosso pacote teste chegou à VM."
    echo "Log do tcpdump mostrando nosso pacote:"
    sudo incus exec ${VM_NAME} -- grep -A2 -B2 "PROXY_TEST_${TEST_ID}_SUCCESS" /tmp/udp_test.log 2>/dev/null || true
else
    echo "❌ Proxy UDP falhou. Nosso pacote teste não chegou à VM."
    echo ""
    echo "🔍 Diagnósticos:"
    echo "1. Verificando se a porta ${HOST_UDP_PORT} está sendo usada no host:"
    netstat -ulnp | grep ${HOST_UDP_PORT} || echo "   Porta não está em uso no host"
    echo ""
    echo "2. Verificando configuração do proxy na VM:"
    sudo incus config device show ${VM_NAME} sip-udp 2>/dev/null || echo "   Erro ao mostrar config do proxy"
    echo ""
    echo "3. Testando conectividade direta VM:"
    echo "   Enviando pacote diretamente para a VM..."
    echo "DIRECT_TEST_${TEST_ID}" | sudo incus exec ${VM_NAME} -- nc -u -w1 127.0.0.1 5060 2>/dev/null || echo "   Teste direto executado"
    echo ""
    echo "4. Log completo do tcpdump na VM:"
    sudo incus exec ${VM_NAME} -- cat /tmp/udp_test.log 2>/dev/null || echo "   Nenhum log encontrado"
    echo ""
    echo "❌ ABORTANDO: Proxy UDP não está funcionando!"
    echo "   Não adianta instalar o Asterisk se os pacotes SIP não chegam na VM."
    echo "   Corrija o problema do proxy primeiro."
    echo ""
    echo "💡 Possíveis soluções:"
    echo "   - Verificar se o Incus suporta proxy UDP na sua versão"
    echo "   - Tentar usar iptables ao invés de proxy devices"
    echo "   - Verificar firewall do host"
    echo "   - Usar uma VM com IP público ao invés de NAT"
    exit 1
fi


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

echo ""
echo "✅ Asterisk instalado e port forwarding configurado com sucesso!"
echo ""
echo "📋 Informações de conectividade:"
echo "   VM IP: ${VM_IP}"
echo "   SIP TCP: Host:${HOST_UDP_PORT} → VM:5060"
echo "   SIP UDP: Host:${HOST_UDP_PORT} → VM:5060"
echo "   RTP UDP: Host:${HOST_RTP_START_PORT}-${HOST_RTP_END_PORT} → VM:10000-20000"
echo ""
echo "🔧 Para configurar o Linphone:"
echo "   Servidor SIP: 127.0.0.1:${HOST_UDP_PORT}"
echo "   Protocolo: UDP"
echo "   Usuário: 3000"
echo "   Senha: 3000"
echo ""
echo "🧪 Para testar a conectividade UDP:"
echo "   echo 'test' | nc -u -w1 127.0.0.1 ${HOST_UDP_PORT}"
