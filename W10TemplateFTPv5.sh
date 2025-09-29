#!/bin/bash
set -e  # Exit script immediately if a command exits with a non-zero status.

# --- VARIABLES ---
# FTP Settings
FTP_SERVER="10.1.51.44"
FTP_FILE="Windows10Template.qcow2"

# GNS3 Settings
GNS3_IMAGE_DIR="/opt/gns3/images/QEMU"
GNS3_CONFIG_FILE="/home/gns3/.config/GNS3/2.2/gns3_controller.conf"
TEMPLATE_NAME="Windows10Template"
LOCAL_FILE_PATH="$GNS3_IMAGE_DIR/$FTP_FILE"
GNS3_SERVICE_NAME="gns3" # Service name updated to 'gns3'

# Space requirement (15GB in KB)
REQUIRED_SPACE_KB=$((15 * 1024 * 1024))

# JSON data for the new template
TEMPLATE_JSON='{"name":"Windows10Template","default_name_format":"{name}-{0}","usage":"","symbol":"Microsoft_logo.svg","category":"guest","port_name_format":"Ethernet{0}","port_segment_size":0,"first_port_name":"","custom_adapters":[],"qemu_path":"/bin/qemu-system-x86_64","hda_disk_image":"Windows10Template.qcow2","hdb_disk_image":"","hdc_disk_image":"","hdd_disk_image":"","hda_disk_interface":"ide","hdb_disk_interface":"none","hdc_disk_interface":"none","hdd_disk_interface":"none","cdrom_image":"","bios_image":"","boot_priority":"c","console_type":"vnc","console_auto_start":false,"ram":2048,"cpus":2,"adapters":1,"adapter_type":"e1000","mac_address":null,"legacy_networking":false,"replicate_network_connection_state":true,"tpm":false,"uefi":false,"create_config_disk":false,"on_close":"shutdown_signal","platform":"","cpu_throttling":0,"process_priority":"normal","options":"","kernel_image":"","initrd":"","kernel_command_line":"","linked_clone":true,"compute_id":"local","template_id":"6a40307a-5da1-4add-bf22-6ed4a94a5606","template_type":"qemu","builtin":false}'

# --- CHECK REQUIRED SOFTWARE ---
if ! command -v lftp &> /dev/null || ! command -v jq &> /dev/null; then
    echo "lftp and/or jq not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y lftp jq
fi

# --- STEP 1: DOWNLOAD THE IMAGE ---
echo "--- Step 1: Checking and downloading QEMU image ---"
if [ -f "$LOCAL_FILE_PATH" ]; then
    echo "✅ Image already exists: $LOCAL_FILE_PATH. Skipping download."
else
    echo "Image not found. Starting download procedure..."
    
    # Check for available disk space
    echo "Checking for available disk space..."
    AVAILABLE_SPACE_KB=$(df -k "$GNS3_IMAGE_DIR" | tail -1 | awk '{print $4}')
    
    if [ "$AVAILABLE_SPACE_KB" -lt "$REQUIRED_SPACE_KB" ]; then
        echo "❌ ERROR: Not enough disk space."
        echo "Required: 15 GB, Available: $(($AVAILABLE_SPACE_KB / 1024 / 1024)) GB."
        echo "Please free up space on the partition for $GNS3_IMAGE_DIR and run the script again."
        exit 1
    else
        echo "✅ Sufficient disk space available. Proceeding with download."
    fi

    mkdir -p "$GNS3_IMAGE_DIR"
    lftp -u anonymous, $FTP_SERVER <<EOF
set ftp:passive-mode on
lcd $GNS3_IMAGE_DIR
get $FTP_FILE
bye
EOF
    echo "✅ Download complete: $LOCAL_FILE_PATH"
fi

# --- STEP 2: ADD TEMPLATE TO GNS3 CONFIGURATION ---
echo ""
echo "--- Step 2: Adding template to GNS3 configuration ---"

if [ ! -f "$GNS3_CONFIG_FILE" ]; then
    echo "❌ ERROR: GNS3 configuration file not found at $GNS3_CONFIG_FILE"
    exit 1
fi

NEEDS_POST_CONFIG_STEPS=false
if jq -e '.templates[] | select(.name == "'"$TEMPLATE_NAME"'")' "$GNS3_CONFIG_FILE" > /dev/null; then
    echo "✅ Template '$TEMPLATE_NAME' already exists in the configuration. Skipping action."
else
    echo "Template '$TEMPLATE_NAME' not found. Adding..."
    jq --argjson new_template "$TEMPLATE_JSON" '.templates = [$new_template] + .templates' "$GNS3_CONFIG_FILE" > "$GNS3_CONFIG_FILE.tmp" && mv "$GNS3_CONFIG_FILE.tmp" "$GNS3_CONFIG_FILE"
    echo "✅ Template successfully added to $GNS3_CONFIG_FILE"
    NEEDS_POST_CONFIG_STEPS=true # Mark that subsequent steps are needed
fi

# --- STEP 3: SET PERMISSIONS AND RESTART SERVICE (if needed) ---
echo ""
echo "--- Step 3: Finalizing configuration ---"
if [ "$NEEDS_POST_CONFIG_STEPS" = true ]; then
    # Set owner and group to gns3:gns3
    echo "Setting owner and permissions for configuration file..."
    sudo chown gns3:gns3 "$GNS3_CONFIG_FILE"
    
    # Set permissions to -rw-rw-r-- (664)
    sudo chmod 664 "$GNS3_CONFIG_FILE"
    echo "✅ Owner and permissions set correctly."

    # Restart the service to apply changes
    echo "Restarting GNS3 service to apply changes..."
    sudo systemctl restart "$GNS3_SERVICE_NAME"
    echo "✅ GNS3 service has been restarted."
else
    echo "No changes were made to the configuration, subsequent steps are not required."
fi

echo ""
echo "Script finished successfully!"

# --- FINAL MESSAGE ---
# Define color codes for readability
YELLOW='\e[1;33m'
RED_BOLD='\e[1;31m'
NC='\e[0m' # No Color (reset)

echo ""
# Use the -e flag to interpret the color codes
echo -e "${YELLOW}###############################################################################${NC}"
echo -e "${YELLOW}#                                                                              #${NC}"
echo -e "${YELLOW}#                           IMPORTANT: ACTION REQUIRED                           #${NC}"
echo -e "${YELLOW}#                                                                              #${NC}"
echo -e "${YELLOW}###############################################################################${NC}"
echo ""
echo "The Windows 10 template is ready. To complete the cleanup, please follow these steps:"
echo ""
echo -e "${YELLOW}Step 1: Remove the Windows 11 VMs from your GNS3 Project${NC}"
echo "   - Open your GNS3 projects and delete any VMs that use the old Windows 11 template."
echo ""
echo -e "${YELLOW}Step 2: Delete the Windows 11 Template from GNS3${NC}"
echo "   - In GNS3, go to 'Edit' -> 'Preferences' -> 'QEMU VMs'."
echo "   - Select the 'Windows 11' template and click 'Delete'."
echo ""
echo -e "${YELLOW}Step 3: Delete the Template Disk Files from the Server${NC}"
echo "   - Finally, run the following command in the server console to remove the actual files:"
echo -e "   ${RED_BOLD}sudo rm /opt/gns3/images/QEMU/Windows11Preset.*${NC}"
echo ""
echo -e "${YELLOW}--------------------------------------------------------------------------------${NC}"
