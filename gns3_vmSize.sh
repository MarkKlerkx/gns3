#!/bin/bash

# Path to the GNS3 projects directory
PROJECTS_DIR="/opt/gns3/projects"
TOTAL_SIZE_BYTES=0

# Check if the projects directory exists
if [ ! -d "$PROJECTS_DIR" ]; then
  echo "The directory $PROJECTS_DIR was not found."
  exit 1
fi

echo "Analyzing VMs in: $PROJECTS_DIR..."
echo ""

# Loop through each project in the projects directory
for project_path in "$PROJECTS_DIR"/*; do
  if [ -d "$project_path" ]; then
    PROJECT_ID=$(basename "$project_path")
    VM_DIR="$project_path/project-files/qemu"

    # Check if there are any VMs in the project
    if [ -d "$VM_DIR" ] && [ "$(ls -A "$VM_DIR")" ]; then
      echo "--- Project ID: $PROJECT_ID ---"

      # Loop through each VM in the VM directory
      for vm_path in "$VM_DIR"/*; do
        if [ -d "$vm_path" ]; then
          LOG_FILE="$vm_path/qemu.log"
          DISK_FILE=$(find "$vm_path" -name "*.qcow2" -type f -print -quit)

          # Get the VM name from the log file
          if [ -f "$LOG_FILE" ]; then
            VM_NAME=$(grep -oP '(?<=-name\s)[\w,]+' "$LOG_FILE" | head -n 1)
          else
            VM_NAME="Name not found"
          fi

          # Get the disk size
          if [ -f "$DISK_FILE" ]; then
            # Size for display (Human-readable)
            VM_SIZE_HUMAN=$(du -sh "$DISK_FILE" | awk '{print $1}')
            
            # Size in bytes for calculation
            VM_SIZE_BYTES=$(du -b "$DISK_FILE" | awk '{print $1}')
            TOTAL_SIZE_BYTES=$(($TOTAL_SIZE_BYTES + $VM_SIZE_BYTES))
            
            echo "VM Name: ${VM_NAME}, Size: ${VM_SIZE_HUMAN}"
          fi
        fi
      done
      echo "" # Add a blank line for readability
    fi
  fi
done

# =================================================================
# NEW CODE: CALCULATE AND DISPLAY TOTAL USAGE
# =================================================================

# 1. Get disk stats from the root filesystem (in Kilobytes)
DISK_STATS=($(df / | awk 'NR==2 {print $2, $3}'))
TOTAL_DISK_KB=${DISK_STATS[0]}
USED_DISK_KB=${DISK_STATS[1]}

# 2. Convert values to a human-readable format (e.g., GB, MB)
TOTAL_VM_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" $TOTAL_SIZE_BYTES)
TOTAL_DISK_HUMAN=$(numfmt --from=si --to=iec-i --suffix=B --format="%.2f" "${TOTAL_DISK_KB}K")
USED_DISK_HUMAN=$(numfmt --from=si --to=iec-i --suffix=B --format="%.2f" "${USED_DISK_KB}K")

# 3. Calculate the percentage of used space taken by the VMs
USED_DISK_BYTES=$((USED_DISK_KB * 1024))
PERCENTAGE="0.00"
if [ $USED_DISK_BYTES -gt 0 ]; then
  PERCENTAGE=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_SIZE_BYTES / $USED_DISK_BYTES) * 100}")
fi

# 4. Display the summary
echo "================================================================="
echo "📊 Disk Usage Summary"
echo "================================================================="
echo ""
echo "Total GNS3 VM Disks:   $TOTAL_VM_HUMAN"
echo "Total Used (GNS3 VM):  $USED_DISK_HUMAN"
echo "Total Capacity (GNS3 VM): $TOTAL_DISK_HUMAN"
echo ""
echo "=> The GNS3 project VMs occupy $PERCENTAGE% of the total used disk space."
echo ""
