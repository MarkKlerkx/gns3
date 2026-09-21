#!/usr/bin/env bash

LOG_FILE="./gns3_migration.log"
CACHE_FILE="/tmp/gns3_v2_templates.json"
RESP_FILE="/tmp/gns3_resp.json"

# Logging helper
log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

log_and_print() {
    echo "$1"
    log "$1"
}

# Initialiseer logbestand
echo "=== GNS3 Migration Run: $(date) ===" >> "$LOG_FILE"

echo "=================================================="
echo "   GNS3 v2 -> v3 Template Migration (Bash/curl)   "
echo "=================================================="
echo "Log file: ${LOG_FILE}"

# --- Source Server (Remote v2) ---
read -rp "Old server IP or hostname: " V2_HOST
if [ -z "$V2_HOST" ]; then
    log_and_print "[!] Error: Remote host is required."
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

# --- Stap 1: Templates ophalen van oude server ---
log_and_print ""
log_and_print "[*] [STAP 1/3] Downloading templates from source: ${V2_URL}..."

V2_AUTH=""
if [ -n "$V2_USER" ]; then
    V2_AUTH="-u ${V2_USER}:${V2_PASS}"
fi

curl -s -S $V2_AUTH "$V2_URL" -o "$CACHE_FILE" 2>> "$LOG_FILE"

if [ ! -s "$CACHE_FILE" ] || ! jq -e 'type == "array"' "$CACHE_FILE" >/dev/null 2>&1; then
    log_and_print "[!] Failed to fetch a valid template array from old server."
    if [ -f "$CACHE_FILE" ]; then
        log "[DEBUG] Response head: $(head -n 5 "$CACHE_FILE")"
    fi
    exit 1
fi

TOTAL_COUNT=$(jq '. | length' "$CACHE_FILE")
log_and_print "[+] Received ${TOTAL_COUNT} templates from old server."

# --- Stap 2: Inloggen op lokale v3 controller ---
AUTH_HEADER=""
if [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    log_and_print "[*] Dry run selected: skipping v3 authentication."
else
    log_and_print ""
    log_and_print "[*] [STAP 2/3] Authenticating with local v3 server: ${V3_LOGIN_URL}..."
    LOGIN_RESP=$(curl -s -X POST "$V3_LOGIN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${V3_USER}&password=${V3_PASS}")

    TOKEN=$(echo "$LOGIN_RESP" | jq -r '.access_token // .token // empty' 2>/dev/null)

    if [ -n "$TOKEN" ]; then
        AUTH_HEADER="Authorization: Bearer ${TOKEN}"
        log_and_print "[+] Authentication successful. Bearer token obtained."
        log "[DEBUG] Token prefix: ${TOKEN:0:15}..."
    else
        log_and_print "[!] Login failed on v3 server."
        log_and_print "Response: $LOGIN_RESP"
        exit 1
    fi
fi

# --- Stap 3: Templates verwerken en importeren ---
SUCCESS=0
SKIPPED=0
FAILED=0
COUNTER=0

log_and_print ""
if [[ "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    log_and_print "[*] [STAP 3/3] Migrating templates to v3 database..."
else
    log_and_print "[*] [STAP 3/3] Dry run simulation (no database writes)..."
fi

# Verwerk templates compact regel voor regel (stream)
while IFS= read -r CLEAN_TPL; do
    ((COUNTER++))
    TPL_NAME=$(echo "$CLEAN_TPL" | jq -r '.name // "Unnamed"')
    TPL_TYPE=$(echo "$CLEAN_TPL" | jq -r '.template_type // "unknown"')
    TPL_PLAT=$(echo "$CLEAN_TPL" | jq -r '.platform // empty')

    DETAILS="[${COUNTER}/${TOTAL_COUNT}] '${TPL_NAME}' (Type: ${TPL_TYPE}"
    [ -n "$TPL_PLAT" ] && DETAILS+=", Platform: ${TPL_PLAT}"
    DETAILS+=")"

    if [[ ! "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
        log_and_print "[DRY-RUN] ${DETAILS}"
        continue
    fi

    log "[START] Submitting ${DETAILS}"

    HTTP_CODE=$(curl -s -o "$RESP_FILE" -w "%{http_code}" \
        -X POST "$V3_TPL_URL" \
        -H "Content-Type: application/json" \
        -H "$AUTH_HEADER" \
        -d "$CLEAN_TPL")

    case "$HTTP_CODE" in
        200|201)
            NEW_ID=$(jq -r '.template_id // empty' "$RESP_FILE" 2>/dev/null)
            ID_STR=""
            [ -n "$NEW_ID" ] && ID_STR=" -> ID: ${NEW_ID}"
            log_and_print "[OK]   ${DETAILS}${ID_STR}"
            ((SUCCESS++))
            ;;
        409)
            log_and_print "[SKIP] ${DETAILS} (Already exists on server)"
            ((SKIPPED++))
            ;;
        *)
            log_and_print "[FAIL] ${DETAILS} -> HTTP ${HTTP_CODE}"
            if [ -s "$RESP_FILE" ]; then
                ERR_MSG=$(cat "$RESP_FILE")
                echo "       Error: ${ERR_MSG}"
                log "[ERROR BODY] ${ERR_MSG}"
            fi
            ((FAILED++))
            ;;
    esac

done < <(jq -c '.[] 
    | del(.template_id, .builtin, .status, .path)
    | if .template_type == "qemu" and ((.platform // "") == "") then
        .platform = (
            if ((.qemu_path // "") | test("aarch64")) then "aarch64"
            elif ((.qemu_path // "") | test("arm")) then "arm"
            elif ((.qemu_path // "") | test("i386")) then "i386"
            else "x86_64"
            end
        )
      else . end' "$CACHE_FILE")

rm -f "$RESP_FILE" "$CACHE_FILE"

# --- Samenvatting ---
log_and_print ""
log_and_print "================ SUMMARY ================"
log_and_print " Total processed : ${TOTAL_COUNT}"
if [[ "$DRY_RUN_INPUT" =~ ^[nN]$ ]]; then
    log_and_print " Successfully imported: ${SUCCESS}"
    log_and_print " Skipped (existed)    : ${SKIPPED}"
    log_and_print " Failed               : ${FAILED}"
else
    log_and_print " Dry run completed. No templates were created."
fi
log_and_print " Log file saved to    : $(realpath "$LOG_FILE")"
log_and_print "========================================="
