#!/bin/bash

# Pad voor backupfolder
BACKUP_DIR="/gns-backup"

# Check of de folder bestaat, anders aanmaken
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo "Backup directory aangemaakt: $BACKUP_DIR"
fi

# Scriptbestand voor de backup
BACKUP_SCRIPT="/usr/local/bin/gns3_backup.sh"

# Maak het daadwerkelijke backupscript
cat << 'EOF' > $BACKUP_SCRIPT
#!/bin/bash

SRC_DIR="/opt/gns3/projects"
DEST_DIR="/gns-backup"
NOW=$(date +"%Y%m%d-%H%M%S")

# Vind alle *.gns3 bestanden en kopieer ze
find "$SRC_DIR" -type f -name "*.gns3" | while read FILE; do
    BASENAME=$(basename "$FILE" .gns3)
    cp "$FILE" "$DEST_DIR/${BASENAME}_$NOW.gns3"
done

# Verwijder bestanden ouder dan 5 dagen
find "$DEST_DIR" -type f -name "*.gns3" -mtime +5 -exec rm {} \;
EOF

# Zorg dat het script uitvoerbaar is
chmod +x $BACKUP_SCRIPT

# Cronjob toevoegen (ieder uur)
# Eerst checken of er niet al een regel staat
(crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT"; echo "0 * * * * $BACKUP_SCRIPT") | crontab -

echo "Backupscript en cronjob ingesteld."
