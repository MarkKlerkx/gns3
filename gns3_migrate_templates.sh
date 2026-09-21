#!/usr/bin/env bash

# ==============================================================================
# GNS3 v2 -> v3.1.x Template Migration Script
# ==============================================================================

# Alle tijdelijke bestanden en logging gaan naar /tmp (altijd schrijfbaar)
LOG_FILE="/tmp/gns3_migration.log"
CACHE_FILE="/tmp/gns3_v2_templates.json"
RESP_FILE="/tmp/gns3_resp.json"

# Stuur alle stdout en stderr zowel naar het scherm als naar /tmp/gns3_migration.log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo "   GNS3 v2 -> v3 Template Migration (Bash/curl)   "
echo "=================================================="
echo "[*] Logging to: $LOG_FILE"

# --- Source Server (Remote v2) ---
read -rp "Old server IP or hostname: " V2_HOST
if [ -z "$V2_HOST" ]; then
    echo "[!] Remote host is required."
    exit 1
fi

read -rp "Old server port [80]: " V2_PORT
V2_PORT=${V2_PORT:-80}

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

# --- 1. Fetch templates from old v2 server to file ---
echo ""
echo "[*] [STEP 1/3] Downloading templates from source: ${V2_URL}..."

V2_AUTH_ARGS=()
if [ -n "$V2_USER" ]; then
    V2_AUTH_ARGS=(-u "${V2_USER}:${V2_PASS}")
fi

curl -s -S "${V2_AUTH_ARGS[@]}" "$V2_URL" -o "$CACHE_FILE"

if [ ! -s "$CACHE_FILE" ] || ! jq -e 'type == "array"' "$CACHE_FILE" >/dev/null 2>&1; then
    echo "[!] Failed to fetch a valid template array from old server."
    if [ -f "$CACHE_FILE" ]; then
        echo "Server response head:"
        head -n 5 "$CACHE_FILE"
    fi
    exit 1
fi

TOTAL_COUNT=$(jq '. | length' "$CACHE_FILE")
echo "[+] Successfully downloaded ${TOTAL_COUNT} templates."

# --- 2. Authenticate against local v3 ---
echo ""
echo "[*] [STEP 2/3] Authenticating with local v3 server..."
AUTH_HEADER=()

if [[ "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    LOGIN_RESP=$(curl -s -X POST "$V3_LOGIN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${V3_USER}&password=${V3_PASS}")

    TOKEN=$(echo "$LOGIN_RESP" | jq -r '.access_token // .token // empty')

    if [ -n "$TOKEN" ]; then
        AUTH_HEADER=(-H "Authorization: Bearer ${TOKEN}")
        echo "[+] Authentication successful (Bearer token acquired)."
    else
        echo "[!] Login failed on local v3 server."
        echo "Server response: $LOGIN_RESP"
        exit 1
    fi
else
    echo "[*] Skipping authentication step for dry run."
fi

# --- 3. Process and Migrate templates line-by-line ---
SUCCESS=0
SKIPPED=0
FAILED=0

echo ""
if [[ "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    echo "--- [STEP 3/3] Migrating Templates ---"
else
    echo "--- [STEP 3/3] Dry Run (No changes applied) ---"
fi

# Stream elk template als een compacte JSON-regel
jq -c '.[] 
    | del(.template_id, .builtin, .status, .path)
    | if .template_type == "qemu" and ((.platform // "") == "") then
        .platform = (
            if ((.qemu_path // "") | test("aarch64")) then "aarch64"
            elif ((.qemu_path // "") | test("arm")) then "arm"
            elif ((.qemu_path // "") | test("i386")) then "i386"
            else "x86_64"
            end
        )
      else . end' "$CACHE_FILE" | while IFS= read -r CLEAN_TPL; do

    TPL_NAME=$(echo "$CLEAN_TPL" | jq -r '.name // "Unnamed"')
    TPL_TYPE=$(echo "$CLEAN_TPL" | jq -r '.template_type // "unknown"')

    if [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
        echo "[DRY-RUN] Found: '${TPL_NAME}' [Type: ${TPL_TYPE}]"
        continue
    fi

    HTTP_CODE=$(curl -s -o "$RESP_FILE" -w "%{http_code}" \
        -X POST "$V3_TPL_URL" \
        -H "Content-Type: application/json" \
        "${AUTH_HEADER[@]}" \
        -d "$CLEAN_TPL")

    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
        echo "[OK]   Created: '${TPL_NAME}'"
        ((SUCCESS++))
    elif [ "$HTTP_CODE" -eq 409 ]; then
        echo "[SKIP] '${TPL_NAME}' already exists on target."
        ((SKIPPED++))
    else
        echo "[FAIL] Could not import '${TPL_NAME}' (HTTP ${HTTP_CODE})"
        if [ -f "$RESP_FILE" ]; then
            jq . "$RESP_FILE" 2>/dev/null || cat "$RESP_FILE"
            echo ""
        fi
        ((FAILED++))
    fi
done

# Opruimen van tijdelijke bestanden (logbestand blijft behouden in /tmp)
rm -f "$RESP_FILE" "$CACHE_FILE"

echo ""
echo "[*] Migration process finished."
echo "[*] Detailed log saved to: $LOG_FILE"
