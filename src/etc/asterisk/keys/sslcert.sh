#!/bin/bash

set -e

DIR="demoCA"
rm -Rf "$DIR"
mkdir "$DIR" "$DIR"/certs "$DIR"/crl "$DIR"/newcerts "$DIR"/private
touch "$DIR"/index.txt

echo
######################################################################################
echo "#################################################"
echo "######### Creating self-signed CA files #########"

# Criando um par de chaves publica e privada de 4096 bits com criptografada DES3 (Triple DES).
echo
echo "### Creating a CA public and private key pair. (key file) ###"
CAKEY=ca.key
openssl genrsa -des3 -out ${CAKEY} -passout "pass:4567" 4096 >/dev/null
echo
echo "### Extracting the public key from the key file. ###"
openssl rsa -in ${CAKEY} -passin "pass:4567" -pubout
echo

# Criando um pedido de assinatura para a o certificado da CA.
echo "### Creating signing request (csr file) ###"
CACFG=ca.cfg

cat >${CACFG} <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
default_md = sha256

[req_distinguished_name]
C=BR
ST=SC
L=Florianopolis
O=Bruno
OU=Matriz
emailAddress=ca@bruno.com
CN=ca.bruno.com

[ext]
basicConstraints=CA:TRUE"
EOF

CAREQUEST=ca.csr
openssl req -new -key ${CAKEY} -out ${CAREQUEST} -config ${CACFG} -passin "pass:4567" >/dev/null

# Criando um certificado autoassinado, válido por 365 dias, usando o padrão para certificados digitais X.509.
echo
echo "### Creating self-signed CA certificate (crt file) ###"
CACERT=ca.crt
openssl ca -create_serial -out ${CACERT} -days 1095 -batch -keyfile ${CAKEY} -passin "pass:4567" -selfsign -extensions v3_ca -infiles ${CAREQUEST}

# Criando link para o certificado com hash
echo "### creating hash link ###"
mkdir -p hash
cp ${CACERT} hash/
c_rehash hash

echo
######################################################################################
echo "##################################################"
echo "######### Creating intermediate CA files #########"

# Criando um par de chaves publica e privada de 4096 bits com criptografada DES3 (Triple DES).
echo
echo "### Creating a intermediate CA public and private key pair. (key file) ###"
INTCAKEY=intca.key
openssl genrsa -des3 -out ${INTCAKEY} -passout "pass:4567" 4096 >/dev/null
echo
echo "### Extracting the public key from the key file. ###"
openssl rsa -in ${INTCAKEY} -pubout -passin "pass:4567"
echo

# Criando um pedido de assinatura para a o certificado da CA intermediária.
echo "### Creating certificate signing request (csr file) ###"
INTCACFG=intca.cfg

cat >${INTCACFG} <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
default_md = sha256

[req_distinguished_name]
C=BR
ST=SC
L=Florianopolis
O=Bruno
OU=Matriz
emailAddress=intca@bruno.com
CN=intca.bruno.com
EOF

INTCAREQUEST=intca.csr
openssl req -new -key ${INTCAKEY} -out ${INTCAREQUEST} -config ${INTCACFG} -passin "pass:4567" >/dev/null

# Usando a CA para assinar o certificado da CA intermediária, válido por 365 dias, usando o padrão para certificados digitais X.509.
echo "### Signing certificate request. Creating INTCA certificate (crt file) ###"
INTCACERT=intca.crt
openssl ca -batch -cert ${CACERT} -keyfile ${CAKEY} -passin "pass:4567" -policy policy_anything -out ${INTCACERT} -extensions v3_ca -infiles ${INTCAREQUEST}

# Criando link para o certificado com hash
echo "### creating hash link ###"
mkdir -p hash
cp ${INTCACERT} hash/
c_rehash hash

# Concatenando o certificado e a chave privada (Privacy Enhanced Mail (PEM))
echo "### Creating concatenated certificate and private key (pem file) ###"
INTCACONCAT=intca.pem
cat ${INTCAKEY} ${INTCACERT} > ${INTCACONCAT}

echo
######################################################################################
echo "###############################################"
echo "######### Creating a server SSL files #########"

# Criando um par de chaves publica e privada de 2048 bits com criptografada DES3 (Triple DES).
echo
echo "### Creating a server public and private key pair. (key file) ###"
SERVERKEY=server.key
openssl genrsa -out ${SERVERKEY} 2048 >/dev/null

# Criando um pedido de assinatura para a o certificado do servidor.
echo "### Creating certificate signing request (csr file) ###"
SERVERCFG=server.cfg

