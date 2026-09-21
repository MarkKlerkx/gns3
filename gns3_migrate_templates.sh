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
read -rp "Local v3 port [80]: " V3_PORT
V3_PORT=${V3_PORT:-80}

read -rp "Local v3 admin username [admin]: " V3_USER
V3_USER=${V3_USER:-admin}

read -rsp "Local v3 admin password: " V3_PASS
echo ""

read -rp "Perform dry run first? (Y/n): " DRY_RUN_INPUT
DRY_RUN_INPUT=${DRY_RUN_INPUT:-Y}

V2_URL="http://${V2_HOST}:${V2_PORT}/v2/templates"
V3_BASE="http://127.0.0.1:${V3_PORT}"
V3_TPL_URL="${V3_BASE}/v3/templates"
V3_LOGIN_URL="${V3_BASE}/v3/access/users/login"

# --- 1. Fetch templates from old v2 server ---
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

echo "[+] Found ${TOTAL_COUNT} templates on source server."

# --- 2. Authenticate against local v3 ---
AUTH_HEADER=()
if [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    echo "[*] Skipping authentication for dry-run."
else
    echo "[*] Authenticating with local v3 server (${V3_LOGIN_URL})..."
    LOGIN_RESP=$(curl -s -X POST "$V3_LOGIN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${V3_USER}&password=${V3_PASS}")

    TOKEN=$(echo "$LOGIN_RESP" | jq -r '.access_token // .token // empty')

    if [ -n "$TOKEN" ]; then
        AUTH_HEADER=(-H "Authorization: Bearer ${TOKEN}")
        echo "[+] Authentication successful (Bearer token acquired)."
    else
        echo "[!] Login failed on v3 server."
        echo "Server response: $LOGIN_RESP"
        exit 1
    fi
fi

# --- 3. Process and Migrate templates ---
SUCCESS=0
FAILED=0

echo ""
if [[ "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    echo "--- Migrating Templates ---"
else
    echo "--- Dry Run (No changes applied) ---"
fi

for ((i=0; i<TOTAL_COUNT; i++)); do
    # Extract template, strip server-generated keys, and fix empty platform for QEMU
    CLEAN_TPL=$(echo "$RAW_TEMPLATES" | jq ".[$i] 
        | del(.template_id, .builtin, .status, .path)
        | if .template_type == \"qemu\" and (.platform == \"\" or .platform == null) then
            .platform = (
                if (.qemu_path // \"\") | test(\"aarch64\") then \"aarch64\"
                elif (.qemu_path // \"\") | test(\"arm\") then \"arm\"
                elif (.qemu_path // \"\") | test(\"i386\") then \"i386\"
                else \"x86_64\"
                end
            )
          else . end")

    TPL_NAME=$(echo "$CLEAN_TPL" | jq -r '.name // "Unnamed"')
    TPL_TYPE=$(echo "$CLEAN_TPL" | jq -r '.template_type // "unknown"')
    TPL_PLATFORM=$(echo "$CLEAN_TPL" | jq -r '.platform // empty')

    if [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
        PLAT_INFO=""
        [ -n "$TPL_PLATFORM" ] && PLAT_INFO=" (platform: $TPL_PLATFORM)"
        echo "[DRY-RUN] Found: '${TPL_NAME}' [Type: ${TPL_TYPE}${PLAT_INFO}]"
        continue
    fi

    HTTP_CODE=$(curl -s -o /tmp/gns3_resp.json -w "%{http_code}" \
        -X POST "$V3_TPL_URL" \
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
            jq . /tmp/gns3_resp.json 2>/dev/null || cat /tmp/gns3_resp.json
            echo ""
        fi
        ((FAILED++))
    fi
done

rm -f /tmp/gns3_resp.json

echo ""
if [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    echo "[*] Dry run complete. Run again and type 'n' to execute the import."
else
    echo "[*] Done: ${SUCCESS} imported, ${FAILED} failed."
fi
