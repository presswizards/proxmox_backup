#!/bin/bash
# ChatGPT created backup script for Rob @ PressWizards.com
# Backs up via vzdump each VM by ID to local /tmp/ folder,
# Then rclones to BackBlaze B2 or whatever config you set up,
# Then rsyncs it to remote server using SSH ID file to /root/proxmox_backups/ folder,
# Logs each step for each VM to /var/log/proxmox_backup.log,
# Keeps the last 3 days of local backkups, deletes older files,
# Keeps the last 7 remote rsync backups, and deletes the older files,
# Emails Error Report if errors occur (using msmtp preconfigured).
# Roadmap: Delete older than 7 days BackBlaze B2 files.

# 🔧 CONFIGURATION
HOSTNAME=$(hostname)
VM_IDS=(101 102 103 104)
#VM_IDS=(104) # Small one for testing
BACKUP_DIR="/var/proxmox_backups"
REMOTE_USER="root"
REMOTE_HOST="plesk.presswizards.com"
SSH_KEY="/root/.ssh/termiuskey.pem"
REMOTE_DIR="/var/proxmox_backups"
RCLONE_CONFIG="backblaze-b2"
RCLONE_BUCKET="proxmox-vms-remote"
LOG_FILE="/var/log/proxmox_backup.log"

EMAIL_ERRORS="support@presswizards.com"  # Email From address and To address that the logs are sent to only if there are errors
ERROR_SUBJECT="Proxmox Backup Script Error Report for $HOSTNAME"
ERROR_BODY="ALERT: Theproxmox_backup.sh script completed with errors.<br><br> Check the log for details:" # Sent using HTML so use <br> for line breaks
LOG_LINES_TO_SEND=20  # Number of recent lines to send in the email

KEEP_DAYS=7 # The number of remote rsync files to keep
KEEP_LOCAL_DAYS=3 # The number of local files to keep

umask 0177 # set permissions of files to 600 instead of 644

echo "🚀 Starting backups of VMs on $HOSTNAME at $(date)" | tee -a "$LOG_FILE"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Ensure backup and log directories exist
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"

ERRORS=0  # Track if there are errors during the backup

for VMID in "${VM_IDS[@]}"; do
    echo "🚀 [${VMID}] Starting backup of VM $VMID at $TIMESTAMP" | tee -a "$LOG_FILE"
    vzdump "$VMID" --compress zstd --dumpdir "$BACKUP_DIR"

    # Grab the latest backup file for this VM
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/vzdump-qemu-${VMID}-*.vma.zst | head -n 1)

    # Check if the backup file exists
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "❌ ERROR: [${VMID}] Backup file not found after vzdump!" | tee -a "$LOG_FILE"
        ((ERRORS++))
        continue
    fi

    if [[ -f "$BACKUP_FILE" ]]; then
        BACKUP_FILENAME=$(basename "$BACKUP_FILE")
        REMOTE_PATH="$REMOTE_DIR/$BACKUP_FILENAME"

        echo "✅ [${VMID}] Backup complete: $BACKUP_FILE" | tee -a "$LOG_FILE"

        echo "📡 [${VMID}] rclone to $RCLONE_CONFIG:RCLONE_BUCKET..." | tee -a "$LOG_FILE"
        # Upload the backup to BackBlaze B2 using rclone
        timeout 1h rclone copy "$BACKUP_FILE" "$RCLONE_CONFIG:$RCLONE_BUCKET/" --progress
        # Check if rclone upload was successful
        if [[ $? -eq 0 ]]; then
            echo "✅ [${VMID}] Backup uploaded to $RCLONE_CONFIG:RCLONE_BUCKET" >> "$LOG_FILE"
        else
            echo "❌ ERROR: [${VMID}] rclone upload failed." >> "$LOG_FILE"
            ((ERRORS++))
        fi

        echo "📡 [${VMID}] Rsync to $REMOTE_HOST..." | tee -a "$LOG_FILE"
        timeout 1h rsync --timeout=900 -a -e "ssh -i $SSH_KEY" "$BACKUP_FILE" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
        if [[ $? -eq 0 ]]; then
            echo "✅ [${VMID}] $TIMESTAMP Backup transferred to $REMOTE_PATH" | tee -a "$LOG_FILE"
        else
            echo "❌ ERROR: [${VMID}] $TIMESTAMP Rsync failed!" | tee -a "$LOG_FILE"
            ((ERRORS++))
        fi

        # Delete local backups older than 3 days
        echo "🧹 [${VMID}] Cleaning up local backups for VM $VMID on $REMOTE_HOST - keeping $KEEP_LOCAL_DAYS..." | tee -a "$LOG_FILE"
        find "$BACKUP_DIR" -type f -name "vzdump-qemu-${VMID}-*.vma.zst" -mtime +$((KEEP_LOCAL_DAYS + 1)) -exec rm -f {} \;

        # 🔄 Retention: Keep only the last 7 backups per VM on remote server
        echo "🧹 [${VMID}] backup complete. Cleaning up old backups for VM $VMID on $REMOTE_HOST - keeping $KEEP_DAYS..." | tee -a "$LOG_FILE"
        ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" \
            "cd $REMOTE_DIR && ls -t vzdump-qemu-${VMID}-*.vma.zst | tail -n +$((KEEP_DAYS + 1)) | xargs -r rm -f"
    else
        echo "❌ ERROR: [${VMID}] Backup file not found!" | tee -a "$LOG_FILE"
        ((ERRORS++))
    fi
done

echo "🎉 All backups completed at $(date) on $HOSTNAME" | tee -a "$LOG_FILE"

# If any errors occurred, send the last X lines from the main log file via email
if [[ $ERRORS -gt 0 ]]; then
    echo "📡 Sending Error Report email to $EMAIL_ERRORS" | tee -a "$LOG_FILE"
    echo -e "Subject: $ERROR_SUBJECT\nContent-Type: text/html; charset=UTF-8\n\n$ERROR_BODY<br><br>$(tail -n "$LOG_LINES_TO_SEND" "$LOG_FILE" | sed 's/$/<br>/')" | msmtp "$EMAIL_ERRORS"
fi
