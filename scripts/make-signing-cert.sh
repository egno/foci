#!/bin/bash
# Creates a self-signed code signing certificate in the login keychain, "Foci Dev" or the name given.
# A stable signature lets macOS keep the Accessibility permission across rebuilds, and across releases:
# the permission follows the signing certificate, not one build. Releases use "Foci Release":
#   scripts/make-signing-cert.sh "Foci Release"
# Back its key up (Keychain Access: export as .p12). A new certificate is a new signature, and everyone
# who has Foci installed has to grant the permission again once.
set -euo pipefail
name="${1:-Foci Dev}"
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
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem"
# macOS's own LibreSSL: the p12 it writes imports into the keychain (Homebrew's OpenSSL 3+ needs -legacy, and 4 changed again).
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
    -out "$tmp/cert.p12" -passout pass:foci
security import "$tmp/cert.p12" -k ~/Library/Keychains/login.keychain-db -P foci -T /usr/bin/codesign
echo "created '$name'"
