#!/bin/bash

echo "=== Teste de Configuração ARI ==="
echo

# 1. Verificar se a VM está rodando
echo "1. Verificando se a VM asterisk está ativa..."
if incus info asterisk | grep -q "Status: Running"; then
    echo "   ✅ VM asterisk está rodando"
else
    echo "   ❌ VM asterisk não está rodando"
    exit 1
fi
echo

# 2. Copiar arquivos de configuração
echo "2. Copiando arquivos de configuração..."
incus file push /home/bruno.martins/Desenvolvimento/my-github/basterisk/src/etc/asterisk/http.conf asterisk/etc/asterisk/
incus file push /home/bruno.martins/Desenvolvimento/my-github/basterisk/src/etc/asterisk/ari.conf asterisk/etc/asterisk/
incus file push /home/bruno.martins/Desenvolvimento/my-github/basterisk/src/etc/asterisk/modules.conf asterisk/etc/asterisk/
incus file push /home/bruno.martins/Desenvolvimento/my-github/basterisk/src/etc/asterisk/extensions.conf asterisk/etc/asterisk/
echo "   ✅ Arquivos copiados"
echo

# 3. Reiniciar Asterisk
echo "3. Reiniciando Asterisk..."
incus exec asterisk -- systemctl restart asterisk
sleep 5
echo "   ✅ Asterisk reiniciado"
echo

# 4. Verificar status do HTTP
echo "4. Verificando status do HTTP Server..."
HTTP_STATUS=$(incus exec asterisk -- asterisk -rx 'http show status')
echo "$HTTP_STATUS"
if echo "$HTTP_STATUS" | grep -q "Server Enabled"; then
    echo "   ✅ HTTP Server habilitado"
else
    echo "   ❌ HTTP Server ainda desabilitado"
fi
echo

# 5. Verificar módulos ARI
echo "5. Verificando módulos ARI carregados..."
ARI_MODULES=$(incus exec asterisk -- asterisk -rx 'module show like ari')
echo "$ARI_MODULES"
echo

# 6. Testar conectividade ARI
echo "6. Testando conectividade ARI..."
if timeout 5 curl -s -u admin:admin http://192.168.169.1:8088/ari/asterisk/info > /dev/null; then
    echo "   ✅ ARI está respondendo"
    
    echo "7. Obtendo informações do sistema..."
    curl -s -u admin:admin http://192.168.169.1:8088/ari/asterisk/info | python3 -m json.tool
else
    echo "   ❌ ARI não está respondendo"
    echo "   Verificando se a porta 8088 está aberta..."
    nmap -p 8088 192.168.169.1
fi

echo
echo "=== Teste Concluído ==="
