#!/usr/bin/env bash

set -euo pipefail

FLOW_FILE="storage/flows/flows.json"
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

# Ensure the flow file is valid JSON before proceeding.
if ! jq empty "$FLOW_FILE" >/dev/null 2>&1; then
	echo "Flow file is not valid JSON" >&2
	exit 1
fi

# Fetch all flows to locate the target tab id.
curl_common=(-sf)
if [[ -n "$AUTH_HEADER" ]]; then
	curl_common+=( -H "$AUTH_HEADER" )
fi

tmp_flows=$(mktemp)
tmp_payload=$(mktemp)
tmp_payload2=$(mktemp)
tmp_response=$(mktemp)
trap 'rm -f "$tmp_flows" "$tmp_payload" "$tmp_payload2" "$tmp_response"' EXIT

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

echo "Found tab '$TAB_NAME' with id $target_flow_id; rebuilding flows..."

# Find the tab id contained in the backup so we can remap it to the existing tab.
exported_tab_id=$(jq -r '
	(if type == "object" and has("flows") then .flows else . end)
	| map(select(.type == "tab"))
	| .[0].id // empty
' "$FLOW_FILE")

# Build payload for PUT /flow/:id using backup content remapped to the target tab.
put_payload=$(jq -n \
	--slurpfile backup "$FLOW_FILE" \
	--arg target "$target_flow_id" \
	--arg exported "$exported_tab_id" \
	--arg tab_label "$TAB_NAME" '
		($backup[0] | if type == "object" and has("flows") then .flows else . end | if type == "array" then . else [] end) as $bflows
		| $bflows
		| map(select(.type != "tab"))
		| map(if .z? == $exported and ($target != "") then .z = $target else . end) as $bnodes
		| {
			id: $target,
			label: $tab_label,
			nodes: ($bnodes | map(select(.z? == $target))),
			configs: ($bnodes | map(select((.z? // "") == "")))
		  }
	')

if [[ -z "$put_payload" ]]; then
	echo "Failed to prepare flow payload" >&2
	exit 1
fi

printf '%s' "$put_payload" > "$tmp_payload"

echo "Updating tab via PUT /flow/$target_flow_id..."
status_code=$(curl -s -o "$tmp_response" -w "%{http_code}" -X PUT "$API_BASE/flow/$target_flow_id" \
	-H "Content-Type: application/json" \
	-H "Accept: application/json" \
	${AUTH_HEADER:+-H "$AUTH_HEADER"} \
	-d @"$tmp_payload")

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

printf '%s' "$flows_payload" > "$tmp_payload2"

status_code=$(curl -s -o "$tmp_response" -w "%{http_code}" -X POST "$API_BASE/flows" \
	-H "Content-Type: application/json" \
	-H "Accept: application/json" \
	-H "Node-RED-Deployment-Type: full" \
	${AUTH_HEADER:+-H "$AUTH_HEADER"} \
	-d @"$tmp_payload2")

if [[ "$status_code" != "200" && "$status_code" != "204" ]]; then
	echo "Failed to reorder flows (status $status_code):" >&2
	head -n 40 "$tmp_response" >&2 || true
	exit 1
fi

echo "Flows restored and reordered with '$TAB_NAME' first (id $target_flow_id)."
