#!/bin/bash

# --- CONFIGURATIE ---
NETWORK_PREFIX="10.1.51"
USER="gns3"
PASS="gns3"

# Bronlocaties op jouw Master VM (gebaseerd op jouw find)
SOURCE_QEMU="/opt/gns3/images/QEMU"
SOURCE_SYMBOLS="/home/gns3/GNS3/symbols"

# Bestemming op de student VM's
DEST_QEMU="/opt/gns3/images/QEMU"
DEST_SYMBOLS="/opt/gns3/symbols"

LATEST_VERSION="1.2.0"
GITHUB_URL="https://raw.githubusercontent.com/MarkKlerkx/gns3/refs/heads/main/gns3_monitor.sh"

# Bestandenlijsten
IMAGES=("TCL_Firefox.qcow2" "pfsense-CE-272-preconfigured.qcow2")
SYMBOLS=("firefox.svg" "pfSense.svg")

TEMPLATES_JSON_DATA='{
  "t1": {"name": "Firefox-TCL", "default_name_format": "{name}-{0}", "usage": "", "symbol": "firefox.svg", "category": "guest", "port_name_format": "Ethernet{0}", "port_segment_size": 0, "first_port_name": "", "custom_adapters": [], "qemu_path": "/usr/bin/qemu-system-x86_64", "hda_disk_image": "TCL_Firefox.qcow2", "hdb_disk_image": "", "hdc_disk_image": "", "hdd_disk_image": "", "hda_disk_interface": "virtio", "hdb_disk_interface": "none", "hdc_disk_interface": "none", "hdd_disk_interface": "none", "cdrom_image": "", "bios_image": "", "boot_priority": "c", "console_type": "vnc", "console_auto_start": false, "ram": 512, "cpus": 1, "adapters": 1, "adapter_type": "virtio-net-pci", "mac_address": null, "legacy_networking": false, "replicate_network_connection_state": true, "tpm": false, "uefi": false, "create_config_disk": false, "on_close": "power_off", "platform": "", "cpu_throttling": 0, "process_priority": "normal", "options": "-device usb-tablet", "kernel_image": "", "initrd": "", "kernel_command_line": "", "linked_clone": true, "compute_id": "local", "template_id": "202a9360-b2be-44b5-b6b3-afd65b68909f", "template_type": "qemu", "builtin": false},
  "t2": {"name": "pfSense-CE 2.7.2-Preconfigured", "default_name_format": "{name}-{0}", "usage": "Preconfigured pfSense image:\nWAN: DHCP\nLAN01: 192.168.1.0/24\nLAN02: 192.168.2.0/24\n\nBasic firewall rule on LAN02: any any\n\nLogin:\nUsername: admin\nPassword: pfsense\n", "symbol": "pfSense.svg", "category": "guest", "port_name_format": "Ethernet{0}", "port_segment_size": 0, "first_port_name": "", "custom_adapters": [], "qemu_path": "/bin/qemu-system-x86_64", "hda_disk_image": "pfsense-CE-272-preconfigured.qcow2", "hdb_disk_image": "", "hdc_disk_image": "", "hdd_disk_image": "", "hda_disk_interface": "virtio", "hdb_disk_interface": "none", "hdc_disk_interface": "none", "hdd_disk_interface": "none", "cdrom_image": "", "bios_image": "", "boot_priority": "c", "console_type": "vnc", "console_auto_start": false, "ram": 1024, "cpus": 1, "adapters": 6, "adapter_type": "virtio-net-pci", "mac_address": null, "legacy_networking": false, "replicate_network_connection_state": true, "tpm": false, "uefi": false, "create_config_disk": false, "on_close": "power_off", "platform": "", "cpu_throttling": 0, "process_priority": "normal", "options": "-enable-kvm -cpu qemu64", "kernel_image": "", "initrd": "", "kernel_command_line": "", "linked_clone": true, "compute_id": "local", "template_id": "7dcfca65-a804-4ccb-a5c5-4e2972132539", "template_type": "qemu", "builtin": false}
}'

echo "--- GNS3 Fleet Sync v3.7 ---"

# --- PRE-FLIGHT CHECK ---
echo "[CHECK] Controleren lokale bestanden op Master VM..."
for f in "${IMAGES[@]}"; do
    if [ ! -f "$SOURCE_QEMU/$f" ]; then echo "  -> FOUT: $f niet gevonden in $SOURCE_QEMU"; exit 1; fi
