# unraid-plex-backup-script

An Unraid userscript to back up Plex data on a schedule with minimum downtime.

## Plex Container
If the Plex container `container_name` is running it will be stopped, if only an essential backup is being done it will be restarted once the data has been added to the archive, if a full backup is also being taken, the container will be restarted after the files/directories in the `stopped_backup_list` list have been added to the full backup archive.

## Compression
By default, this script will compress the created archive files, this is only done after the Plex container has been restarted so that the downtime is minimal.

## Configuration
- `source` the path of your "Plex Media Server" directory i.e. `/mnt/cache_system/appdata/binhex-plexpass/Plex Media Server`
- `stopped_backup_list` list of files/directories to include in a full backup (while plex is stopped)
- `started_backup_list` list of files/directories to include in a full backup (after plex has restarted, if applicable)
- `destination` the path to your backup directory.
  - "Essential" and "Full" directories will be created in this path so using a path ending with `/plex` is recommended
- `container_name` the name of the Plex docker container to be stopped
- `notify` (yes|no) Unraid notification that the backup was performed
- `delete_after` the number of days to keep essential backups
- `full_backup` (yes/no) creation of entire Plex backup (yes) or essential data only (no).
  - Yes will significantly increase the amount of time and size to create a backup as all metadata (potentially hundreds of thousands of files) is included in the backup.
- `force_full_backup` create a full backup every (#) number of days, in addition to regular essential data (0 to disable).
  - This will create an essential backup and then a full backup separately.
  - This setting is ignored if full_backup = yes
- `keep_full` the number of full backups to keep - these can be very large
- `compress_backup` (yes|no) compress the backups
  - this can take a long time but only happens after Plex has been restarted
