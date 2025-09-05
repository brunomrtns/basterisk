#!/bin/bash
set -e

PARENT_PATH=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)

# Importar funções comuns
source "${PARENT_PATH}/utils/common_functions.sh"

VM_NAME="asterisk"
CONFIG_SOURCE_DIR="${PARENT_PATH}/src/etc/asterisk"

# Verificar se a VM existe
if ! incus list --format csv | grep -q "^${VM_NAME},"; then
    echo "❌ Erro: VM '${VM_NAME}' não encontrada!"
    echo "Execute primeiro: ./create-vm.sh"
    exit 1
fi

# Verificar se a VM está rodando
VM_STATUS=$(incus list --format csv | grep "^${VM_NAME}," | cut -d',' -f2)
if [[ "${VM_STATUS}" != "RUNNING" ]]; then
    echo "❌ Erro: VM '${VM_NAME}' não está rodando (status: ${VM_STATUS})"
    echo "Execute: incus start ${VM_NAME}"
    exit 1
fi

# Verificar se o diretório de configuração existe
if [[ ! -d "${CONFIG_SOURCE_DIR}" ]]; then
    echo "❌ Erro: Diretório de configuração não encontrado: ${CONFIG_SOURCE_DIR}"
    exit 1
fi

echo "🔄 Atualizando configurações do Asterisk na VM '${VM_NAME}'..."
echo "📂 Origem: ${CONFIG_SOURCE_DIR}"
echo "🎯 Destino: /etc/asterisk (na VM)"

# Fazer backup das configurações atuais
echo "💾 Fazendo backup das configurações atuais..."
incus exec ${VM_NAME} -- mkdir -p /etc/asterisk/backup.$(date +%Y%m%d_%H%M%S)
incus exec ${VM_NAME} -- cp -r /etc/asterisk/* /etc/asterisk/backup.$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || true

# Parar o Asterisk antes de atualizar
echo "⏹️  Parando o Asterisk..."
incus exec ${VM_NAME} -- systemctl stop asterisk || echo "⚠️  Asterisk já estava parado"

# Copiar todos os arquivos de configuração
echo "📋 Copiando arquivos de configuração..."
for config_file in "${CONFIG_SOURCE_DIR}"/*; do
    if [[ -f "$config_file" ]]; then
        filename=$(basename "$config_file")
        echo "  📄 Copiando ${filename}..."
        
        # Copiar arquivo para a VM
        incus file push "$config_file" "${VM_NAME}/etc/asterisk/${filename}"
        
        # Definir permissões corretas
        incus exec ${VM_NAME} -- chown asterisk:asterisk "/etc/asterisk/${filename}"
        incus exec ${VM_NAME} -- chmod 640 "/etc/asterisk/${filename}"
    fi
done

# Verificar se existem subdiretórios e copiá-los também
if [[ -d "${CONFIG_SOURCE_DIR}" ]]; then
    for subdir in "${CONFIG_SOURCE_DIR}"/*/; do
        if [[ -d "$subdir" ]]; then
            subdir_name=$(basename "$subdir")
            echo "  📁 Copiando diretório ${subdir_name}/..."
            
            # Criar diretório na VM se não existir
            incus exec ${VM_NAME} -- mkdir -p "/etc/asterisk/${subdir_name}"
            
            # Copiar todos os arquivos do subdiretório
            for sub_file in "$subdir"*; do
                if [[ -f "$sub_file" ]]; then
                    sub_filename=$(basename "$sub_file")
                    echo "    📄 Copiando ${subdir_name}/${sub_filename}..."
                    incus file push "$sub_file" "${VM_NAME}/etc/asterisk/${subdir_name}/${sub_filename}"
                    incus exec ${VM_NAME} -- chown asterisk:asterisk "/etc/asterisk/${subdir_name}/${sub_filename}"
                    incus exec ${VM_NAME} -- chmod 640 "/etc/asterisk/${subdir_name}/${sub_filename}"
                fi
            done
        fi
    done
fi

# Reiniciar o Asterisk completamente
echo "🔄 Reiniciando o Asterisk..."
if incus exec ${VM_NAME} -- systemctl start asterisk; then
    echo "  ✅ Asterisk iniciado"
    
    # Aguardar inicialização
    echo "  ⏳ Aguardando inicialização (3s)..."
    sleep 3
    
    # Restart completo para aplicar todas as configurações
    echo "  🔄 Fazendo restart completo para aplicar configurações..."
    incus exec ${VM_NAME} -- asterisk -r -x "core restart now" 2>/dev/null || echo "    ⚠️  Restart via CLI falhou, usando systemctl..."
    
    if ! incus exec ${VM_NAME} -- asterisk -r -x "core restart now" 2>/dev/null; then
        echo "    🔄 Reiniciando via systemctl..."
        incus exec ${VM_NAME} -- systemctl restart asterisk
    fi
    
    # Aguardar reinicialização
    echo "  ⏳ Aguardando reinicialização completa (5s)..."
    sleep 5
    
else
    echo "  ❌ Erro ao iniciar o Asterisk"
    echo "  🔍 Verificando logs de erro..."
    incus exec ${VM_NAME} -- tail -10 /var/log/asterisk/messages 2>/dev/null || echo "    ⚠️  Não foi possível acessar logs"
    exit 1
fi

# Obter IP da VM para mostrar informações
VM_IP=$(get_vm_ip "${VM_NAME}" "interface")
if [[ $? -eq 0 ]]; then
    echo ""
    echo "✅ Atualização concluída com sucesso!"
    echo "🏠 IP da VM: ${VM_IP}"
    echo "🌐 WebSocket SIP: ws://${VM_IP}:8088/asterisk/ws"
    echo "📡 Asterisk ARI: http://${VM_IP}:8088/ari/"
    echo "📞 SIP UDP: ${VM_IP}:5060"
    echo ""
    echo "🔧 Para testar a configuração:"
    echo "   incus exec ${VM_NAME} -- asterisk -r -x 'core show version'"
    echo "   incus exec ${VM_NAME} -- asterisk -r -x 'pjsip show endpoints'"
    echo "   incus exec ${VM_NAME} -- asterisk -r -x 'http show status'"
    echo ""
    echo "📋 Para ver logs em tempo real:"
    echo "   incus exec ${VM_NAME} -- tail -f /var/log/asterisk/messages"
else
    echo "✅ Atualização concluída, mas não foi possível obter IP da VM"
fi

echo "🎉 Script update-vm.sh executado com sucesso!"
