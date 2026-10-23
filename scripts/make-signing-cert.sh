#!/bin/bash
# Creates a self-signed code signing certificate "Foci Dev" in the login keychain.
# A stable signature lets macOS keep the Accessibility permission across rebuilds.
set -euo pipefail
name="Foci Dev"
if security find-certificate -c "$name" >/dev/null 2>&1; then
    echo "'$name' already exists"
    exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem"
# OpenSSL 3 needs -legacy for a p12 the macOS keychain can import; LibreSSL (/usr/bin/openssl) has no such flag.
legacy=$(openssl version | grep -q '^OpenSSL 3' && echo -legacy || true)
openssl pkcs12 -export $legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
    -out "$tmp/cert.p12" -passout pass:foci
security import "$tmp/cert.p12" -k ~/Library/Keychains/login.keychain-db -P foci -T /usr/bin/codesign
echo "created '$name'"
