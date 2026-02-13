#!/bin/bash

# --- CONFIGURATION ---
CONFIG_FILE="/home/gns3/.gns3_student_email"
RELAY="smtp.educloud.fontysict.nl"
FROM="noreply@fontysict.nl"
PROJECTS_DIR="/opt/gns3/projects"
THRESHOLD=90 # Alert bij 90% gebruik

# --- 1. STUDENT EMAIL CHECK & VALIDATION ---
# Check of bestand bestaat en NIET leeg is (-s)
if [ ! -s "$CONFIG_FILE" ]; then
    echo "Geen e-mailadres gevonden of bestand is leeg."
    echo "Voer een student e-mailadres in voor rapportage:"
    read student_email
    # Simpele validatie voor de interactieve input
    if [[ "$student_email" == *"@*"* ]]; then
        echo "$student_email" > "$CONFIG_FILE"
        echo "E-mailadres opgeslagen."
    else
        echo "Ongeldig formaat. Script stopt om CPU-loop te voorkomen."
        exit 1
    fi
fi

EMAIL=$(cat "$CONFIG_FILE" | tr -d '[:space:]')

# --- 2. ANALYSIS ---
TOTAL_SIZE_BYTES=0
REPORT_BODY="GNS3 Disk Analysis Report for $EMAIL\n\n"

if [ -d "$PROJECTS_DIR" ]; then
    for project_path in "$PROJECTS_DIR"/*; do
        if [ -d "$project_path" ]; then
            PROJECT_ID=$(basename "$project_path")
            VM_DIR="$project_path/project-files/qemu"
            if [ -d "$VM_DIR" ] && [ "$(ls -A "$VM_DIR" 2>/dev/null)" ]; then
                REPORT_BODY+="--- Project: $PROJECT_ID ---\n"
                for vm_path in "$VM_DIR"/*; do
                    if [ -d "$vm_path" ]; then
                        DISK_FILE=$(find "$vm_path" -name "*.qcow2" -type f -print -quit)
                        if [ -f "$DISK_FILE" ]; then
                            VM_SIZE_HUMAN=$(du -sh "$DISK_FILE" | awk '{print $1}')
                            VM_SIZE_BYTES=$(du -b "$DISK_FILE" | awk '{print $1}')
                            TOTAL_SIZE_BYTES=$((TOTAL_SIZE_BYTES + VM_SIZE_BYTES))
                            REPORT_BODY+="VM: $(basename "$vm_path"), Size: $VM_SIZE_HUMAN\n"
                        fi
                    fi
                done
                REPORT_BODY+="\n"
            fi
        fi
    done
fi

# --- 3. DISK STATS CALCULATION ---
DISK_STATS=($(df / | awk 'NR==2 {print $2, $3, $5}'))
TOTAL_DISK_KB=${DISK_STATS[0]}
USED_DISK_KB=${DISK_STATS[1]}
PERCENTAGE_USED_STR=${DISK_STATS[2]} 
PERCENTAGE_USED=${PERCENTAGE_USED_STR%?} 

TOTAL_VM_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" $TOTAL_SIZE_BYTES)
TOTAL_DISK_HUMAN=$(numfmt --from=si --to=iec-i --suffix=B --format="%.2f" "${TOTAL_DISK_KB}K")
USED_DISK_HUMAN=$(numfmt --from=si --to=iec-i --suffix=B --format="%.2f" "${USED_DISK_KB}K")

# Finalizing Report
REPORT_SUMMARY="\n================================\n"
REPORT_SUMMARY+="DISK USAGE OVERVIEW\n"
REPORT_SUMMARY+="================================\n"
REPORT_SUMMARY+="GNS3 VM Total Capacity: $TOTAL_DISK_HUMAN\n"
REPORT_SUMMARY+="Currently In Use:       $USED_DISK_HUMAN ($PERCENTAGE_USED_STR)\n"
REPORT_SUMMARY+="Of which GNS3 projects: $TOTAL_VM_HUMAN\n"

# --- 4. EMAIL LOGIC MET VEILIGHEIDSCHECK ---

send_mail() {
    local subject=$1
    local body=$2

    # CRUCIALE CHECK: Voorkom 100% CPU door lege --to
    if [[ -z "$EMAIL" || "$EMAIL" != *"@fontysict.nl"* ]]; then
        echo "FOUT: Geen geldig e-mailadres ($EMAIL). Swaks wordt niet uitgevoerd."
        return 1
    fi

    echo "Verzenden naar $EMAIL..."
    swaks --to "$EMAIL" \
          --from "$FROM" \
          --server "$RELAY" \
          --port 25 \
          --header "Subject: $subject" \
          --body "$body" > /dev/null 2>&1
}

# Uitvoering op basis van triggers
if [[ "$1" == "--daily" ]]; then
    send_mail "Daily GNS3 Status Report - $(date +%F)" "$REPORT_BODY$REPORT_SUMMARY"
fi

if [ "$PERCENTAGE_USED" -ge "$THRESHOLD" ]; then
    send_mail "⚠️ ALERT: GNS3 Disk Space Low ($PERCENTAGE_USED_STR used)" "Warning! Your GNS3 VM has less than 10% free space remaining.\n\n$REPORT_SUMMARY"
fi
