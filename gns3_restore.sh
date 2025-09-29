#!/bin/bash

# ==============================================================================
# GNS3 VM Recovery Script (Version 3.5 - pfSense Adapter Fix)
#
# Author: Gemini
# Version: 3.5
#
# CHANGES (v3.5):
# - Adds a rule to automatically set 4 network adapters if the
#   'hda_disk_image' contains the name 'pfSense'.
#
# Previous features:
# - 'on_close' property moved to the 'properties' object.
# - Sets 'on_close' to 'shutdown_signal' for a correct shutdown.
# - Conditionally adds the 'bios_image' property for specific VMs.
# - Creates a backup of the original .gns3 file.
# - Restores the project under its original filename.
# - Automatically scans all projects in '/opt/gns3/projects'.
# ==============================================================================

# --- Configuration ---
BASE_PROJECTS_DIR="/opt/gns3/projects"
JQ_CMD="jq"
QEMU_IMG_CMD="qemu-img"

# --- Script Logic ---

# Check if the base projects directory exists
if [ ! -d "$BASE_PROJECTS_DIR" ]; then
    echo "❌ Error: The GNS3 projects directory '${BASE_PROJECTS_DIR}' was not found."
    exit 1
fi

# Check if required tools are installed
if ! command -v $JQ_CMD &> /dev/null || ! command -v $QEMU_IMG_CMD &> /dev/null; then
    echo "❌ Error: Please ensure 'jq' and 'qemu-utils' are installed."
    exit 1
fi

echo "🚀 Starting recovery of all projects in '${BASE_PROJECTS_DIR}'..."
echo "------------------------------------------------------------------"

