#!/bin/bash
# Creates a local self-signed code-signing identity "Chitter Local" so TCC grants persist across rebuilds.
set -e
NAME="Chitter Local"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then echo "cert exists"; exit 0; fi
T=$(mktemp -d); cd "$T"
cat > cfg <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 3650 -config cfg 2>/dev/null
openssl pkcs12 -export -inkey k.pem -in c.pem -out c.p12 -passout pass:chitter 2>/dev/null
security import c.p12 -k ~/Library/Keychains/login.keychain-db -P chitter -T /usr/bin/codesign >/dev/null
echo "created $NAME (you may need to trust it in Keychain Access for codesign -v)"
