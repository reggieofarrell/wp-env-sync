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
# 3. You have added an additional-rsync-excludes-local.txt or additional-rsync-excludes-staging.txt to the wp-env-sync directory
#    file to reflect any files and/or folders that you don't want synced from the remote for this specific environment
# 4. The .env.wpenvsync file and the additional-rsync-excludes-local.txt(if it exists) files files are gitignored
#
# Instructions:
# 1. Setup your .env.wpenvsync file
# 2. Add any necessary additional rsync exclues not already in this script for
#    this env to a file named additional-rsync-excludes-{$LOCAL_ENV}.txt
# 3. Add any additional shell commands to run at the end of the script to a file name sync-prod-ext-local.sh and sync-prod-ext-staging.sh
# 4. Run script (bash sync-prod.sh)
#
# Note: the --copy-links flag is used with rsync so that if there are any symlinks in the remote, those
#       files will be copied into an actual directory at the correct location.  No symlinks will be created locally
#
# Flags:
#   --no-file-sync : skips the file sync from the remote environment
#   --no-perms : skips the process of setting file permissions after the file sync
#   --no-db-sync : skips the syncing of the database from the remote environment
#
#

if [ -f ".env.wpenvsync" ]
then echo "Starting sync script..."
else echo "Error: .env.wpenvsync file not found, exiting..."; exit 1
fi

if [ "$SSH_USER" == "example@1.1.1.1" ]
then echo "Error: you forgot to change the variables in the .env.wpenvsync file from the example values"; exit 1
fi

START=$(date +%s)

# import variables from .env.wpenvsync file
set -o allexport
source .env.wpenvsync
set +o allexport

# bail if not on staging or local
if [ $LOCAL_ENV != "staging" ] && [ $LOCAL_ENV != "local" ]
then echo "Error: 'LOCAL_ENV' set in .env.wpenvsync is not staging or local"; exit 1
fi

SKIP_DB_SYNC="no"
SKIP_PERMS="no"
SKIP_RSYNC="no"

# set up flags
# https://stackoverflow.com/questions/402377/using-getopts-to-process-long-and-short-command-line-options#answer-768068
optspec=":-:"
while getopts "$optspec" optchar; do
  case "${optchar}" in
    -)
        case "${OPTARG}" in
            no-db-sync)
                SKIP_DB_SYNC="yes"; OPTIND=$(( $OPTIND + 1 ))
                # echo "Parsing option: '--${OPTARG}', value: '${SKIP_DB_SYNC}'" >&2;
                ;;
            no-perms)
                SKIP_PERMS="yes"; OPTIND=$(( $OPTIND + 1 ))
                # echo "Parsing option: '--${OPTARG}', value: '${SKIP_PERMS}'" >&2;
                ;;
            no-file-sync)
                SKIP_RSYNC="yes"; OPTIND=$(( $OPTIND + 1 ))
                # echo "Parsing option: '--${OPTARG}', value: '${SKIP_RSYNC}'" >&2;
                ;;
            # Left here as examples...
            # loglevel)
            #     val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
            #     echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
            #     ;;
            # loglevel=*)
            #     val=${OPTARG#*=}
            #     opt=${OPTARG%=$val}
            #     echo "Parsing option: '--${opt}', value: '${val}'" >&2
            #     ;;
            *)
                if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                    echo "Unknown option --${OPTARG}" >&2
                    exit 1
                fi
                ;;
        esac;;
    # h)
    #     echo "usage: $0 [-v] [--loglevel[=]<value>]" >&2
    #     exit 2
    #     ;;
    # v)
    #     echo "Parsing option: '-${optchar}'" >&2
    #     ;;
    *)
        if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
            echo "Non-option argument: '-${OPTARG}'" >&2
            exit 1
        fi
        ;;
    esac
done

RSYNC_EXCLUDES=""

# backwards compatibility (or no environment specific excludes necessary)
if [[ -f "wp-env-sync/additional-rsync-excludes.txt" ]]; then
RSYNC_EXCLUDES="./wp-env-sync/additional-rsync-excludes.txt"
fi

if [[ -f "wp-env-sync/additional-rsync-excludes-local.txt" && $LOCAL_ENV == "local" ]]; then
RSYNC_EXCLUDES="./wp-env-sync/additional-rsync-excludes-local.txt"
fi

if [[ -f "wp-env-sync/additional-rsync-excludes-staging.txt" && $LOCAL_ENV == "staging" ]]; then
RSYNC_EXCLUDES="./wp-env-sync/additional-rsync-excludes-staging.txt"
fi

# allow overriding additional-rsync-excludes-local.txt
if [[ -f "wp-env-sync/additional-rsync-excludes-local-override.txt" && $LOCAL_ENV == "local" ]]; then
RSYNC_EXCLUDES="./wp-env-sync/additional-rsync-excludes-local-override.txt"
fi

PORT="22"

if [[ $SSH_PORT != "" ]]; then
PORT="$SSH_PORT"
fi

echo "checking ssh connection..."
ssh -p $PORT -q -o BatchMode=yes -o ConnectTimeout=5 $SSH_USER exit

if [[ $? != "0" ]]; then
  echo "SSH connection failed"
  exit 1
fi

