#!/bin/bash
# update-asterisk.sh - Script SIMPLES para atualizar configurações do Asterisk
set -e

# Configurações
REMOTE_USER="root"
REMOTE_HOST="192.168.15.176"
REMOTE_PASSWORD="080693"
VM_NAME="asterisk"
LOCAL_ASTERISK_DIR="./src/etc/asterisk"
REMOTE_ASTERISK_DIR="/etc/asterisk"
BACKUP_DIR="/tmp/asterisk_backup_$(date +%Y%m%d_%H%M%S)"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}[INFO]${NC} Iniciando atualização do Asterisk..."
echo -e "${GREEN}[INFO]${NC} Diretório local: $LOCAL_ASTERISK_DIR"

# Verificar se o diretório local existe
if [ ! -d "$LOCAL_ASTERISK_DIR" ]; then
    echo -e "${RED}[ERROR]${NC} Diretório local não encontrado!"
    exit 1
fi

# Verificar se sshpass está instalado
if ! command -v sshpass &> /dev/null; then
    echo -e "${GREEN}[INFO]${NC} Instalando sshpass..."
    sudo apt-get install -y sshpass
fi

# Função para executar comando na VM
execute_in_vm() {
    sshpass -p "$REMOTE_PASSWORD" ssh -o StrictHostKeyChecking=no \
        $REMOTE_USER@$REMOTE_HOST "incus exec $VM_NAME -- bash -c \"$1\""
}

# 1. Criar backup
echo -e "${GREEN}[INFO]${NC} Criando backup em $BACKUP_DIR..."
execute_in_vm "mkdir -p $BACKUP_DIR && cp -a $REMOTE_ASTERISK_DIR/. $BACKUP_DIR/"

# 2. Parar o Asterisk temporariamente
echo -e "${GREEN}[INFO]${NC} Parando Asterisk..."
execute_in_vm "service asterisk stop || systemctl stop asterisk" || true

# 3. Copiar/Atualizar configurações (preservando arquivos existentes)
echo -e "${GREEN}[INFO]${NC} Fazendo merge das configurações..."

# Criar diretório temporário no host remoto
sshpass -p "$REMOTE_PASSWORD" ssh -o StrictHostKeyChecking=no \
    $REMOTE_USER@$REMOTE_HOST "rm -rf /tmp/asterisk_temp && mkdir -p /tmp/asterisk_temp"

# Copiar todo o diretório para o host remoto
sshpass -p "$REMOTE_PASSWORD" rsync -avz "$LOCAL_ASTERISK_DIR/" $REMOTE_USER@$REMOTE_HOST:/tmp/asterisk_temp/

echo -e "${GREEN}[INFO]${NC} Atualizando /etc/asterisk na VM via rsync..."
sshpass -p "$REMOTE_PASSWORD" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST "
    tar -C /tmp/asterisk_temp -cf - . | incus exec $VM_NAME -- tar -C $REMOTE_ASTERISK_DIR -xf -
"
echo -e "${GREEN}[INFO]${NC} Atualização completa do diretório /etc/asterisk."

# Limpar temporários
sshpass -p "$REMOTE_PASSWORD" ssh -o StrictHostKeyChecking=no \
    $REMOTE_USER@$REMOTE_HOST "rm -rf /tmp/asterisk_temp"

# 4. Ajustar permissões
echo -e "${GREEN}[INFO]${NC} Ajustando permissões..."
execute_in_vm "chown -R asterisk:asterisk $REMOTE_ASTERISK_DIR"
execute_in_vm "chmod -R 755 $REMOTE_ASTERISK_DIR"

# 5. Iniciar Asterisk
echo -e "${GREEN}[INFO]${NC} Iniciando Asterisk..."
execute_in_vm "systemctl start asterisk"
sleep 5
execute_in_vm "asterisk -rx 'core restart now'"

# 6. Verificar status
echo -e "${GREEN}[INFO]${NC} Verificando status..."
sleep 3
status=$(execute_in_vm "asterisk -rx 'core show version' 2>/dev/null || echo 'Asterisk não responde'")
echo -e "${GREEN}[INFO]${NC} $status"

# 7. Verificar sintaxe
echo -e "${GREEN}[INFO]${NC} Verificando sintaxe..."
if execute_in_vm "asterisk -rx 'core show settings'" | grep -q -i "error"; then
    echo -e "${RED}[ERROR]${NC} Erros na sintaxe! Revertendo para backup..."
    execute_in_vm "cp -a $BACKUP_DIR/. $REMOTE_ASTERISK_DIR/"
    execute_in_vm "service asterisk restart || systemctl restart asterisk"
    echo -e "${GREEN}[INFO]${NC} Configuração revertida para backup"
else
    echo -e "${GREEN}[INFO]${NC} Sintaxe OK!"
fi

echo -e "${GREEN}[INFO]${NC} Atualização concluída! Backup em: $BACKUP_DIR"