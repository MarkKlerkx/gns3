#!/bin/bash

# --- CONFIGURATIE ---
NETWORK_PREFIX="10.1.51"
USER="gns3"
PASS="gns3"
SOURCE_DIR="/opt/gns3/images/QEMU"
DEST_DIR="/opt/gns3/images/QEMU"
LATEST_VERSION="1.2.0"
GITHUB_URL="https://raw.githubusercontent.com/MarkKlerkx/gns3/refs/heads/main/gns3_monitor.sh"

echo "--- GNS3 Fleet Sync v2.6 (Generiek & Anti-Hang) ---"

# 1. Haal lijst van images op
IMAGES=$(ls "$SOURCE_DIR" | grep -E ".qcow2|.md5sum")

for i in {1..254}; do
    IP="$NETWORK_PREFIX.$i"
    
    echo "----------------------------------------------------"
    echo -n "[$IP] SSH test... "

    # Test verbinding met korte timeout
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
                          -o ConnectTimeout=3 \
                          -o ServerAliveInterval=2 \
                          -o ServerAliveCountMax=1 \
                          "$USER@$IP" "true" 2>/dev/null
    SSH_STATUS=$?

    if [ $SSH_STATUS -ne 0 ]; then
        echo "Overslaan (Onbereikbaar/Fout)."
        continue
    fi

    echo "OK. Start updates."

    # --- DEEL A: SCRIPT UPDATE MET STATUS FEEDBACK ---
    # We voegen 'timeout 30' toe om te voorkomen dat wget de hele boel blokkeert
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$USER@$IP" << EOF
        if [ -f /usr/local/bin/gns3_monitor.sh ]; then
            REMOTE_V=\$(grep 'VERSION=' /usr/local/bin/gns3_monitor.sh | cut -d'"' -f2)
            if [ "\$REMOTE_V" != "$LATEST_VERSION" ]; then
                echo "  -> Update nodig (Remote: \$REMOTE_V, Nieuw: $LATEST_VERSION)"
                sudo timeout 20 wget -q -O /usr/local/bin/gns3_monitor.sh "$GITHUB_URL"
                sudo chmod 0755 /usr/local/bin/gns3_monitor.sh
                echo "  -> Update voltooid."
            else
                echo "  -> Reeds up-to-date (v$LATEST_VERSION)."
            fi
        else
            echo "  -> Geen script aanwezig om te updaten."
        fi
EOF

    # --- DEEL B: IMAGE SYNC ---
    for IMG in $IMAGES; do
        # Check of image bestaat (ook met timeout)
        if ! sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$USER@$IP" "[ -f \"$DEST_DIR/$IMG\" ]" 2>/dev/null; then
            echo "  -> Kopieer: $IMG"
            # SCP heeft een eigen timeout mechanisme
            sshpass -p "$PASS" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SOURCE_DIR/$IMG" "$USER@$IP:$DEST_DIR/"
            sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "sudo chown gns3:gns3 \"$DEST_DIR/$IMG\""
        else
            echo "  -> Image aanwezig: $IMG"
        fi
    done
done

echo "--- Klaar ---"
