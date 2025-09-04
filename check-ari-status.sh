#!/bin/bash

# Importar funções comuns
PARENT_PATH=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)
source "${PARENT_PATH}/utils/common_functions.sh"

echo "=== Verificação de Status do ARI (SEM MODIFICAÇÕES) ==="
echo

# 1. Verificar se a VM está rodando
echo "1. Verificando se a VM asterisk está ativa..."
VM_STATUS=$(incus list asterisk --format csv | cut -d, -f2)
if [ "$VM_STATUS" = "RUNNING" ]; then
    echo "   ✅ VM asterisk está rodando"
    # Obter IP atual da VM usando a função comum
    VM_IP=$(get_vm_ip "asterisk" "interface")
    if [ $? -eq 0 ] && [ -n "$VM_IP" ]; then
        echo "   IP da VM: $VM_IP"
    else
        echo "   ⚠️  Não foi possível obter IP da VM, usando método alternativo..."
        VM_IP=$(incus list asterisk --format csv | cut -d, -f3 | cut -d' ' -f1)
        echo "   IP da VM: $VM_IP"
    fi
else
    echo "   ❌ VM asterisk não está rodando (Status: $VM_STATUS)"
    exit 1
fi
echo

# 2. Verificar se o Asterisk está rodando na VM
echo "2. Verificando se o Asterisk está rodando..."
if incus exec asterisk -- pgrep asterisk > /dev/null; then
    echo "   ✅ Asterisk está rodando"
else
    echo "   ❌ Asterisk não está rodando"
    echo "   Para iniciar: incus exec asterisk -- systemctl start asterisk"
    exit 1
fi
echo

# 3. Verificar se a porta 8088 está aberta na VM
echo "3. Verificando porta 8088 na VM..."
if incus exec asterisk -- netstat -ln | grep ":8088 " > /dev/null; then
    echo "   ✅ Porta 8088 está aberta na VM"
else
    echo "   ❌ Porta 8088 não está aberta na VM"
    echo "   HTTP Server pode não estar habilitado"
fi
echo

# 4. Verificar status do HTTP Server
echo "4. Verificando status do HTTP Server..."
HTTP_STATUS=$(incus exec asterisk -- asterisk -rx 'http show status' 2>/dev/null)
echo "$HTTP_STATUS"
if echo "$HTTP_STATUS" | grep -q "Server Enabled"; then
    echo "   ✅ HTTP Server está habilitado"
else
    echo "   ❌ HTTP Server está desabilitado"
    echo "   Necessário habilitar no /etc/asterisk/http.conf"
fi
echo

# 5. Verificar módulos ARI carregados
echo "5. Verificando módulos ARI carregados..."
ARI_MODULES=$(incus exec asterisk -- asterisk -rx 'module show like ari' 2>/dev/null)
if echo "$ARI_MODULES" | grep -q "res_ari.so"; then
    echo "   ✅ Módulos ARI carregados:"
    echo "$ARI_MODULES" | grep "res_ari" | sed 's/^/      /'
else
    echo "   ❌ Módulos ARI não estão carregados"
    echo "   Necessário carregar: asterisk -rx 'module load res_ari'"
fi
echo

# 6. Testar conectividade ARI do host
echo "6. Testando conectividade ARI do host..."
if timeout 3 curl -s http://$VM_IP:8088 > /dev/null 2>&1; then
    echo "   ✅ Porta 8088 acessível do host"
    
    # 7. Testar autenticação ARI
    echo "7. Testando autenticação ARI..."
    ARI_RESPONSE=$(timeout 5 curl -s -u admin:admin http://$VM_IP:8088/ari/asterisk/info 2>/dev/null)
    if echo "$ARI_RESPONSE" | grep -q '"name"'; then
        echo "   ✅ ARI está funcionando corretamente!"
        echo "   Informações do sistema:"
        echo "$ARI_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'      Nome: {data.get(\"name\", \"N/A\")}'); print(f'      Versão: {data.get(\"version\", \"N/A\")}'); print(f'      Build: {data.get(\"build\", {}).get(\"date\", \"N/A\")}')" 2>/dev/null || echo "$ARI_RESPONSE"
    else
        echo "   ❌ ARI não está autenticando corretamente"
        echo "   Resposta: $ARI_RESPONSE"
    fi
else
    echo "   ❌ Porta 8088 não acessível do host"
    echo "   Verificando port forwarding..."
    
    # Verificar se o port forwarding está configurado
    if incus network forward list incusbr0 --format csv | grep -q "8088"; then
        echo "      ✅ Port forwarding configurado"
    else
        echo "      ❌ Port forwarding não configurado para porta 8088"
        echo "      Necessário adicionar: incus network forward port add incusbr0 [HOST_IP] tcp 8088 $VM_IP 8088"
    fi
fi

echo
echo "=== Resumo ==="
echo "🔧 Para habilitar o ARI:"
echo "   1. Editar /etc/asterisk/http.conf (enabled=yes, bindaddr=0.0.0.0)"
echo "   2. Editar /etc/asterisk/ari.conf (enabled=yes, allowed_origins=*)"
echo "   3. Carregar módulos: asterisk -rx 'module load res_ari'"
echo "   4. Reiniciar: systemctl restart asterisk"
echo
echo "📋 URLs de teste (quando funcionando):"
echo "   - http://$VM_IP:8088/ari/asterisk/info"
echo "   - ws://$VM_IP:8088/ari/events"
echo "   - Credenciais: admin:admin"