cat >${SERVERCFG} <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
default_md = sha256

[req_distinguished_name]
C=BR
ST=SC
L=Florianopolis
O=Bruno
OU=Matriz
emailAddress=server@bruno.com
CN=server.bruno.com
EOF

SERVERREQUEST=server.csr
openssl req -new -key ${SERVERKEY} -out ${SERVERREQUEST} -config ${SERVERCFG} >/dev/null

# Usando a CA intermediária para assinar o certificado do servidor, válido por 365 dias, usando o padrão para certificados digitais X.509.
echo "### Signing certificate request. Creating server certificate (crt file) ###"
SERVERCERT=server.crt
openssl ca -batch -cert ${INTCACERT} -keyfile ${INTCAKEY} -passin "pass:4567" -policy policy_anything -out ${SERVERCERT} -extensions v3_ca -infiles ${SERVERREQUEST}

# Criando link para o certificado com hash
echo "### creating hash link ###"
mkdir -p hash
cp ${SERVERCERT} hash/
c_rehash hash

# Concatenando a cadeia de certificados assinados (Privacy Enhanced Mail (PEM))
echo "### Creating concatenated certificate chain (pem file) ###"
SERVERCHAIN=serverchain.pem
cat ${SERVERCERT} ${INTCACERT} > ${SERVERCHAIN}

# Concatenando o certificado e a chave privada (Privacy Enhanced Mail (PEM))
echo "### Creating concatenated certificate and private key (pem file) ###"
SERVERCONCAT=server.pem
cat ${SERVERKEY} ${SERVERCHAIN} > ${SERVERCONCAT}

echo
######################################################################################
echo "###############################################"
echo "######### Creating a client SSL files #########"

# Criando um par de chaves publica e privada de 2048 bits com criptografada DES3 (Triple DES).
echo
echo "### Creating a client public and private key pair. (key file) ###"
CLIENTKEY=client.key
openssl genrsa -out ${CLIENTKEY} 2048 >/dev/null

# Criando um pedido de assinatura para a o certificado do servidor.
echo "### Creating certificate signing request (csr file) ###"
CLIENTCFG=client.cfg

cat >${CLIENTCFG} <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
default_md = sha256

[req_distinguished_name]
C=BR
ST=SC
L=Florianopolis
O=Bruno
OU=Matriz
emailAddress=client@bruno.com
CN=client.bruno.com
EOF

CLIENTREQUEST=client.csr
openssl req -new -key ${CLIENTKEY} -out ${CLIENTREQUEST} -config ${CLIENTCFG} >/dev/null

# Usando o certificado do servidor para assinar o certificado do cliente, válido por 365 dias, usando o padrão para certificados digitais X.509.
echo "### Signing certificate request. Creating client certificate (crt file) ###"
CLIENTCERT=client.crt
openssl ca -batch -cert ${SERVERCERT} -keyfile ${SERVERKEY} -policy policy_anything -out ${CLIENTCERT} -infiles ${CLIENTREQUEST}

# Criando link para o certificado com hash
echo "### creating hash link ###"
mkdir -p hash
cp ${CLIENTCERT} hash/
c_rehash hash

# Concatenando a cadeia de certificados assinados (Privacy Enhanced Mail (PEM))
echo "### Creating concatenated certificate chain (pem file) ###"
CLIENTCHAIN=clientchain.pem
cat ${CLIENTCERT} ${SERVERCERT} ${INTCACERT} > ${CLIENTCHAIN}

# Concatenando o certificado e a chave privada (Privacy Enhanced Mail (PEM))
echo "### Creating concatenated certificate and private key (pem file) ###"
CLIENTCONCAT=client.pem
cat ${CLIENTKEY} ${CLIENTCHAIN} > ${CLIENTCONCAT}

echo
######################################################################################
echo "################################################"
echo "######### Checking certificate #########"
echo
echo "### Checking ${CACERT} ###"
openssl verify -CAfile ${CACERT} ${CACERT}

echo
echo "### Checking ${INTCACERT} ###"
openssl verify -CAfile ${CACERT} ${INTCACERT}

echo
echo "### Checking ${SERVERCERT} ###"
openssl verify -CAfile ${CACERT} -untrusted ${SERVERCHAIN} ${SERVERCERT}

echo
echo "### Checking ${CLIENTCERT} ###"
cat ${SERVERCERT} ${INTCACERT} >chain.crt
openssl verify -CAfile ${CACERT} -untrusted ${CLIENTCHAIN} ${CLIENTCERT}
