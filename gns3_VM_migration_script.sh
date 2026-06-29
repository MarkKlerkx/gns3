#!/bin/bash

# --- CONFIGURATION ---
OLD_SERVER="10.1.51.10"
SSH_USER="gns3" # Change this to 'fontysadmin' or 'root' if that is your SSH user

echo "================================================================="
echo " Starting GNS3 data migration from ${OLD_SERVER}"
echo "================================================================="

# 1. Stop the local GNS3 service to prevent database corruption
echo "--> Temporarily stopping local GNS3 service..."
sudo systemctl stop gns3-server 2>/dev/null

# 2. Synchronize the images directory
echo "--> Copying /opt/gns3/images..."
sudo rsync -avzP --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r ${SSH_USER}@${OLD_SERVER}:/opt/gns3/images/ /opt/gns3/images/

# 3. Synchronize the symbols directory
echo "--> Copying /opt/gns3/symbols..."
sudo rsync -avzP --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r ${SSH_USER}@${OLD_SERVER}:/opt/gns3/symbols/ /opt/gns3/symbols/

# 4. Synchronize GNS3 settings and templates
echo "--> Copying GNS3 configurations and templates..."
# Ensuring the destination path exists first
mkdir -p /home/gns3/.config/GNS3/2.2/
rsync -avzP ${SSH_USER}@${OLD_SERVER}:/home/gns3/.config/GNS3/2.2/ /home/gns3/.config/GNS3/2.2/

# 5. Restore correct permissions on the new server
echo "--> Adjusting ownership and permissions for the 'gns3' user..."
sudo chown -R gns3:gns3 /opt/gns3/images
sudo chown -R gns3:gns3 /opt/gns3/symbols
sudo chown -R gns3:gns3 /home/gns3/.config/GNS3

# 6. Restart the GNS3 Service
echo "--> Restarting GNS3 service..."
sudo systemctl start gns3-server 2>/dev/null

echo "================================================================="
echo " Migration completed successfully! Please check your GNS3 GUI."
echo "================================================================="
