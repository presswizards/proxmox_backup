# proxmox_backup
A fairly simple script to vmdump your VMs by ID, and rsync them to a remote server, and rclone them to BackBlaze or other rclone compatible config.


<p/>
<a href="https://www.buymeacoffee.com/robwpdev" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="41" width="174"></a><br>
If this code saves you time, helps your clients, or helps you do better work, I’d appreciate it.
</p>

ChatGPT created backup script for Rob @ PressWizards.com

- Backs up via vzdump each VM by ID to local /tmp/ folder,
- Then rclones to BackBlaze B2 or whatever config you set up,
- Then rsyncs it to remote server using SSH ID file to /root/proxmox_backups/ folder,
- Logs each step for each VM to /var/log/proxmox_backup.log,
- Keeps the last 3 days of local backkups, deletes older files,
- Keeps the last 7 remote rsync backups, and deletes the older files,
- Emails Error Report if errors occur (using msmtp preconfigured).
- Roadmap: Delete older than 7 days BackBlaze B2 files.

See the Configuration variables and change them as needed.

Note:
- uses rsync via SSH ID file
- uses rclone preconfigured for your fav B2, S3 or other remote cloud
- Uses msmtp preconfigured for your fav SMTP provider


<p/>
<a href="https://www.buymeacoffee.com/robwpdev" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="41" width="174"></a><br>
If this code saves you time, helps your clients, or helps you do better work, I’d appreciate it.
</p>