# Loop through each subdirectory in the GNS3 projects directory
for project_dir in "${BASE_PROJECTS_DIR}"/*/; do
    if [ ! -d "$project_dir" ]; then continue; fi

    PROJECT_PATH=$(realpath "${project_dir}")
    PROJECT_UUID=$(basename "$PROJECT_PATH")

    echo "▶️ Processing project: ${PROJECT_UUID}"

    # Step 1: Find the original .gns3 project file
    original_gns3_file=$(find "${PROJECT_PATH}" -maxdepth 1 -type f -name "*.gns3" | head -n 1)
    if [ -z "$original_gns3_file" ]; then
        echo "   -> ⚠️ Skipped: No .gns3 file found in this directory."
        echo "------------------------------------------------------------------"
        continue
    fi
    echo "   -> Found project file: $(basename "$original_gns3_file")"

    # Step 2: Create a backup of the original file
    backup_date=$(date +%Y-%m-%d)
    backup_file_path="${original_gns3_file}.backup-${backup_date}"
    if [ -f "$backup_file_path" ]; then
        echo "   -> ℹ️ A backup for today already exists, not creating a new one."
    else
        echo "   -> Creating backup at: $(basename "$backup_file_path")"
        mv "$original_gns3_file" "$backup_file_path"
    fi

    QEMU_DIR="${PROJECT_PATH}/project-files/qemu"
    if [ ! -d "$QEMU_DIR" ]; then
        echo "   -> ⚠️ Skipped: Directory '${QEMU_DIR}' not found."
        echo "------------------------------------------------------------------"
        continue
    fi

    # Generate the JSON array for all nodes (VMs)
    node_json_array=$((
        x_pos=-250
        y_pos=0
        for vm_dir in "${QEMU_DIR}"/*/; do
            if [ ! -d "$vm_dir" ]; then continue; fi

            vm_uuid=$(basename "$vm_dir")
            log_file="${vm_dir}qemu.log"
            hda_disk_file="${vm_dir}hda_disk.qcow2"
            if [ ! -f "$log_file" ] || [ ! -s "$log_file" ]; then continue; fi

            first_line=$(head -n 1 "$log_file" | tr -d '\r')
            vm_name="${vm_uuid}"

            if [[ "$first_line" == *"-name "* ]]; then
                after_name_param=${first_line##*-name }; vm_name_raw=${after_name_param%% -*}
                temp_name=${vm_name_raw#\"}; extracted_name=${temp_name%\"}
                if [ -n "$extracted_name" ]; then vm_name="$extracted_name"; fi
            fi

            ram=1024; cpus=1; adapters=1; adapter_type="e1000"
            qemu_path="/bin/qemu-system-x86_64"; platform="x86_64"
            hda_disk_image=""; hda_disk_interface="ide"; bios_image="" # Reset bios_image
            
            if [ -f "$hda_disk_file" ]; then
                backing_file=$($QEMU_IMG_CMD info "$hda_disk_file" | grep 'backing file:' | awk '{print $3}')
                if [ -n "$backing_file" ]; then hda_disk_image=$(basename "$backing_file"); fi
            fi

            if [ "$hda_disk_image" == "Windows11Preset.qcow2" ]; then
                bios_image="OVMF-edk2-stable202305.fd"
                echo "      -> ✨ UEFI BIOS set for Windows 11 VM." >&2
            fi
            
            extracted_drive_info=$(echo "$first_line" | grep -oP -- "-drive file.*?if=\K[^,]+")
            if [ -n "$extracted_drive_info" ]; then hda_disk_interface=$extracted_drive_info; fi
            extracted_qemu_path=$(echo "$first_line" | awk '{print $4}')
            if [ -n "$extracted_qemu_path" ] && [ -f "$extracted_qemu_path" ]; then
                qemu_path=$extracted_qemu_path; platform=$(basename "$qemu_path" | sed 's/qemu-system-//')
            fi
            extracted_ram=$(echo "$first_line" | grep -oP -- '-m\s+\K[0-9]+'); if [ -n "$extracted_ram" ]; then ram=$extracted_ram; fi
            extracted_cpus=$(echo "$first_line" | grep -oP -- '-smp\s+[^,]*cpus=\K[0-9]+'); if [ -n "$extracted_cpus" ]; then cpus=$extracted_cpus; fi
            extracted_adapters=$(echo "$first_line" | grep -o -- "-device[^ ]*,mac=" | wc -l); if [ "$extracted_adapters" -gt 0 ]; then adapters=$extracted_adapters; fi
            extracted_adapter_type=$(echo "$first_line" | grep -oP -- "-device\s+\K[^,]+" | head -n 1); if [ -n "$extracted_adapter_type" ]; then adapter_type=$extracted_adapter_type; fi
            
            # --- NEW LOGIC HERE ---
            # Override the number of adapters if the disk image name contains 'pfSense'.
            if [[ "$hda_disk_image" == *"pfSense"* ]]; then
                adapters=4
                echo "      -> 🔥 pfSense detected, setting adapters to 4." >&2
            fi
            # --- END OF NEW LOGIC ---

            echo "      -> VM: '${vm_name}' | Disk: ${hda_disk_image}" >&2

            # Create JSON, and conditionally add the bios_image
            $JQ_CMD -n \
                --arg name "$vm_name" --arg node_id "$vm_uuid" \
                --argjson x "$x_pos" --argjson y "$y_pos" \
                --argjson ram "$ram" --argjson cpus "$cpus" \
                --argjson adapters "$adapters" --arg adapter_type "$adapter_type" \
                --arg qemu_path "$qemu_path" --arg platform "$platform" \
                --arg hda_disk_image "$hda_disk_image" --arg hda_disk_interface "$hda_disk_interface" \
                --arg bios_image "$bios_image" \
                '
                {
                    "compute_id": "local", "console_auto_start": false, "console_type": "vnc",
                    "name": $name, "node_id": $node_id, "node_type": "qemu",
                    "symbol": ":/symbols/qemu_guest.svg", "template_id": null,
                    "x": $x, "y": $y, "z": 1,
                    "label": {"text": $name, "style": "font-family: TypeWriter;font-size: 10.0;font-weight: bold;", "x": 0, "y": -25, "rotation": 0},
                    "properties": {
                        "on_close": "shutdown_signal",
                        "adapter_type": $adapter_type, "adapters": $adapters, "cpus": $cpus, "ram": $ram,
                        "hda_disk_image": $hda_disk_image, "hda_disk_interface": $hda_disk_interface,
                        "linked_clone": true, "qemu_path": $qemu_path, "platform": $platform
                    }
                } | if $bios_image != "" then .properties.bios_image = $bios_image else . end
                '
            x_pos=$((x_pos + 250))
        done
    ) | $JQ_CMD -s '.')

    if [ -z "$node_json_array" ] || [[ "$node_json_array" == "[]" ]]; then
        echo "   -> ⚠️ No VMs found, an empty project file will be created."
        node_json_array="[]"
    fi

    project_name=$(basename "$original_gns3_file" .gns3)
    project_json=$(
        $JQ_CMD -n \
            --arg project_id "$PROJECT_UUID" --argjson nodes "$node_json_array" \
            --arg name "${project_name} (Restored)" \
            '{"name": $name, "project_id": $project_id, "type": "topology", "revision": 9, "version": "2.2.54", "zoom": 100, "scene_height": 1000, "scene_width": 2000, "topology": {"computes": [], "drawings": [], "links": [], "nodes": $nodes}}'
    )

    # Save the new project under the original filename
    output_path="$original_gns3_file"
    echo "$project_json" > "$output_path"

    echo "   -> ✅ Success! Project restored and saved as:"
    echo "      ${output_path}"
    echo "------------------------------------------------------------------"
done

echo "🎉 All projects have been processed."
