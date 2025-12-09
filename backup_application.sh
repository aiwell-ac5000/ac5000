#!/bin/bash

set -euo pipefail

FLOW_FILE="/root/storage/flows/application.json"
TAB_NAME="Applikasjon"
API_BASE="http://localhost:80"
AUTH_HEADER=${AUTH_HEADER:-}
CLIENT_ID=${CLIENT_ID:-node-red-admin}
GRANT_TYPE=${GRANT_TYPE:-password}
SCOPE=${SCOPE:-*}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but not installed" >&2
  exit 1
fi

mkdir -p "$(dirname "$FLOW_FILE")"

# Keep the previous backup if present.
if [[ -f "$FLOW_FILE" ]]; then
  mv "$FLOW_FILE" "${FLOW_FILE%.*}_old.json"
fi

get_token() {
  curl -sf -X POST "$API_BASE/auth/token" \
    -d "client_id=$CLIENT_ID&grant_type=$GRANT_TYPE&scope=$SCOPE&username=$USERNAME&password=$PASSWORD"
}

# Acquire an access token if none was provided, retrying until Node-RED is ready (max 30s).
if [[ -z "$AUTH_HEADER" ]]; then
  echo "Waiting for Node-RED auth to become ready..."
  token_response=""
  for _ in {1..30}; do
    if token_response=$(get_token 2>/dev/null); then
      break
    fi
    sleep 1
  done

  if [[ -z "$token_response" ]]; then
    echo "Failed to fetch auth token after retries" >&2
    exit 1
  fi

  access_token=$(echo "$token_response" | jq -r '.access_token // empty')
  if [[ -z "$access_token" ]]; then
    echo "Auth token response missing access_token" >&2
    exit 1
  fi

  AUTH_HEADER="Authorization: Bearer $access_token"
fi

curl_common=(-sf)
if [[ -n "$AUTH_HEADER" ]]; then
  curl_common+=( -H "$AUTH_HEADER" )
fi

tmp_flows=$(mktemp)
trap 'rm -f "$tmp_flows"' EXIT

echo "Fetching flows to locate tab '$TAB_NAME'..."
curl "${curl_common[@]}" -o "$tmp_flows" "$API_BASE/flows" || {
  echo "Unable to reach Node-RED at $API_BASE" >&2
  exit 1
}

target_flow_id=$(jq -r --arg name "$TAB_NAME" '
    (if type == "object" and has("flows") then .flows else . end)
    | map(select(.type == "tab" and .label == $name))
    | .[0].id // empty
' "$tmp_flows")

if [[ -z "$target_flow_id" ]]; then
  echo "Tab '$TAB_NAME' not found in Node-RED" >&2
  exit 1
fi

echo "Found tab '$TAB_NAME' with id $target_flow_id; fetching tab flows..."

tmp_flow=$(mktemp)
trap 'rm -f "$tmp_flows" "$tmp_flow"' EXIT

curl "${curl_common[@]}" -o "$tmp_flow" "$API_BASE/flow/$target_flow_id" || {
  echo "Failed to fetch flow $target_flow_id" >&2
  exit 1
}

echo "Saving to $FLOW_FILE"
cp "$tmp_flow" "$FLOW_FILE"


cn=$(sed -n 's/^[[:space:]]*Subject:[[:space:]]*CN=\([^[:space:]]*\).*/\1/p' /etc/openvpn/client.conf | tr -d '\r' | head -n1)
if [[ -z "$cn" ]]; then
  echo "CN not found in /etc/openvpn/client.conf" >&2
else
  echo "Using CN='$cn' from /etc/openvpn/client.conf for FTP upload"
  if ! curl -v --ftp-create-dirs --retry 3 --retry-delay 2 \
  -T "$FLOW_FILE" "ftp://10.2.0.1:2121/pub/${cn}/application.json"; then
  echo "FTP upload failed" >&2
  fi
fi

echo "Backup complete for tab '$TAB_NAME' -> $FLOW_FILE"
