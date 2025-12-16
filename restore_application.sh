#!/bin/bash

set -euo pipefail

FLOW_FILE="/root/storage/flows/application.json"
TAB_NAME="Applikasjon"
API_BASE="http://127.0.0.1:80"
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

if [[ ! -s "$FLOW_FILE" ]]; then
  echo "No flow file at $FLOW_FILE, nothing to restore" >&2
  exit 0
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

# Temp files
tmp_flows=$(mktemp)
tmp_response=$(mktemp)
trap 'rm -f "$tmp_flows" "$tmp_response"' EXIT

echo "Fetching existing flows..."
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

echo "Found tab '$TAB_NAME' with id $target_flow_id; restoring..."

# PUT the flow exactly as stored
status_code=$(curl -s -o "$tmp_response" -w "%{http_code}" -X PUT "$API_BASE/flow/$target_flow_id" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
  -d @"$FLOW_FILE")

if [[ "$status_code" != "200" && "$status_code" != "204" ]]; then
  echo "Failed to update flow $target_flow_id (status $status_code):" >&2
  head -n 40 "$tmp_response" >&2 || true
  exit 1
fi

echo "Reordering tabs to place '$TAB_NAME' first..."

curl "${curl_common[@]}" -o "$tmp_flows" "$API_BASE/flows" || {
  echo "Unable to refresh flows from Node-RED" >&2
  exit 1
}

flows_payload=$(jq -n \
  --slurpfile curr "$tmp_flows" \
  --arg target "$target_flow_id" \
  --arg rev "$(jq -r 'if type == "object" and has("rev") then .rev else "" end' "$tmp_flows")" '
    ($curr[0] | if type == "object" and has("flows") then .flows else . end | if type == "array" then . else [] end) as $flows
    | ($flows | map(select(.id == $target))) as $first
    | ($flows | map(select(.id != $target))) as $rest
    | $first + $rest as $ordered
    | if ($rev | length) > 0 then {rev:$rev, flows:$ordered} else $ordered end
  ')

if [[ -z "$flows_payload" ]]; then
  echo "Failed to prepare reorder payload" >&2
  exit 1
fi

printf '%s' "$flows_payload" > "$tmp_response"

status_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_BASE/flows" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Node-RED-Deployment-Type: full" \
  ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
  -d @"$tmp_response")

if [[ "$status_code" != "200" && "$status_code" != "204" ]]; then
  echo "Failed to reorder flows (status $status_code)" >&2
  exit 1
fi

echo "Restore complete; '$TAB_NAME' is first."
