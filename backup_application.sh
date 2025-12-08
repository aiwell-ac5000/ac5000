#!/bin/bash

set -euo pipefail

FLOW_FILE="/root/storage/flows/application.json"
TAB_NAME="Applikasjon"
API_BASE="http://localhost:80"
AUTH_HEADER=${AUTH_HEADER:-}
CLIENT_ID=${CLIENT_ID:-node-red-admin}
GRANT_TYPE=${GRANT_TYPE:-password}
SCOPE=${SCOPE:-*}
USERNAME=${USERNAME:-admin}
PASSWORD=${PASSWORD:-Prod2001}

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

# Acquire an access token if none was provided.
if [[ -z "$AUTH_HEADER" ]]; then
  token_response=$(curl -sf -X POST "$API_BASE/auth/token" \
    -d "client_id=$CLIENT_ID&grant_type=$GRANT_TYPE&scope=$SCOPE&username=$USERNAME&password=$PASSWORD") || {
      echo "Failed to fetch auth token" >&2
      exit 1
    }

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

echo "Backup complete for tab '$TAB_NAME' -> $FLOW_FILE"
