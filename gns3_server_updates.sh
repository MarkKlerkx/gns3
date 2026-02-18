#!/bin/bash

# --- CONFIGURATIE ---
NETWORK_PREFIX="10.1.51"
SUBNET_MASK="/24" # Gebruikt voor documentatie, loop loopt van 1-254
USER="gns3"
PASS="gns3"
SOURCE_DIR="/opt/gns3/images/QEMU"
DEST_DIR="/opt/gns3/images/QEMU"
LATEST_VERSION="1.2.0"
GITHUB_URL="https://raw.githubusercontent.com/MarkKlerkx/gns3/refs/heads/main/gns3_monitor.sh"

echo "--- GNS3 Fleet Sync v2.5 ---"
echo "Target: $NETWORK_PREFIX.0$SUBNET_MASK"
echo "Referentie: $SOURCE_DIR"

# 1. Haal lijst van images op
IMAGES=$(ls "$SOURCE_DIR" | grep -E ".qcow2|.md5sum")

# Loop door het volledige /24 subnet (1 t/m 254)
for i in {1..254}; do
    IP="$NETWORK_PREFIX.$i"
    
    echo "----------------------------------------------------"
    echo -n "[$IP] SSH Verbinding testen... "

    # We proberen direct in te loggen. 
    # -o ConnectTimeout=3 zorgt dat we niet te lang wachten op dode IP's.
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
                          -o ConnectTimeout=3 \
                          -o BatchMode=no \
                          "$USER@$IP" "true" 2>/dev/null
    SSH_STATUS=$?

    if [ $SSH_STATUS -ne 0 ]; then
        if [ $SSH_STATUS -eq 255 ]; then
            echo "ONBEREIKBAAR (Connection refused/timeout)."
        elif [ $SSH_STATUS -eq 5 ]; then
            echo "GEWEIGERD (Wachtwoord onjuist)."
        else
            echo "FOUT (Code: $SSH_STATUS)."
        fi
        continue # Direct naar het volgende IP
    fi

    echo "OK! Verwerken..."

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
        if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "[ -f \"$DEST_DIR/$IMG\" ]" 2>/dev/null; then
            echo "  -> Kopieer: $IMG"
            sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SOURCE_DIR/$IMG" "$USER@$IP:$DEST_DIR/"
            sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo chown gns3:gns3 \"$DEST_DIR/$IMG\""
        else
            echo "  -> OK: $IMG"
        fi
    done
done

echo "--- Klaar ---"
