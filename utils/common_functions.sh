#!/bin/bash

# Função para validar arquivo jasterisk.tar
validate_file() {
    local file_path="$1"
    if [ -f "$file_path" ] && [ -s "$file_path" ]; then
        # Verificar se é um arquivo tar válido
        if file "$file_path" | grep -q "tar archive\|gzip compressed"; then
            return 0
        fi
    fi
    return 1
}

# Função para baixar jasterisk.tar
download_jasterisk() {
    local url="$1"
    local local_path="$2"
    local fallback_path="$3"
    
    echo "📥 Verificando jasterisk.tar..."
    
    # Verificar se arquivo local existe e é válido
    if validate_file "${local_path}"; then
        echo "✅ jasterisk.tar válido encontrado: ${local_path}"
        return 0
    fi
    
    echo "🔄 Arquivo não encontrado ou inválido, obtendo novo..."
    rm -f "${local_path}"
    
    echo "📥 Tentando download do GitHub..."
    
    if command -v wget >/dev/null 2>&1; then
        echo "🔄 Baixando via wget..."
        if wget --progress=bar:force --timeout=60 --tries=3 -O "${local_path}" "${url}"; then
            echo "✅ Download via wget concluído!"
        else
            echo "❌ Falha no download via wget"
            rm -f "${local_path}"
        fi
    elif command -v curl >/dev/null 2>&1; then
        echo "🔄 Baixando via curl..."
        if curl --progress-bar --connect-timeout 60 --retry 3 -L -o "${local_path}" "${url}"; then
            echo "✅ Download via curl concluído!"
        else
            echo "❌ Falha no download via curl"
            rm -f "${local_path}"
        fi
    else
        echo "❌ wget ou curl não encontrado!"
        echo "💡 Instale: sudo apt install wget curl"
        return 1
    fi
    
    # Se download falhou, tentar fallback
    if ! validate_file "${local_path}"; then
        echo "❌ Download falhou ou arquivo corrompido!"
        if [ -f "${fallback_path}" ] && validate_file "${fallback_path}"; then
            echo "📁 Usando fallback ${fallback_path}"
            cp "${fallback_path}" "${local_path}"
        else
            echo "❌ Fallback também não encontrado ou inválido!"
            return 1
        fi
    fi
    
    # Validação final
    if ! validate_file "${local_path}"; then
        echo "❌ Arquivo jasterisk.tar não encontrado ou inválido!"
        echo "💡 Certifique-se de que o arquivo existe em: ${local_path}"
        echo "💡 Ou baixe manualmente de: ${url}"
        return 1
    fi
    
    FILE_SIZE=$(du -h "${local_path}" | cut -f1)
    echo "📁 Tamanho do arquivo: ${FILE_SIZE}"
    return 0
}

# Função para instalar dependências básicas na VM
install_vm_basics() {
    local vm_name="$1"
    
    echo "📦 Instalando dependências básicas na VM..."
    sudo incus exec ${vm_name} -- bash -c "
        apt update -y && \
        apt upgrade -y && \
        apt autoremove -y && \
        apt autoclean -y && \
        apt install -y tree nano netcat-openbsd tcpdump > /dev/null 2>&1
    "
}