done
for s in "${SYMBOLS[@]}"; do
    if [ ! -f "$SOURCE_SYMBOLS/$s" ]; then echo "  -> FOUT: $s niet gevonden in $SOURCE_SYMBOLS"; exit 1; fi
done
echo "  -> Alle bronbestanden aanwezig. Start loop."

for i in {1..254}; do
    IP="$NETWORK_PREFIX.$i"
    echo "===================================================="
    echo "HOST: $IP"
    
    if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 "$USER@$IP" "true" 2>/dev/null; then
        echo "[STATUS] Offline."
        continue
    fi

    # --- STAP 0: CLEANUP ---
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo killall -9 swaks 2>/dev/null"

    # --- STAP 1: SYMBOL SYNC ---
    echo "[STAP 1] Controleren iconen..."
    for SYM in "${SYMBOLS[@]}"; do
        if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "[ -f \"$DEST_SYMBOLS/$SYM\" ]" 2>/dev/null; then
            echo "  -> KOPIËREN: $SYM..."
            sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo mkdir -p $DEST_SYMBOLS && sudo chown gns3:gns3 $DEST_SYMBOLS"
            sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SOURCE_SYMBOLS/$SYM" "$USER@$IP:$DEST_SYMBOLS/"
            sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo chown gns3:gns3 $DEST_SYMBOLS/$SYM"
        else
            echo "  -> OK: $SYM aanwezig."
        fi
    done

    # --- STAP 2: IMAGE SYNC ---
    echo "[STAP 2] Controleren QCOW2 images..."
    for IMG in "${IMAGES[@]}"; do
        if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "[ -f \"$DEST_QEMU/$IMG\" ]" 2>/dev/null; then
            echo "  -> KOPIËREN: $IMG..."
            sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SOURCE_QEMU/$IMG" "$USER@$IP:$DEST_QEMU/"
            sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo chown gns3:gns3 \"$DEST_QEMU/$IMG\""
        else
            echo "  -> OK: $IMG aanwezig."
        fi
    done

    # --- STAP 3: CONFIG INJECTIE ---
    echo "[STAP 3] Injecteren templates in gns3_controller.conf..."
    echo "$TEMPLATES_JSON_DATA" | sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "cat > /tmp/templates_to_add.json"

    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" << 'EOF'
        CONF="/home/gns3/.config/GNS3/2.2/gns3_controller.conf"
        JSON_IN="/tmp/templates_to_add.json"
        
        if ! command -v jq &> /dev/null; then sudo apt-get update && sudo apt-get install -y jq >/dev/null 2>&1; fi

        T1_M=$(jq -e '.templates[] | select(.name == "Firefox-TCL")' "$CONF" >/dev/null 2>&1; echo $?)
        T2_M=$(jq -e '.templates[] | select(.name == "pfSense-CE 2.7.2-Preconfigured")' "$CONF" >/dev/null 2>&1; echo $?)

        if [ $T1_M -ne 0 ] || [ $T2_M -ne 0 ]; then
            cp "$CONF" "${CONF}.bak"
            cp "$CONF" /tmp/work.conf
            
            [ $T1_M -ne 0 ] && jq --argjson t "$(jq .t1 $JSON_IN)" '.templates = [$t] + .templates' /tmp/work.conf > /tmp/s.json && mv /tmp/s.json /tmp/work.conf
            [ $T2_M -ne 0 ] && jq --argjson t "$(jq .t2 $JSON_IN)" '.templates = [$t] + .templates' /tmp/work.conf > /tmp/s.json && mv /tmp/s.json /tmp/work.conf

            if [ -s /tmp/work.conf ] && jq . /tmp/work.conf >/dev/null 2>&1; then
                cp /tmp/work.conf "$CONF"
                sudo chown gns3:gns3 "$CONF" && sudo chmod 664 "$CONF"
                sudo systemctl restart gns3 && echo "  -> [SUCCES] GNS3 herstart met nieuwe templates."
            fi
        else
            echo "  -> OK: Templates reeds in config."
        fi
        rm -f "$JSON_IN" /tmp/work.conf /tmp/s.json
EOF
done

echo "--- Klaar! ---"
