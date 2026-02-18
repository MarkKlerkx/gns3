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

# 1. Lijst van images (alleen .qcow2)
IMAGES=$(ls "$SOURCE_DIR" | grep ".qcow2")

for i in {1..254}; do
    IP="$NETWORK.$i"
    
    # Check of de host leeft
    if ping -c 1 -W 1 "$IP" > /dev/null 2>&1; then
        echo "----------------------------------------------------"
        echo "[$IP] Poging tot inloggen..."

        # --- DEEL A: TEST VERBINDING & SCRIPT UPDATE ---
        # We voeren een simpele check uit en vangen de exit code op ($?)
        sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$USER@$IP" "exit" 2>/dev/null
        
        if [ $? -ne 0 ]; then
            echo "[$IP] FOUT: Inloggen mislukt (Verkeerd wachtwoord of SSH-key issue). Overslaan..."
            continue  # Spring direct naar de volgende 'i' in de loop
        fi

        echo "[$IP] Ingelogd. Bezig met controles..."

        # Update het script
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
            # Check of file bestaat op remote host
            sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "[ -f $DEST_DIR/$IMG ]" 2>/dev/null
            
            if [ $? -ne 0 ]; then
                echo "[$IP] ! Kopieer ontbrekende image: $IMG"
                sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$SOURCE_DIR/$IMG" "$USER@$IP:$DEST_DIR/"
                sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo chown gns3:gns3 $DEST_DIR/$IMG"
            else
                echo "[$IP] OK: $IMG reeds aanwezig."
            fi
        done
    fi
done

echo "--- Master Sync Voltooid ---"
