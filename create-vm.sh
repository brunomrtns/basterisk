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
HOST_IP=$(get_internet_ip_local_address)
HOST_UDP_PORT="5060"
echo "HOST IP: ${HOST_IP}"
# Portas que serão encaminhadas
PORTS=(
    "5060:5060/tcp"   
    "5060:5060/udp"   
    "5061:5061/tcp"
    "5061:5061/udp"
    "5001:5001/tcp"
    "5005:5005/tcp"
    "5432:5432/tcp"
    "8088:8088/tcp"   # ARI (Asterisk REST Interface)
    "8161:8161/tcp"
    "8787:8787/tcp"
    "4020:4099/tcp"
    "18080:18080/tcp"
    "61616:61616/tcp"
)


if ! sudo incus network show incusbr0 >/dev/null 2>&1; then
    echo "Criando rede incusbr0..."
    sudo incus network create incusbr0 bridge.driver=linux
    sudo incus network set incusbr0 ipv4.address auto
    sudo incus network set incusbr0 ipv4.nat true
    sudo incus network set incusbr0 ipv6.address none
else
    echo "Rede incusbr0 já existe, pulando..."
fi

# Criando network forward se não existir
echo "Verificando network forward para ${HOST_IP}..."

if incus network forward list incusbr0 --format csv | grep -q "${HOST_IP}"; then
    echo "🗑️  Removendo forward existente ${HOST_IP} (VM será recriada com novo IP)..."
    if incus network forward delete incusbr0 "${HOST_IP}"; then
        echo "  ✅ Forward antigo removido"
    else
        echo "  ❌ Erro ao remover forward antigo"
        exit 1
    fi
fi

echo "🔄 Criando network forward limpo para ${HOST_IP}..."
if incus network forward create incusbr0 "${HOST_IP}"; then
    echo "✅ Network forward criado com sucesso!"
else
    echo "❌ Erro ao criar network forward. Tentando listar forwards existentes:"
    incus network forward list incusbr0 || echo "Falha ao listar forwards"
    exit 1
fi

echo "Criando VM ${VM_NAME}..."
sudo incus remove ${VM_NAME} --force || true
sudo incus launch images:ubuntu/jammy ${VM_NAME} -c limits.cpu=4 -c security.privileged=true -c limits.memory=4GiB -c boot.autostart=true --vm

# Aguardar VM ficar pronta
wait_system_ready "${VM_NAME}"

# Obter IP da VM
VM_IP=$(get_vm_ip "${VM_NAME}" "interface")
if [ $? -ne 0 ]; then
    echo "❌ Erro: Não foi possível obter o endereço IP da VM ${VM_NAME}."
    exit 1
else
    echo "✅ IP da VM: $VM_IP"
fi


echo "Configurando port forwarding com network forward..."

# Verificar se o forward foi criado corretamente
if ! incus network forward list incusbr0 --format csv | grep -q "${HOST_IP}"; then
    echo "❌ Erro: Network forward ${HOST_IP} não encontrado!"
    echo "Forwards disponíveis:"
    incus network forward list incusbr0 || echo "Nenhum forward encontrado"
    exit 1
fi

echo "✅ Network forward ${HOST_IP} confirmado"

echo "SOLUÇÃO TEMPORARIA"
incus exec ${VM_NAME} -- find /etc/apt/sources.list.d/ -type f -exec sed -i 's|^deb |# &|' {} \;
incus exec ${VM_NAME} -- sed -i '/^deb .*ubuntu.com/! s/^deb /# /' /etc/apt/sources.list
incus exec ${VM_NAME} -- sed -i '/^deb .*security.ubuntu.com/! s/^deb /# /' /etc/apt/sources.list
incus exec ${VM_NAME} -- sed -i '/^deb .*backports/! s/^deb /# /' /etc/apt/sources.list
incus exec ${VM_NAME} -- apt -o Acquire::ForceIPv4=true update

# Configurar portas básicas (SIP)
echo "🔧 Configurando portas SIP e outras..."
for port_pair in "${PORTS[@]}"; do
    IFS=':' read -r -a split_ports <<< "$port_pair"
    LISTEN_PORT=${split_ports[0]}
    TARGET_PORT=$(echo ${split_ports[1]} | cut -d'/' -f1)
    PROTOCOL=$(echo ${split_ports[1]} | cut -d'/' -f2)

    echo "  Porta ${LISTEN_PORT}/${PROTOCOL} → ${VM_IP}:${TARGET_PORT}"
    
    if incus network forward port add incusbr0 ${HOST_IP} ${PROTOCOL} ${LISTEN_PORT} ${VM_IP} ${TARGET_PORT}; then
        echo "    ✅ Configurada"
    else
        echo "    ❌ Erro ao configurar porta $LISTEN_PORT/$PROTOCOL"
    fi
done

echo "✅ Port forwarding configurado!"

# Instalar dependências básicas
install_vm_basics "${VM_NAME}"

# Testar conectividade
if ! test_udp_connectivity "${VM_NAME}" "${HOST_IP}" "${HOST_UDP_PORT}" "forward"; then
    echo ""
    echo "🔍 Diagnósticos:"
    echo "1. Verificando network forwards configurados:"
    incus network forward list incusbr0
    echo ""
    echo "2. Verificando portas configuradas:"
    incus network forward show incusbr0 ${HOST_IP}
    echo ""
    echo "❌ ABORTANDO: Network forward UDP não está funcionando!"
    echo "   Corrija o problema do forward primeiro."
    exit 1
fi

# Instalar Asterisk
install_asterisk "${VM_NAME}" "${JASTERISK_TAR_LOCAL}"

# Exibir informações finais
show_final_info "${VM_IP}" "forward" "${HOST_IP}" "${HOST_UDP_PORT}" "${HOST_RTP_START_PORT}" "${HOST_RTP_END_PORT}" "${VM_NAME}"
