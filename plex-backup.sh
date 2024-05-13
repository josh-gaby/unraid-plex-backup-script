#!/bin/bash

# 	-- USER CONFIGURATION --	#

source="/mnt/cache_system/appdata/binhex-plexpass/Plex Media Server"      # path to your plex appdata location
stopped_backup_list=("Preferences.xml" "Plug-ins" "Plug-in Support")      # list of files/folders to include in a full backup (while plex is stopped)
started_backup_list=("Media" "Metadata")                                  # list of files/folders to include in a full backup (after plex has restarted, if applicable)
destination="/mnt/cache_backups/plex"                                     # path to your backup folder
container_name="binhex-plexpass"                                          # name of the docker container
notify=yes                                                                # (yes/no) Unraid notification that the backup was performed
delete_after=3                                                            # number of days to keep backups
full_backup=no                                                            # (yes/no) creation of entire Plex backup (yes) or essential data only (no)
                                                                          # Yes will significantly increase the amount of time and size to create a backup
                                                                          # as all metadata (potentially hundreds of thousands of files) is included in the backup.
force_full_backup=7                                                       # create a full backup every (#) number of days, in addition to regular essential data (0 to disable)
                                                                          # this will create an essential backup and then a full backup separately
                                                                          # this setting is ignored if full_backup = yes
keep_full=1                                                               # number of full backups to keep - these can be very large
compress_backup=yes                                                       # compress the backups - this can take a long time but only happens after Plex has been restarted

#	-- END USER CONFIGURATION --	#


#       DO NOT MODIFY BELOW THIS LINE
#-------------------------------------------------------------------------------------------------------

start=`date`	# start time of script for statistics
fail_counter=0
plex_down_start=0
plex_down_end=0
script_stopped_docker=false
dest=$(realpath -s $destination)
dt=$(date +"%Y-%m-%d")
cf=false
essential_backup_filename=false
full_backup_filename=false

function startPlexIfRequired {
  if [ "$script_stopped_docker" = "true" ]; then
    echo "\nRestarting the Plex container"
    docker start $container_name
    echo "\n"
    plex_down_end=`date +%s`
  fi
}

function fullBackup {
  echo -e  "\nCreating full backup... please wait\n"
  dest_dir="$dest/Full/$dt"
  mkdir -p "$dest_dir"

  # create an empty backup tar
  full_backup_filename="$dest_dir/Data_Backup-$dt-$(date +"%H%M").tar"
  tar -cf "$full_backup_filename" --files-from /dev/null

  # add only the files/folders that require plex to be stopped
  for source in "${stopped_backup_list[@]}"; do
    echo "  backing up $source"
    tar -rf "$full_backup_filename" "$source"
  done

  # restart the plex container (if we stopped it)
  startPlexIfRequired

  # add any files/folders that dont require plex to be stopped
  for source in "${started_backup_list[@]}"; do
    echo "  backing up $source"
    tar -rf "$full_backup_filename" "$source"
  done
  
  # save the date of the full backup
  echo "$start" > /boot/config/plugins/user.scripts/scripts/last_plex_backup

  echo "done"
}

# Get the state of the docker
plex_running=`docker inspect -f '{{.State.Running}}' $container_name`
if [ "$plex_running" = "true" ]; then
  echo "Stopping Plex"
  docker stop $container_name
  sleep 15
  # Get the state of the docker
  plex_running=`docker inspect -f '{{.State.Running}}' $container_name`
  while [ "$plex_running" = "true" ]; do
    fail_counter=$((fail_counter+1))
    echo "  attempt #$fail_counter"
    docker stop $container_name
    sleep 15
    plex_running=`docker inspect -f '{{.State.Running}}' $container_name`
    # Exit with an error code if the container won't stop
    # Restart plex and report a warning to the Unraid GUI
    if (($fail_counter == 5)); then
      echo "\nPlex failed to stop. Restarting container and exiting"
      docker start $container_name
      /usr/local/emhttp/webGui/scripts/notify -i warning -s "Plex Backup failed. Failed to stop container for backup."
      exit 1
    fi
  done
  plex_down_start=`date +%s`
  script_stopped_docker=true
fi

