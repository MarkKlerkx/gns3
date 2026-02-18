#!/bin/bash

# --- CONFIGURATIE ---
CONFIG_FILE="/home/gns3/.gns3_student_email"
LOG_FILE="/var/log/gns3_disk_monitor.log"
VERSION="1.2.0"

echo "--- Start Opschonen GNS3 VM voor CloudStack Template (v$VERSION) ---"

# 1. Monitor Script herstellen
echo "[1/6] Monitor script config en logs verwijderen..."
[ -f "$CONFIG_FILE" ] && sudo rm -f "$CONFIG_FILE"
[ -f "$LOG_FILE" ] && sudo truncate -s 0 "$LOG_FILE"
# Reset de MOTD naar een standaard melding
echo "GNS3 VM - Student Edition v$VERSION" | sudo tee /etc/motd

# 2. Systeem logs leegmaken
echo "[2/6] Systeem logs opschonen..."
sudo find /var/log -type f -exec truncate -s 0 {} \;

# 3. Tijdelijke bestanden wissen
echo "[3/6] Tijdelijke mappen legen..."
sudo rm -rf /tmp/* /var/tmp/*

# 4. SSH-identiteit wissen (belangrijk voor unieke VM's!)
echo "[4/6] SSH Host Keys en historie wissen..."
sudo rm -f /etc/ssh/ssh_host_*
rm -rf ~/.ssh/*
rm -f ~/.bash_history

# 5. Schijf optimalisatie (vrije ruimte 'nullen' voor betere compressie)
echo "[5/6] Schijf optimaliseren (vrije ruimte nullen)..."
echo "Dit kan even duren..."
sudo dd if=/dev/zero of=/EMPTY bs=1M status=progress
sudo rm -f /EMPTY

# 6. Bash historie van huidige sessie wissen
echo "[6/6] Laatste sporen wissen..."
history -c

echo "--- VM is nu SCHOON. Schakel de VM nu uit via 'sudo poweroff' ---"
