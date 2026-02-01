#!/bin/bash
# GNS3 Ubuntu Server Optimization Script
# Voer dit uit met: sudo bash

echo "--- Start optimalisatie voor Ubuntu Server ---"

# 1. Update de package list
apt-get update

# 2. Verwijder Snap (grootste bron van vertraging en CPU-gebruik in Linux VM's)
echo "  - Snapd verwijderen..."
systemctl stop snapd
apt-get purge -y snapd
rm -rf /snap /var/snap /var/lib/snapd

# 3. Verwijder onnodige pakketten en cache
echo "  - Onnodige pakketten opschonen..."
apt-get autoremove -y
apt-get clean

# 4. Schakel de 'Cloud-Init' service uit (tenzij je deze specifiek gebruikt)
# Cloud-init vertraagt de boot-tijd in GNS3 enorm.
echo "  - Cloud-init uitschakelen..."
touch /etc/cloud/cloud-init.disabled

# 5. Logbestanden minimaliseren
echo "  - Logs legen..."
journalctl --vacuum-time=1s
find /var/log -type f -exec truncate -s 0 {} \;

# 6. GRUB Timeout verkorten (sneller booten)
echo "  - Boot-tijd verkorten..."
sed -i 's/GRUB_TIMEOUT=.[0-9]*/GRUB_TIMEOUT=1/' /etc/default/grub
update-grub

# 7. Schijfruimte vrijmaken (Zero-fill voor QCOW2 compressie)
echo "  - Vrije ruimte met nullen vullen (SDelete alternatief voor Linux)..."
dd if=/dev/zero of=/zero_file bs=1M status=progress
rm /zero_file

echo "--- Optimalisatie voltooid! ---"
echo "Je kunt de VM nu afsluiten en het QCOW2 image comprimeren."