# Read timestamp of the last full backup, if any
if [ -f /boot/config/plugins/user.scripts/scripts/last_plex_backup ]; then
  while IFS= read -r line; do
    last_backup=$line
  done < /boot/config/plugins/user.scripts/scripts/last_plex_backup
else
  last_backup=0
fi

# create the backup directory if it doesn't exist - error handling - will not create backup file it path does not exist
mkdir -p "$dest"

cd "$source"

# create tar file of essential databases and preferences -- The Plug-in Support preferences will keep settings of any plug-ins, even though they will need to be reinstalled.
if [ $full_backup == no ]; then
  echo -e  "\n\nCreating essential backup... please wait"
  mkdir -p "$dest/Essential/$dt"
  essential_backup_filename="$dest/Essential/$dt/Data_Backup-$dt-$(date +"%H%M").tar"
  # backup only the essentials
  tar -cf "$essential_backup_filename" "Plug-in Support/Databases" "Plug-in Support/Preferences" Preferences.xml
  echo "done"
  
  if [ $force_full_backup != 0 ]; then
     # check how many days are between now and the last full backup run
    days=$(( ($(date --date="" +%s) - $(date --date=$(date --date="$last_backup" +%Y-%m-%d) +%s) )/(60*60*24) ))
    
    if [[ $days -ge $force_full_backup ]] || [[ $last_backup == 0 ]]; then
      cf=true
      fullBackup
    else
      echo -e "\nLast full backup created " $days " ago... skipping\n"
    fi
  fi
  if [[ $cf = false ]]; then
    # restart the plex container if we stopped it and it wasnt restarted during a forced full_backup
    startPlexIfRequired
  fi
else
  fullBackup
fi

sleep 2
chmod -R 777 "$dest"

# compress the backed up data if required
if [ $compress_backup == yes ]; then
  echo "\n\nCompressing... please wait"
  if [[ $essential_backup_filename != false ]]; then
    echo "Compressing the Essential backup, this may take a while..."
    gzip "$essential_backup_filename"
  fi
  if [[ $full_backup_filename != false ]]; then
    echo "Compressing the Full backup, this may take a while..."
    gzip "$full_backup_filename"
  fi
fi

echo -e  "\n\nRemoving Essential backups older than " $delete_after "days... please wait\n\n"
find $destination/Essential* -daystart -mtime +$delete_after -exec rm -rfd {} \;

old=$(( $force_full_backup*$keep_full ))
if [ -d "$destination/Full" ]; then
  echo -e  "Removing Full backups older than " $old "days... please wait\n\n\n"
  find $destination/Full* -daystart -mtime +$old -exec rm -rfd {} \;
fi

if [ $notify == yes ]; then
  if [ $full_backup == no ]; then
    if [ $cf = false ]; then
      /usr/local/emhttp/webGui/scripts/notify -e "Unraid Server Notice" -s "Plex Backup" -d "Essential Plex data has been backed up." -i "normal"
      echo -e  Essential backup: "$(du -sh $dest/Essential/$dt/)\n"
    else
      /usr/local/emhttp/webGui/scripts/notify -e "Unraid Server Notice" -s "Plex Backup" -d "Essential & Full Plex data has been backed up." -i "normal"
      echo -e  Essential backup: "$(du -sh $dest/Essential/$dt/)\n"
      echo -e  Full backup: "$(du -sh $dest/Full/$dt/)\n"
    fi
  else
    /usr/local/emhttp/webGui/scripts/notify -e "Unraid Server Notice" -s "Plex Backup" -d "Complete Plex data has been backed up." -i "normal"
    echo -e  Full backup: "$(du -sh $dest/Full/$dt/)\n"
  fi
fi

end=`date +%s`

echo -e  "\nTotal time for backup: " $((end - $(date --date="$start" +%s))) "seconds"

if [ "$script_stopped_docker" = "true" ]; then
  echo -e  "Plex was down for: " $((plex_down_end-plex_down_start)) "seconds"
fi

echo -e  '\n\nAll Done!\n'

if [ -d $dest/Essential/ ]; then
  echo -e  Total size of all Essential backups: "$(du -sh $dest/Essential/)"
fi

if [ -d $dest/Full/ ]; then
  echo -e  Total size of all Full backups: "$(du -sh $dest/Full/)"
fi

exit
