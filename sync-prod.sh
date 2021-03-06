#!/bin/bash
#
# WP Env Sync Script
# Author: Reggie O'Farrell | Casadega Development
#
# This script syncs the untracked files and database from the production server.
# It assumes a few things...
#
# 1. You have WP CLI installed globally on this machine
# 2. You have ssh access to the server and the server has WP CLI installed
# 3. You have added an additional-rsync-excludes.txt file to reflect any files and/or folders
#    that you don't want synced from the remote for this specific environment
# 4. The .env.wpenvsync file and, if applicable, the additional-rsync-excludes.txt file and sync-prod-ext.sh
#    files are gitignored
#
# Instructions:
# 1. Setup your .env.wpenvsync file
# 2. Add any necessary additional rsync exclues not already in rsync-excludes.txt for
#    this env to a file named additional-rsync-excludes.txt
# 3. Add any additional shell commands to run at the end of the script to a file name sync-prod-ext.sh
# 4. Run script (bash sync-prod.sh)
#
# Note: the --copy-links flag is used with rsync so that if there are any symlinks in the remote, those
#       files will be copied into an actual directory at the correct location.  No symlinks will be created locally
#

if [ -f ".env.wpenvsync" ]
then echo "Starting sync script..."
else echo "Error: .env.wpenvsync file not found, exiting..."; exit 1
fi

START=$(date +%s)

# import variables from .env.wpenvsync file
set -o allexport
source .env.wpenvsync
set +o allexport

# bail if not on staging or local
if [ $LOCAL_ENV != "staging" ] && [ $LOCAL_ENV != "local" ]
then echo "Error: environment is not staging or local"; exit 1
fi

if ! [ -f "additional-rsync-excludes.txt" ]
then touch additional-rsync-excludes.txt
fi

echo "Syncing files from production..."
rsync --progress --exclude-from='additional-rsync-excludes.txt' \
--exclude 'wp-content/uploads/wp-migrate-db/' \
--exclude 'wp-content/cache/' \
--exclude 'wp-content/et-cache/' \
--exclude '.git' \
--exclude '.gitignore' \
--exclude '.github' \
--exclude 'gitdeploy.php' \
--exclude 'ShortpixelBackups' \
--exclude 'wp-config.php' \
--exclude '.htaccess' \
--exclude '*.log' \
--exclude 'object-cache.php' \
--exclude 'advanced-cache.php' \
--exclude '.env' \
--exclude '.env.development' \
--exclude '.env.production' \
--exclude '.env.wpenvsync' \
--exclude 'sync-prod.sh' \
--exclude 'sync-prod-ext.sh' \
--exclude 'sync-stage.sh' \
--exclude 'sync-stage-ext.sh' \
--exclude 'rsync-excludes.txt' \
--exclude 'additional-rsync-excludes.txt' \
--exclude '/composer.json' \
--exclude '/composer.lock' \
--exclude '/vendor' \
--exclude 'wp-cli.yml' \
--delete --copy-links -avzhe "ssh -i $SSH_KEY_PATH" $SSH_USER:~/$REMOTE_PATH/ ./

if [ $LOCAL_ENV = "staging" ]
then
  echo "Ensuring permissions..."
  find ./ -type f -exec chmod 644 {} +
  find ./ -type d -exec chmod 755 {} +

  if [ -f "wp-config.php" ]
  then chmod 600 ./wp-config.php
  fi
fi

echo "Exporting and compressing DB on remote..."
ssh -i $SSH_KEY_PATH $SSH_USER /bin/bash << EOF
  wp db export ${REMOTE_ENV}_db_${START}.sql --path=$REMOTE_PATH
  gzip -v ${REMOTE_ENV}_db_${START}.sql
EOF

echo "Copying DB from remote..."
scp -i $SSH_KEY_PATH $SSH_USER:~/${REMOTE_ENV}_db_${START}.sql.gz ./${REMOTE_ENV}_db_${START}.sql.gz
echo "Decompressing..."
gunzip ./${REMOTE_ENV}_db_${START}.sql.gz

if [ $LOCAL_ENV = 'local' ]
then
echo "Backing up local db..."
wp db export ./_db.sql
fi

echo "Clearing local db..."
wp db reset --yes

# fix for remote environments on mysql 8.0 with local environment on 5.7
if [ $LOCAL_MYSQL_VER = 5.7 ] && [ $REMOTE_MYSQL_VER = 8.0 ]
then
  echo "Reformatting MySQL 8.0 db export for MySQL 5.7..."
  sed -i '' -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_520_ci/g' ${REMOTE_ENV}_db_${START}.sql
fi

echo "Importing DB to local..."
wp db import ./${REMOTE_ENV}_db_${START}.sql

echo "Running search-replace on url's..."
wp search-replace //$REMOTE_DOMAIN //$LOCAL_DOMAIN --all-tables  --skip-columns=guid --precise
wp search-replace $FULL_REMOTE_PATH $PWD --all-tables  --skip-columns=guid --precise

if [ $REMOTE_ENV_IS_HTTPS = true ] && [ $LOCAL_ENV_IS_HTTPS = false ]
then
# make sure all https domain references are changed to http
echo "Changing https references to http..."
wp search-replace https://$LOCAL_DOMAIN http://$LOCAL_DOMAIN --all-tables  --skip-columns=guid --precise
fi

echo "A little housekeeping..."
rm ./${REMOTE_ENV}_db_${START}.sql

ssh -i $SSH_KEY_PATH $SSH_USER /bin/bash << EOF
  rm ./${REMOTE_ENV}_db_${START}.sql.gz
EOF

echo "flushing caches and rewrite rules..."
wp cache flush
wp rewrite flush
rm -r ./wp-content/cache

echo "clearing transients"
wp transient delete --all

echo "discourage search engines from indexing"
wp option set blog_public 0

if [ -f "sync-prod-ext.sh" ]
then
echo "executing additional commands in sync-prod-ext.sh"
sh ./sync-prod-ext.sh
fi

END=$(date +%s)
DIFF=$(( $END - $START ))
echo ""
echo "Sync completed in $DIFF seconds"

if [ $LOCAL_ENV = 'local' ]
then
echo ""
echo "** If all went well, you can delete the _db.sql backup file. **"
echo ""
fi
