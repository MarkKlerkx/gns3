#!/bin/bash

# --- CONFIGURATIE ---
NETWORK="10.1.51"
USER="gns3"
PASS="gns3"
SOURCE_DIR="/opt/gns3/images/QEMU"
DEST_DIR="/opt/gns3/images/QEMU"
LATEST_VERSION="1.2.0"
GITHUB_URL="https://raw.githubusercontent.com/MarkKlerkx/gns3/refs/heads/main/gns3_monitor.sh"

echo "--- GNS3 Master Sync: $SOURCE_DIR naar netwerk $NETWORK.x ---"

# 1. Haal de lijst van images op
IMAGES=$(ls "$SOURCE_DIR" | grep -E ".qcow2|.md5sum")

for i in {1..254}; do
    IP="$NETWORK.$i"
    
    if ping -c 1 -W 1 "$IP" > /dev/null 2>&1; then
        echo "----------------------------------------------------"
        echo -n "[$IP] Inlogpoging... "

        # CRUCIALE STAP: Test de verbinding. 
        # We proberen een simpel commando ('true'). Als dit faalt, skippen we ALLES voor deze IP.
        if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=no "$USER@$IP" "true" 2>/dev/null; then
            echo "GEWEIGERD (Permission Denied). Host wordt overgeslagen."
            continue
        fi

        echo "GEACCEPTEERD. Start verwerking..."

        # --- DEEL A: SCRIPT UPDATE ---
        sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" << EOF
            if [ -f /usr/local/bin/gns3_monitor.sh ]; then
                CURRENT_V=\$(grep 'VERSION=' /usr/local/bin/gns3_monitor.sh | cut -d'"' -f2)
                if [ "\$CURRENT_V" != "$LATEST_VERSION" ]; then
                    sudo wget -q -O /usr/local/bin/gns3_monitor.sh $GITHUB_URL
                    sudo chmod 0755 /usr/local/bin/gns3_monitor.sh
                fi
            fi
EOF

        # --- DEEL B: IMAGE SYNC ---
        for IMG in $IMAGES; do
            # Check of de image al bestaat op de remote host
            if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "[ -f $DEST_DIR/$IMG ]" 2>/dev/null; then
                echo "  -> Kopieer: $IMG"
                sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SOURCE_DIR/$IMG" "$USER@$IP:$DEST_DIR/"
                sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo chown gns3:gns3 $DEST_DIR/$IMG"
            else
                echo "  -> OK: $IMG aanwezig."
            fi
        done
    fi
done

echo "--- Master Sync Voltooid ---"
