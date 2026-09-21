#!/usr/bin/env bash
set -e

echo "=================================================="
echo "   GNS3 v2 -> v3 Template Migration (Bash/curl)   "
echo "=================================================="

# --- Source Server (Remote v2) ---
read -rp "Old server IP or hostname: " V2_HOST
if [ -z "$V2_HOST" ]; then
    echo "[!] Remote host is required."
    exit 1
fi

read -rp "Old server port [3080]: " V2_PORT
V2_PORT=${V2_PORT:-3080}

read -rp "Old server username (press Enter if none): " V2_USER
if [ -n "$V2_USER" ]; then
    read -rsp "Old server password: " V2_PASS
    echo ""
fi

# --- Destination Server (Local v3) ---
read -rp "Local v3 port [3080]: " V3_PORT
V3_PORT=${V3_PORT:-3080}

read -rp "Local v3 admin username (press Enter if none): " V3_USER
if [ -n "$V3_USER" ]; then
    read -rsp "Local v3 admin password: " V3_PASS
    echo ""
fi

read -rp "Perform dry run first? (Y/n): " DRY_RUN_INPUT
DRY_RUN_INPUT=${DRY_RUN_INPUT:-Y}

V2_URL="http://${V2_HOST}:${V2_PORT}/v2/templates"
V3_URL="http://127.0.0.1:${V3_PORT}/v3/templates"

# --- 1. Fetch templates from v2 ---
echo ""
echo "[*] Fetching templates from old server: ${V2_URL}..."

V2_CURL_ARGS=(-s -S --fail)
if [ -n "$V2_USER" ]; then
    V2_CURL_ARGS+=(-u "${V2_USER}:${V2_PASS}")
fi

RAW_TEMPLATES=$(curl "${V2_CURL_ARGS[@]}" "$V2_URL" 2>/dev/null) || {
    echo "[!] Failed to connect to old server or fetch templates."
    exit 1
}

TOTAL_COUNT=$(echo "$RAW_TEMPLATES" | jq '. | length')
if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo "[!] No templates found on the remote server."
    exit 0
fi

echo "[+] Found ${TOTAL_COUNT} templates."

# --- 2. Authenticate to local v3 if credentials supplied ---
AUTH_HEADER=()
if [ -n "$V3_USER" ] && [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    : # Dry-run doesn't strictly need auth
elif [ -n "$V3_USER" ]; then
    echo "[*] Authenticating with local v3 server..."
    LOGIN_PAYLOAD=$(jq -n --arg u "$V3_USER" --arg p "$V3_PASS" '{username: $u, password: $p}')
    LOGIN_RESP=$(curl -s -X POST "http://127.0.0.1:${V3_PORT}/v3/users/login" \
        -H "Content-Type: application/json" \
        -d "$LOGIN_PAYLOAD")

    TOKEN=$(echo "$LOGIN_RESP" | jq -r '.access_token // .token // empty')
    if [ -n "$TOKEN" ]; then
        AUTH_HEADER=(-H "Authorization: Bearer ${TOKEN}")
        echo "[+] Authentication successful (Bearer token acquired)."
    else
        echo "[!] Login failed. Check your local v3 credentials."
        echo "Server response: $LOGIN_RESP"
        exit 1
    fi
fi

# --- 3. Process templates ---
SUCCESS=0
FAILED=0

echo ""
if [[ "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    echo "--- Migrating Templates ---"
else
    echo "--- Dry Run (No changes applied) ---"
fi

# Loop through each template index
for ((i=0; i<TOTAL_COUNT; i++)); do
    # Extract template and strip v3-incompatible / auto-generated keys
    CLEAN_TPL=$(echo "$RAW_TEMPLATES" | jq ".[$i] | del(.template_id, .builtin, .status, .path)")
    TPL_NAME=$(echo "$CLEAN_TPL" | jq -r '.name // "Unnamed"')
    TPL_TYPE=$(echo "$CLEAN_TPL" | jq -r '.template_type // "unknown"')

    if [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
        echo "[DRY-RUN] Found: '${TPL_NAME}' (Type: ${TPL_TYPE})"
        continue
    fi

    # Post template to v3
    HTTP_CODE=$(curl -s -o /tmp/gns3_resp.json -w "%{http_code}" \
        -X POST "$V3_URL" \
        -H "Content-Type: application/json" \
        "${AUTH_HEADER[@]}" \
        -d "$CLEAN_TPL")

    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
        echo "[OK]   Created: '${TPL_NAME}'"
        ((SUCCESS++))
    elif [ "$HTTP_CODE" -eq 409 ]; then
        echo "[SKIP] '${TPL_NAME}' already exists on target."
    else
        echo "[FAIL] Could not import '${TPL_NAME}' (HTTP ${HTTP_CODE})"
        if [ -f /tmp/gns3_resp.json ]; then
            cat /tmp/gns3_resp.json && echo ""
        fi
        ((FAILED++))
    fi
done

rm -f /tmp/gns3_resp.json

echo ""
if [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    echo "[*] Dry run complete. Run again and type 'n' to perform the import."
else
    echo "[*] Done: ${SUCCESS} imported, ${FAILED} failed."
fi
