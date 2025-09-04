#!/bin/bash

# Função para validar arquivo basterisk.tar
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

# Função para instalar dependências básicas na VM
install_vm_basics() {
    local vm_name="$1"
    
    echo "📦 Instalando dependências básicas na VM..."
    sudo incus exec ${vm_name} -- bash -c "
        apt update -y && \
        apt upgrade -y && \
        apt autoremove -y && \
        apt autoclean -y && \
        apt install -y tree nano netcat-openbsd tcpdump git > /dev/null 2>&1
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
    local basterisk_path="$2"
    local project_url="${3:-https://github.com/brunomrtns/basterisk.git}"

    echo "🚀 Instalando Asterisk..."
    sudo incus exec ${vm_name} -- bash -c "
        mkdir -p /opt/asterisk-installer && \
        cd /opt/asterisk-installer && \
        git clone ${project_url} && \
        cd basterisk && \
        chmod +x INSTALL.sh && \
        ./INSTALL.sh
    "
    
    # Configurar ARI usando função separada
    if configure_ari "${vm_name}"; then
        echo "✅ ARI configurado com sucesso!"
    else
        echo "⚠️  Configuração ARI falhou, mas Asterisk foi instalado"
    fi
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
wait_system_ready() {
    containerName="${1}"
    
    echo "==> Aguardando sistema da VM ${containerName} estar pronto..."
    
    
    sudo incus project switch default >/dev/null 2>&1 || true

    local looptest=""
    local attempts=0
    local max_attempts=60  
    
    while [ "${looptest}" != "running" ] && [ $attempts -lt $max_attempts ]; do
        
        if ! sudo incus list "${containerName}" --format csv >/dev/null 2>&1; then
            echo "==> VM ${containerName} não encontrada, aguardando..."
            sleep 5
            attempts=$((attempts + 1))
            continue
        fi
        
        
        vm_status=$(sudo incus list "${containerName}" -c s --format csv 2>/dev/null || echo "")
        if [ "$vm_status" != "RUNNING" ]; then
            echo "==> VM status: ${vm_status:-'unknown'}, aguardando..."
            sleep 5
            attempts=$((attempts + 1))
            continue
        fi
        
        
        looptest="$(sudo incus exec "${containerName}" -- bash -c "systemctl is-system-running 2>/dev/null || echo -n" 2>/dev/null || echo -n)"
        echo "==> System status: ${looptest:-'checking...'}"
        
        if [ "${looptest}" = 'degraded' ]; then
            echo "==> Sistema degradado, tentando reset..."
            sudo incus exec "${containerName}" -- bash -c "systemctl reset-failed 2>/dev/null || echo -n" 2>/dev/null || echo -n
            sleep 10
        elif [ "${looptest}" = 'running' ]; then
            echo "==> Sistema pronto!"
            break
        else
            echo "==> Aguardando sistema inicializar..."
            sleep 3
        fi
        
        attempts=$((attempts + 1))
    done
    
    if [ $attempts -ge $max_attempts ]; then
        echo "==> ⚠️  Timeout aguardando sistema ficar pronto (${max_attempts} tentativas)"
        echo "==> Continuando mesmo assim..."
    else
        echo "==> ✅ Sistema pronto após $attempts tentativas"
    fi
    
    sleep 3
}

get_internet_ip_local_address() {
  local default_gateway=$(ip route show | grep default | awk '{print $3}')
  local interface=$(ip route show | grep default | awk '{print $5}' | head -1)
  local ip_address=$(ip addr show dev "$interface" | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d '/' -f 1 | head -1)
  
  # Verificar se obtivemos um IP válido
  if [ -z "$ip_address" ]; then
    return 1
  fi
  
  # Se o IP for igual ao gateway, aguardar (caso raro)
  local attempts=0
  while [ "$ip_address" == "$default_gateway" ] && [ $attempts -lt 5 ]; do
    sleep 1
    ip_address=$(ip addr show dev "$interface" | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d '/' -f 1 | head -1)
    attempts=$((attempts + 1))
  done
  
  echo "$ip_address"
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