if [[ $SKIP_RSYNC == "no" ]]; then
    echo "Syncing files from production..."
    rsync --progress --exclude-from="$RSYNC_EXCLUDES" \
    --exclude '/wp-env-sync/' \
    --exclude '/wp-env-sync.sh' \
    --exclude '/sync-prod.sh' \
    --exclude '/sync-prod-ext.sh' \
    --exclude '/sync-prod-ext-local.sh' \
    --exclude '/sync-prod-ext-staging.sh' \
    --exclude '/sync-stage.sh' \
    --exclude '/sync-stage-ext.sh' \
    --exclude '/rsync-excludes.txt' \
    --exclude '/additional-rsync-excludes.txt' \
    --exclude '/additional-rsync-excludes-local.txt' \
    --exclude '/additional-rsync-excludes-staging.txt' \
    --exclude '/additional-rsync-excludes-local-override.txt' \
    --exclude '/.htaccess' \
    --exclude '/.git' \
    --exclude '/.gitignore' \
    --exclude '/.github' \
    --exclude '/gitdeploy.php' \
    --exclude '/README.md' \
    --exclude '/robots.txt' \
    --exclude '/cgi-bin/' \
    --exclude 'wp-content/object-cache.php' \
    --exclude 'wp-content/advanced-cache.php' \
    --exclude 'wp-content/uploads/wp-migrate-db/' \
    --exclude 'wp-content/db.php' \
    --exclude 'wp-content/fatal-error-handler.php' \
    --exclude 'wp-content/cache/' \
    --exclude 'wp-content/et-cache/' \
    --exclude 'ShortpixelBackups' \
    --exclude 'wp-config.php' \
    --exclude '*.log' \
    --exclude '/.env' \
    --exclude '/.env.development' \
    --exclude '/.env.production' \
    --exclude '/.env.wpenvsync' \
    --exclude '/composer.json' \
    --exclude '/composer.lock' \
    --exclude '/vendor' \
    --exclude '/wp-cli.yml' \
    --delete --copy-links -avzhe "ssh -i $SSH_KEY_PATH -p $PORT" $SSH_USER:~/$REMOTE_PATH/ ./

    if [[ $SKIP_PERMS == "no" ]]; then
        if [[ $LOCAL_ENV == "staging" ]]; then
            echo "Ensuring permissions..."
            find ./ -type f -exec chmod 644 {} +
            find ./ -type d -exec chmod 755 {} +

            if [[ -f "wp-config.php" ]]; then
                chmod 600 ./wp-config.php
            fi
        fi
    fi
fi # END File sync


if [[ $SKIP_DB_SYNC == "no" ]]; then

echo "Exporting and compressing DB on remote..."
ssh -i $SSH_KEY_PATH $SSH_USER -p $PORT /bin/bash << EOF
wp db export ${REMOTE_ENV}_db_${START}.sql --path=$REMOTE_PATH
gzip -v ${REMOTE_ENV}_db_${START}.sql
EOF

echo "Copying DB from remote..."
scp -i $SSH_KEY_PATH -P $PORT $SSH_USER:~/${REMOTE_ENV}_db_${START}.sql.gz ./${REMOTE_ENV}_db_${START}.sql.gz
echo "Decompressing..."
gunzip ./${REMOTE_ENV}_db_${START}.sql.gz

if [ $LOCAL_ENV = 'local' ]; then
echo "Backing up the database..."
wp db export ./_db.sql
fi

echo "Clearing the database..."
wp db reset --yes

# fix for remote environments on mysql 8.0 with local environment on 5.7 (or MariaDB)
if [[ $LOCAL_MYSQL_VER == "5.7" && $REMOTE_MYSQL_VER == "8.0" ]]; then
    echo "Reformatting MySQL 8.0 db export for MySQL 5.7..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # OSX
        sed -i '' -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_520_ci/g' ${REMOTE_ENV}_db_${START}.sql
    else
        # Linux
        sed -i -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_520_ci/g' ${REMOTE_ENV}_db_${START}.sql
    fi
fi

echo "Importing production database..."
wp db import ./${REMOTE_ENV}_db_${START}.sql

echo "Running search-replace on url's..."
wp search-replace //$REMOTE_DOMAIN //$LOCAL_DOMAIN --all-tables  --skip-columns=guid --precise

echo "Running search-replace on files paths..."
wp search-replace $FULL_REMOTE_PATH $PWD --all-tables  --skip-columns=guid --precise

if [ $REMOTE_ENV_IS_HTTPS = true ] && [ $LOCAL_ENV_IS_HTTPS = false ]; then
# make sure all https domain references are changed to http
echo "Changing https references to http..."
wp search-replace https://$LOCAL_DOMAIN http://$LOCAL_DOMAIN --all-tables  --skip-columns=guid --precise
fi

echo "A little housekeeping..."
rm ./${REMOTE_ENV}_db_${START}.sql

ssh -i $SSH_KEY_PATH -p $PORT $SSH_USER /bin/bash << EOF
rm ./${REMOTE_ENV}_db_${START}.sql.gz
EOF

fi # END db sync

echo "flushing caches and rewrite rules..."
wp cache flush
wp rewrite flush
rm -r ./wp-content/cache

echo "clearing transients..."
wp transient delete --all

echo "discourage search engines from indexing..."
wp option set blog_public 0

if [[ -f "wp-env-sync/sync-prod-ext-staging.sh" && $LOCAL_ENV == "staging" ]]; then
echo "executing additional commands in sync-prod-ext-staging.sh..."
bash ./wp-env-sync/sync-prod-ext-staging.sh
fi

if [[ -f "wp-env-sync/sync-prod-ext-local.sh" && $LOCAL_ENV == "local" ]]; then
echo "executing additional commands in sync-prod-ext-local.sh..."
bash ./wp-env-sync/sync-prod-ext-local.sh
fi

# backwards compatibility with older script versions
if [[ -f "wp-env-sync/sync-prod-ext.sh" ]]; then
echo "executing additional commands in sync-prod-ext.sh..."
bash ./wp-env-sync/sync-prod-ext.sh
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
