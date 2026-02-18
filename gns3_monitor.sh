#!/bin/bash

# --- CONFIGURATION ---
VERSION="1.2.0"  # <--- HET VERSIENUMMER
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CONFIG_FILE="/home/gns3/.gns3_student_email"
RELAY="smtp.educloud.fontysict.nl"
FROM="noreply@fontysict.nl"
PROJECTS_DIR="/opt/gns3/projects"
LOG_FILE="/var/log/gns3_disk_monitor.log"
THRESHOLD=90 

# --- 1. STUDENT EMAIL CHECK & VALIDATION ---
if [ ! -s "$CONFIG_FILE" ] && [ -t 0 ]; then
    echo "GNS3 Monitor Versie $VERSION"
    echo "---------------------------"
    echo "Geen e-mailadres gevonden. Voer e-mailadres in voor rapportage:"
    read student_email
    if [[ "$student_email" == *"@"* ]]; then
        echo "$student_email" > "$CONFIG_FILE"
        echo "$(date): [v$VERSION] E-mailadres ingesteld op $student_email" >> "$LOG_FILE"
    else
        echo "Ongeldig formaat. Script stopt."
        exit 1
    fi
fi

if [ ! -s "$CONFIG_FILE" ]; then
    echo "$(date): [v$VERSION] FOUT - Geen e-mailadres geconfigureerd. Script gestopt." >> "$LOG_FILE"
    exit 0 
fi

EMAIL=$(cat "$CONFIG_FILE" | tr -d '[:space:]')

# --- 2. ANALYSIS ---
TOTAL_SIZE_BYTES=0
REPORT_BODY="GNS3 Disk Analysis Report (v$VERSION) for $EMAIL\n\n"

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

REPORT_SUMMARY="\n================================\n"
REPORT_SUMMARY+="DISK USAGE OVERVIEW (Script v$VERSION)\n"
REPORT_SUMMARY+="================================\n"
REPORT_SUMMARY+="GNS3 VM Total Capacity: $TOTAL_DISK_HUMAN\n"
REPORT_SUMMARY+="Currently In Use:        $USED_DISK_HUMAN ($PERCENTAGE_USED_STR)\n"
REPORT_SUMMARY+="Of which GNS3 projects: $TOTAL_VM_HUMAN\n"

# --- 4. EMAIL LOGIC ---

send_mail() {
    local subject=$1
    local body=$2

    if [[ -z "$EMAIL" || "$EMAIL" != *"@"* ]]; then
        echo "$(date): [v$VERSION] FOUT - Ongeldig of leeg adres ($EMAIL). Swaks overgeslagen." >> "$LOG_FILE"
        return 1
    fi

    # Voeg versie toe aan het onderwerp voor makkelijke filtering in dashboard/mailbox
    local full_subject="[GNS3-v$VERSION] $subject"

    swaks --to "$EMAIL" \
          --from "$FROM" \
          --server "$RELAY" \
          --port 25 \
          --header "Subject: $full_subject" \
          --body "$body" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "$(date): [v$VERSION] Succesvol gemaild naar $EMAIL" >> "$LOG_FILE"
    else
        echo "$(date): [v$VERSION] FOUT - Swaks kon niet verzenden naar $EMAIL" >> "$LOG_FILE"
    fi
}

# --- 5. EXECUTION ---
if [[ "$1" == "--daily" ]]; then
    send_mail "Daily Status Report - $(date +%F)" "$REPORT_BODY$REPORT_SUMMARY"
fi

if [ "$PERCENTAGE_USED" -ge "$THRESHOLD" ]; then
    send_mail "⚠️ ALERT: Disk Space Low ($PERCENTAGE_USED_STR)" "Waarschuwing! De GNS3 VM schijf is bijna vol.\n\n$REPORT_SUMMARY"
fi
