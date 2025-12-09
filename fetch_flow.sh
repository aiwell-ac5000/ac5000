#!/bin/bash
set -euo pipefail
FLOW_FILE="/root/storage/flows/application.json"
API_BASE="http://localhost:80"
AUTH_HEADER=${AUTH_HEADER:-}
CLIENT_ID=${CLIENT_ID:-node-red-admin}
GRANT_TYPE=${GRANT_TYPE:-password}
SCOPE=${SCOPE:-*}

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but not installed" >&2
  exit 1
fi

cn=$(sed -n 's/^[[:space:]]*Subject:[[:space:]]*CN=\([^[:space:]]*\).*/\1/p' /etc/openvpn/client.conf | tr -d '\r' | head -n1)
if [[ -z "$cn" ]]; then
  echo "CN not found in /etc/openvpn/client.conf" >&2
  exit 1
else
  echo "Using CN='$cn' from /etc/openvpn/client.conf for FTP upload"
  if ! curl -v --ftp-create-dirs --retry 3 --retry-delay 2 \
  -o "$FLOW_FILE" "ftp://10.2.0.1:2121/pub/${cn}/application.json"; then
  echo "FTP download failed" >&2
  fi
fi

echo "Download complete for -> $FLOW_FILE"