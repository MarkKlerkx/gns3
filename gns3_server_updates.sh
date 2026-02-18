#!/bin/bash

# --- CONFIGURATIE ---
NETWORK="10.1.51"
USER="gns3"
PASS="gns3"
# De bron-folder op de machine waar je NU op werkt
SOURCE_DIR="/opt/gns3/images/QEMU"
# De doel-folder op de remote GNS3 VM's
DEST_DIR="/opt/gns3/images/QEMU"

LATEST_VERSION="1.2.0"
GITHUB_URL="https://raw.githubusercontent.com/MarkKlerkx/gns3/refs/heads/main/gns3_monitor.sh"

echo "--- GNS3 Master Sync: $SOURCE_DIR naar netwerk $NETWORK.x ---"

# 1. Maak een lijst van alle .qcow2 bestanden in de lokale bron-folder
# We filteren op .qcow2 om te voorkomen dat we logs of tijdelijke files sturen
IMAGES=$(ls "$SOURCE_DIR" | grep ".qcow2")

for i in {1..254}; do
    IP="$NETWORK.$i"
    
    if ping -c 1 -W 1 "$IP" > /dev/null 2>&1; then
        echo "----------------------------------------------------"
        echo "[$IP] Verbinding maken..."

        # --- DEEL A: SCRIPT & VERSIE UPDATE ---
        sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" << EOF
            # Check of het monitor script bestaat
            if [ -f /usr/local/bin/gns3_monitor.sh ]; then
                CURRENT_V=\$(grep 'VERSION=' /usr/local/bin/gns3_monitor.sh | cut -d'"' -f2)
                if [ "\$CURRENT_V" != "$LATEST_VERSION" ]; then
                    echo "[$IP] Update script naar $LATEST_VERSION"
                    sudo wget -q -O /usr/local/bin/gns3_monitor.sh $GITHUB_URL
                    sudo chmod 0755 /usr/local/bin/gns3_monitor.sh
                fi
            fi
EOF

        # --- DEEL B: IMAGE SYNC ---
        for IMG in $IMAGES; do
            # Controleer of de image al bestaat op de doel-machine
            # We gebruiken 'ls' op de remote host; als die faalt, moet de file gekopieerd worden.
            sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "[ -f $DEST_DIR/$IMG ]"
            
            if [ $? -ne 0 ]; then
                echo "[$IP] ! Kopieer ontbrekende image: $IMG"
                # Gebruik scp om het bestand over te zetten
                sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SOURCE_DIR/$IMG" "$USER@$IP:$DEST_DIR/"
                # Herstel rechten op de remote machine
                sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo chown gns3:gns3 $DEST_DIR/$IMG"
            else
                echo "[$IP] OK: $IMG reeds aanwezig."
            fi
        done
    fi
done

echo "--- Master Sync Voltooid ---"