# Função para testar conectividade UDP
test_udp_connectivity() {
    local vm_name="$1"
    local target_ip="$2"
    local target_port="$3"
    local test_type="$4"  # "forward" ou "direct"
    
    echo "🔍 Testando conectividade UDP ${test_type}..."
    
    TEST_ID="${test_type}-test-$(date +%s)-$$"
    echo "ID do teste: $TEST_ID"
    
    echo "Iniciando captura de pacotes UDP na VM..."
    sudo incus exec ${vm_name} -- bash -c "
        timeout 10 tcpdump -i any udp port ${target_port} -A -n > /tmp/udp_test.log 2>&1 &
        echo \$! > /tmp/tcpdump.pid
    " &
    
    sleep 3
    
    echo "Enviando pacote de teste: ${target_ip}:${target_port}"
    echo "${test_type^^}_TEST_${TEST_ID}_SUCCESS" | nc -u -w2 ${target_ip} ${target_port} 2>/dev/null || echo "Comando nc executado"
    
    sleep 4
    
    sudo incus exec ${vm_name} -- bash -c "pkill tcpdump 2>/dev/null || true"
    sleep 1
    
    PACKET_FOUND=$(sudo incus exec ${vm_name} -- bash -c "
        if [ -f /tmp/udp_test.log ]; then
            grep -c '${test_type^^}_TEST_${TEST_ID}_SUCCESS' /tmp/udp_test.log 2>/dev/null || echo '0'
        else
            echo '0'
        fi
    ")
    
    echo "Pacotes com nosso ID encontrados: $PACKET_FOUND"
    
    if [[ "$PACKET_FOUND" =~ ^[0-9]+$ ]] && [ "$PACKET_FOUND" -ge 1 ]; then
        echo "✅ Conectividade UDP ${test_type} funcionando! Pacote chegou à VM."
        echo "Log do tcpdump mostrando nosso pacote:"
        sudo incus exec ${vm_name} -- grep -A2 -B2 "${test_type^^}_TEST_${TEST_ID}_SUCCESS" /tmp/udp_test.log 2>/dev/null || true
        return 0
    else
        if [ "$test_type" = "direct" ]; then
            echo "⚠️  Teste UDP direto falhou, mas isso pode ser normal com MACVLAN do host."
            echo "A VM pode estar acessível de outros dispositivos da rede."
            return 0
        else
            echo "❌ Conectividade UDP ${test_type} falhou. Pacote teste não chegou à VM."
            return 1
        fi
    fi
}

# Função para instalar Asterisk
install_asterisk() {
    local vm_name="$1"
    local jasterisk_path="$2"
    
    echo "📤 Enviando jasterisk.tar para a VM..."
    sudo incus exec ${vm_name} -- mkdir -p /opt/asterisk-installer
    cat ${jasterisk_path} | sudo incus exec ${vm_name} -- tee /opt/asterisk-installer/jasterisk.tar > /dev/null
    
    echo "🚀 Instalando Asterisk..."
    sudo incus exec ${vm_name} -- bash -c "
        cd /opt/asterisk-installer && \
        tar xvf jasterisk.tar && \
        cd jasterisk/jasterisk && \
        chmod +x INSTALL.sh && \
        ./INSTALL.sh
    "
}

# Função para obter IP da VM
get_vm_ip() {
    local vm_name="$1"
    local method="$2"  # "interface" ou "list"
    
    if [ "$method" = "interface" ]; then
        # Método usando interface de rede (para bridge/forward)
        VM_NETWORK_INTERFACE_NAME=$(incus list | grep "${vm_name}" | sed 's/.*(//;s/).*//')
        VM_IP=$(incus exec "${vm_name}" -- ip addr show $VM_NETWORK_INTERFACE_NAME | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    else
        # Método usando lista do incus (para macvlan)
        VM_IP=$(sudo incus list ${vm_name} -c 4 --format csv | cut -d' ' -f1)
    fi
    
    if [ -z "$VM_IP" ] || [ "$VM_IP" = "-" ]; then
        echo ""
        return 1
    else
        echo "$VM_IP"
        return 0
    fi
}

# Função para aguardar VM ficar pronta
wait_vm_ready() {
    local vm_name="$1"
    local timeout="${2:-60}"
    
    echo "⏳ Aguardando VM ${vm_name} ficar pronta..."
    
    for i in $(seq 1 $timeout); do
        STATUS=$(sudo incus list ${vm_name} -c s --format csv 2>/dev/null || echo "UNKNOWN")
        if [ "$STATUS" = "RUNNING" ]; then
            # Aguardar mais um pouco para sistema inicializar
            sleep 5
            echo "✅ VM pronta!"
            return 0
        fi
        echo "Aguardando VM: $STATUS (${i}/${timeout})"
        sleep 2
    done
    
    echo "❌ Timeout aguardando VM ficar pronta"
    return 1
}

# Função para exibir informações finais
show_final_info() {
    local vm_ip="$1"
    local connection_type="$2"  # "forward" ou "macvlan"
    local host_ip="$3"
    local sip_port="$4"
    local rtp_start="$5"
    local rtp_end="$6"
    local vm_name="${7:-asterisk}"  # Nome da VM (padrão: asterisk)
    
    echo ""
    echo "✅ Asterisk instalado com ${connection_type} configurado com sucesso!"
    echo ""
    echo "📋 Informações de conectividade:"
    echo "   VM IP: ${vm_ip}"
    
    if [ "$connection_type" = "forward" ]; then
        echo "   Host Forward IP: ${host_ip}"
        echo "   SIP TCP: ${host_ip}:${sip_port} → VM:5060"
        echo "   SIP UDP: ${host_ip}:${sip_port} → VM:5060"
        echo "   RTP UDP: ${host_ip}:${rtp_start}-${rtp_end} → VM:10000-10079"
        echo ""
        echo "🔧 Para configurar o Linphone:"
        echo "   Servidor SIP: ${host_ip}:${sip_port}"
        echo ""
        echo "🧪 Para testar a conectividade UDP:"
        echo "   echo 'test' | nc -u -w1 ${host_ip} ${sip_port}"
        echo ""
        echo "📝 Comandos úteis:"
        echo "   Ver forwards: incus network forward list incusbr0"
        echo "   Ver detalhes: incus network forward show incusbr0 ${host_ip}"
    else
        echo "   SIP TCP/UDP: ${vm_ip}:${sip_port}"
        echo "   RTP UDP: ${vm_ip}:${rtp_start}-${rtp_end}"
        echo ""
        echo "🔧 Para configurar o softphone:"
        echo "   Servidor SIP: ${vm_ip}"
        echo "   Porta: ${sip_port}"
        echo "   Ramal: 3001-3199 (use qualquer disponível)"
        echo "   Senha: Teste123"
    fi
    
    echo "   Protocolo: UDP"
    echo ""
    echo "📝 Comandos úteis gerais:"
    echo "   Conectar na VM: incus exec ${vm_name} -- bash"
    echo "   Ver status: incus list ${vm_name}"
}
