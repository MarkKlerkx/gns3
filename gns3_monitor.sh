#!/bin/bash

# --- CONFIGURATION ---
CONFIG_FILE="$HOME/.gns3_student_email"
RELAY="smtp.educloud.fontysict.nl"
FROM="noreply@fontysict.nl"
PROJECTS_DIR="/opt/gns3/projects"
THRESHOLD=90 # Alert at 90% usage (10% remaining)

# --- 1. STUDENT EMAIL CHECK ---
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Welcome to the GNS3 Disk Monitor."
    echo "Please enter your student email address for reporting:"
    read student_email
    echo "$student_email" > "$CONFIG_FILE"
    echo "Email address saved."
fi
EMAIL=$(cat "$CONFIG_FILE")

# --- 2. ANALYSIS ---
TOTAL_SIZE_BYTES=0
REPORT_BODY="GNS3 Disk Analysis Report for $EMAIL\n\n"

if [ -d "$PROJECTS_DIR" ]; then
    for project_path in "$PROJECTS_DIR"/*; do
        if [ -d "$project_path" ]; then
            PROJECT_ID=$(basename "$project_path")
            VM_DIR="$project_path/project-files/qemu"
            if [ -d "$VM_DIR" ] && [ "$(ls -A "$VM_DIR")" ]; then
                REPORT_BODY+="--- Project: $PROJECT_ID ---\n"
                for vm_path in "$VM_DIR"/*; do
                    if [ -d "$vm_path" ]; then
                        DISK_FILE=$(find "$vm_path" -name "*.qcow2" -type f -print -quit)
                        if [ -f "$DISK_FILE" ]; then
                            VM_SIZE_HUMAN=$(du -sh "$DISK_FILE" | awk '{print $1}')
                            VM_SIZE_BYTES=$(du -b "$DISK_FILE" | awk '{print $1}')
                            TOTAL_SIZE_BYTES=$(($TOTAL_SIZE_BYTES + $VM_SIZE_BYTES))
                            REPORT_BODY+="VM: $(basename $vm_path), Size: $VM_SIZE_HUMAN\n"
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

# --- 4. EMAIL LOGIC ---

send_mail() {
    local subject=$1
    local body=$2
    # Using swaks to send mail via port 25 without auth
    swaks --to "$EMAIL" --from "$FROM" --server "$RELAY" --port 25 --header "Subject: $subject" --body "$body" > /dev/null
}

# Send daily report if triggered with --daily flag
if [[ "$1" == "--daily" ]]; then
    send_mail "Daily GNS3 Status Report - $(date +%F)" "$REPORT_BODY$REPORT_SUMMARY"
fi

# Send alert if disk usage >= 90%
if [ "$PERCENTAGE_USED" -ge "$THRESHOLD" ]; then
    send_mail "⚠️ ALERT: GNS3 Disk Space Low ($PERCENTAGE_USED_STR used)" "Warning! Your GNS3 VM has less than 10% free space remaining.\n\n$REPORT_SUMMARY"
fi
