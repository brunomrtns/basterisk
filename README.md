# 🎯 BAsterisk - VM Asterisk com MACVLAN

Projeto para criação automatizada de VM Asterisk com conectividade MACVLAN + roteamento híbrido WiFi/Ethernet.

## 🚀 Visão Geral

Este projeto resolve o problema clássico do MACVLAN: **como conectar do host quando a VM usa MACVLAN?**

**Solução implementada:**

- VM Asterisk com MACVLAN via **Ethernet** (acesso direto à rede)
- Host conecta via **WiFi** → Gateway → VM (roteamento automático)
- Sistema híbrido que combina o melhor dos dois mundos

## 📋 Requisitos

### Hardware

- Interface **Ethernet** (cabo de rede conectado)
- Interface **WiFi** (conectada na mesma rede)
- 4GB+ RAM para VM
- 20GB+ espaço em disco

### Software

- Ubuntu/Linux com Incus/LXD instalado
- `wget` ou `curl` para download automático
- Permissões sudo
- Network Manager ativo

> **Nota:** O arquivo `basterisk.tar` (150MB) será baixado automaticamente do GitHub Releases.

## 🛠️ Scripts do Projeto

### 1. `create-vm-macvlan.sh` - Script Principal

**Funcionalidade completa:**

```bash
chmod +x create-vm-macvlan.sh
./create-vm-macvlan.sh
```

**O que faz:**

- ✅ **Baixa automaticamente** basterisk.tar (150MB) do GitHub Releases
- ✅ Detecta interface Ethernet automaticamente
- ✅ Cria profile MACVLAN no Incus
- ✅ Lança VM Ubuntu 22.04 com MACVLAN
- ✅ Instala Asterisk 18.19.0 + PJSIP
- ✅ **Configura rota automática** WiFi → Gateway → VM
- ✅ Testa conectividade SIP
- ✅ Deixa sistema pronto para uso

### 2. `enable-host-to-vm.sh` - Script de Rota (Legado)

Script independente para configurar rota manualmente:

```bash
./enable-host-to-vm.sh
```

> **Nota:** Funcionalidade integrada ao script principal.

### 3. `wait_system_ready` - Função Auxiliar

Função para aguardar VM estar completamente inicializada.

## 🔧 Configuração de Rede

### Topologia Implementada

```
┌─────────────────┐    WiFi     ┌──────────────┐    Switch    ┌─────────────────┐
│     HOST        │◄────────────►│   Gateway    │◄─────────────►│   VM Asterisk   │
│  192.168.15.165 │             │192.168.15.1  │              │  192.168.15.73  │
│   (wlp3s0)      │             │              │              │   (MACVLAN)     │
└─────────────────┘             └──────────────┘              └─────────────────┘
```

### Interface Detection

O script detecta automaticamente:

- **Ethernet**: `enp2s0` (configurável na variável `PARENT_IF`)
- **WiFi**: `wlp3s0` (usado para rota de retorno)
- **Gateway**: Detectado via `ip route show default`

## 📞 Configuração SIP

### Endpoints Disponíveis

- **Ramais 3000-3199:** Todos pré-configurados
- **Senha padrão:** `Teste123`
- **Protocolo:** UDP (porta 5060)

### Configuração do Softphone

```
Servidor: 192.168.15.73 (IP da VM)
Porta: 5060
Protocolo: UDP
Usuário: 3001 (ou qualquer 3001-3199)
Senha: Teste123
```

### Softphones Testados

- ✅ **Jitsi** (Linux/Windows/Mac)
- ✅ **Linphone** (Multiplataforma)
- ✅ **MicroSIP** (Windows)

## 🎯 Casos de Uso

### 1. Desenvolvimento VoIP

- Teste rápido de aplicações SIP
- Desenvolvimento com softphones
- Simulação de PABX

### 2. Laboratório de Rede

- Estudo de MACVLAN vs Bridge
- Testes de roteamento híbrido
- Análise de conectividade L2/L3

### 3. Demonstração Técnica

- Solução para limitações WiFi + MACVLAN
- Implementação de rede híbrida
- Automação com Incus/LXD

## 🔍 Troubleshooting

### VM não obtém IP MACVLAN

```bash
# Verificar interface
ip link show enp2s0

# Testar DHCP manual na VM
sudo incus exec asterisk -- dhclient eth0
```

### Host não conecta na VM

```bash
# Verificar rota
ip route show | grep 192.168.15.73

# Reconfigurar rota manualmente
sudo ip route add 192.168.15.73 via 192.168.15.1
```

### Asterisk não inicia

```bash
# Verificar processo
sudo incus exec asterisk -- pgrep asterisk

# Logs do Asterisk
sudo incus exec asterisk -- asterisk -rvvv
```

## 🏗️ Arquitetura Técnica

### MACVLAN Profile

```yaml
devices:
  eth0:
    name: eth0
    nictype: macvlan
    parent: enp2s0
    type: nic
config:
  limits.cpu: "4"
  limits.memory: "4GiB"
  security.privileged: "true"
```

### Roteamento Automático

```bash
# Detecta gateway automaticamente
GATEWAY=$(ip route show default | awk '/default/ {print $3}')

# Configura rota específica para VM
sudo ip route add ${VM_IP} via ${GATEWAY}
```

### PJSIP Configuration

- **Transport UDP:** `0.0.0.0:5060`
- **Endpoints:** Template-based configuration
- **Authentication:** Digest (user/password)
- **Codecs:** ulaw, alaw, g729, h264, vp8

## 📈 Vantagens da Solução

### vs Bridge Networking

- ✅ **Performance:** Acesso L2 direto (sem NAT)
- ✅ **Simplicidade:** VM aparece como dispositivo físico na rede
- ✅ **Compatibilidade:** Funciona com DHCP/descoberta automática

### vs Proxy Devices

- ✅ **Transparência:** Não precisa configurar port forwarding
- ✅ **Escalabilidade:** Suporta múltiplas VMs facilmente
- ✅ **Flexibilidade:** VM tem IP real na rede

### Roteamento Híbrido

- ✅ **WiFi Compatibility:** Resolve limitação WiFi + MACVLAN
- ✅ **Automático:** Configuração transparente
- ✅ **Eficiente:** Rota direta via gateway

## 🤝 Contribuições

Contribuições são bem-vindas! Áreas de interesse:

- [ ] Detecção automática de interfaces
- [ ] Suporte a múltiplas VMs simultâneas
- [ ] Configuração SIP customizável
- [ ] Testes automatizados
- [ ] Documentação adicional

## 📄 Licença

Este projeto está sob licença MIT. Veja [LICENSE](LICENSE) para detalhes.

## 🏷️ Tags

`asterisk` `voip` `sip` `macvlan` `incus` `lxd` `networking` `ubuntu` `pjsip` `vm` `automation`
