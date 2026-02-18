#!/bin/bash

# --- CONFIGURATIE ---
NETWORK_PREFIX="10.1.51"
USER="gns3"
PASS="gns3"
SOURCE_DIR="/opt/gns3/images/QEMU"
DEST_DIR="/opt/gns3/images/QEMU"
LATEST_VERSION="1.2.0"
GITHUB_URL="https://raw.githubusercontent.com/MarkKlerkx/gns3/refs/heads/main/gns3_monitor.sh"

# --- TEMPLATES DEFINITIES ---
# Firefox-TCL
T1_NAME="Firefox-TCL"
T1_FILE="TCL_Firefox.qcow2"
T1_JSON='{"name": "Firefox-TCL", "default_name_format": "{name}-{0}", "usage": "", "symbol": "firefox.svg", "category": "guest", "port_name_format": "Ethernet{0}", "port_segment_size": 0, "first_port_name": "", "custom_adapters": [], "qemu_path": "/usr/bin/qemu-system-x86_64", "hda_disk_image": "TCL_Firefox.qcow2", "hdb_disk_image": "", "hdc_disk_image": "", "hdd_disk_image": "", "hda_disk_interface": "virtio", "hdb_disk_interface": "none", "hdc_disk_interface": "none", "hdd_disk_interface": "none", "cdrom_image": "", "bios_image": "", "boot_priority": "c", "console_type": "vnc", "console_auto_start": false, "ram": 512, "cpus": 1, "adapters": 1, "adapter_type": "virtio-net-pci", "mac_address": null, "legacy_networking": false, "replicate_network_connection_state": true, "tpm": false, "uefi": false, "create_config_disk": false, "on_close": "power_off", "platform": "", "cpu_throttling": 0, "process_priority": "normal", "options": "-device usb-tablet", "kernel_image": "", "initrd": "", "kernel_command_line": "", "linked_clone": true, "compute_id": "local", "template_id": "202a9360-b2be-44b5-b6b3-afd65b68909f", "template_type": "qemu", "builtin": false}'

# pfSense
T2_NAME="pfSense-CE 2.7.2-Preconfigured"
T2_FILE="pfsense-CE-272-preconfigured.qcow2"
T2_JSON='{"name": "pfSense-CE 2.7.2-Preconfigured", "default_name_format": "{name}-{0}", "usage": "Preconfigured pfSense image:\nWAN: DHCP\nLAN01: 192.168.1.0/24\nLAN02: 192.168.2.0/24\n\nBasic firewall rule on LAN02: any any\n\nLogin:\nUsername: admin\nPassword: pfsense\n", "symbol": "pfSense.svg", "category": "guest", "port_name_format": "Ethernet{0}", "port_segment_size": 0, "first_port_name": "", "custom_adapters": [], "qemu_path": "/bin/qemu-system-x86_64", "hda_disk_image": "pfsense-CE-272-preconfigured.qcow2", "hdb_disk_image": "", "hdc_disk_image": "", "hdd_disk_image": "", "hda_disk_interface": "virtio", "hdb_disk_interface": "none", "hdc_disk_interface": "none", "hdd_disk_interface": "none", "cdrom_image": "", "bios_image": "", "boot_priority": "c", "console_type": "vnc", "console_auto_start": false, "ram": 1024, "cpus": 1, "adapters": 6, "adapter_type": "virtio-net-pci", "mac_address": null, "legacy_networking": false, "replicate_network_connection_state": true, "tpm": false, "uefi": false, "create_config_disk": false, "on_close": "power_off", "platform": "", "cpu_throttling": 0, "process_priority": "normal", "options": "-enable-kvm -cpu qemu64", "kernel_image": "", "initrd": "", "kernel_command_line": "", "linked_clone": true, "compute_id": "local", "template_id": "7dcfca65-a804-4ccb-a5c5-4e2972132539", "template_type": "qemu", "builtin": false}'

echo "--- GNS3 Fleet Sync & Template Injector v2.8 ---"

for i in {1..254}; do
    IP="$NETWORK_PREFIX.$i"
    
    echo "----------------------------------------------------"
    echo -n "[$IP] SSH test... "
    if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 "$USER@$IP" "true" 2>/dev/null; then
        echo "Skipped (Offline/No Auth)."
        continue
    fi
    echo "OK."

    # --- DEEL A: MONITOR SCRIPT UPDATE ---
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" << EOF
        if [ -f /usr/local/bin/gns3_monitor.sh ]; then
            REMOTE_V=\$(grep 'VERSION=' /usr/local/bin/gns3_monitor.sh | cut -d'"' -f2)
            if [ "\$REMOTE_V" != "$LATEST_VERSION" ]; then
                sudo wget -q -O /usr/local/bin/gns3_monitor.sh "$GITHUB_URL"
                sudo chmod 0755 /usr/local/bin/gns3_monitor.sh
                echo "  -> Monitor script geüpdatet naar $LATEST_VERSION"
            fi
        fi
EOF

    # --- DEEL B: IMAGE CHECK & SYNC ---
    for IMG in "$T1_FILE" "$T2_FILE"; do
        if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "[ -f \"$DEST_DIR/$IMG\" ]" 2>/dev/null; then
            echo "  -> Kopieer ontbrekende image: $IMG"
            sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SOURCE_DIR/$IMG" "$USER@$IP:$DEST_DIR/"
            sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo chown gns3:gns3 \"$DEST_DIR/$IMG\""
        else
            echo "  -> Image aanwezig: $IMG"
        fi
    done

    # --- DEEL C: TEMPLATE INJECTIE ---
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" << EOF
        if ! command -v jq &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq > /dev/null 2>&1
        fi

        CONF="/home/gns3/.config/GNS3/2.2/gns3_controller.conf"
        RESTART_NEEDED=0

        # Inject Template 1 (Firefox)
        if ! jq -e '.templates[] | select(.name == "$T1_NAME")' "\$CONF" > /dev/null 2>&1; then
            echo "  -> Injecteren: $T1_NAME"
            jq --argjson t1 '$T1_JSON' '.templates = [\$t1] + .templates' "\$CONF" > "/tmp/conf.tmp" && mv "/tmp/conf.tmp" "/tmp/gns3_inject.tmp"
            RESTART_NEEDED=1
        fi

        # Inject Template 2 (pfSense)
        # We checken op de (eventueel al aangepaste) tmp file of de originele conf
        TARGET_FILE=\${RESTART_NEEDED:+"/tmp/gns3_inject.tmp"}
        TARGET_FILE=\${TARGET_FILE:-"\$CONF"}

        if ! jq -e '.templates[] | select(.name == "$T2_NAME")' "\$TARGET_FILE" > /dev/null 2>&1; then
            echo "  -> Injecteren: $T2_NAME"
            jq --argjson t2 '$T2_JSON' '.templates = [\$t2] + .templates' "\$TARGET_FILE" > "/tmp/gns3_inject.tmp"
            RESTART_NEEDED=1
        fi

        if [ \$RESTART_NEEDED -eq 1 ]; then
            sudo mv "/tmp/gns3_inject.tmp" "\$CONF"
            sudo chown gns3:gns3 "\$CONF"
            sudo chmod 664 "\$CONF"
            sudo systemctl restart gns3
            echo "  -> GNS3 herstart en templates toegevoegd."
        else
            echo "  -> Beide templates reeds aanwezig in config."
        fi
EOF
done

echo "--- Klaar! ---"
