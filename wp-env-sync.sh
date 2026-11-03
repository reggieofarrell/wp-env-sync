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
# 3. You may optionally add an additional-rsync-excludes-local.txt or additional-rsync-excludes-staging.txt to the wp-env-sync directory
#    to reflect any files and/or folders that you don't want synced from the remote for this specific environment
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
#   --slow : pauses 2 seconds on some commands to show output
#
#

# Abort on failed commands and pipelines so a failed import or security hook can
# never be followed by a misleading success message or maintenance deactivation.
# Unset-variable checking is intentionally omitted for existing optional settings.
set -eo pipefail

if [ -f ".env.wpenvsync" ]
then echo "Starting sync script..."
else echo "Error: .env.wpenvsync file not found, exiting..."; exit 1
fi

START=$(date +%s)

# import variables from .env.wpenvsync file
set -o allexport
source .env.wpenvsync
set +o allexport

if [[ $SSH_USER == "example@1.1.1.1" ]]
then echo "Error: you forgot to change the variables in the .env.wpenvsync file from the example values"; exit 1
fi

# bail if not on staging or local
if [[ $LOCAL_ENV != "staging" ]] && [[ $LOCAL_ENV != "local" ]]
then echo "Error: 'LOCAL_ENV' set in .env.wpenvsync is not staging or local"; exit 1
fi

SKIP_DB_SYNC="no"
SKIP_PERMS="no"
SKIP_RSYNC="no"
SLOW_MODE="no"

# Report failures without printing the command or environment, either of which
# may contain site credentials. Failures leave the native maintenance marker
# untouched, so WordPress can still apply its normal expiry on local/staging.
function _sync_exit() {
    local status=$?
    if [[ $status -ne 0 ]]; then
        echo "Sync failed; maintenance was not explicitly deactivated. WordPress's normal timeout still applies." >&2
    fi
    return "$status"
}
trap _sync_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Execute optional project hooks in a fresh Bash process. Enabling errexit and
# pipefail in that process makes an early failing command fail the entire hook.
# Hooks inherit the existing .env.wpenvsync exports and the DB lifecycle markers.
function _run_hook() {
    local hook="wp-env-sync/$1"
    if [[ -f "$hook" ]]; then
        echo "executing $hook..."
        bash -eo pipefail "$hook"
    fi
}

function _usage()
{
###### U S A G E : Help ######
cat <<EOF
Usage: bash wp-env-sync.sh <[options]>
Options:
    -d   --no-db-sync       Skip database synchronization
    -f   --no-file-sync     Skip file synchronization
    -h   --help             Show this message
    -p   --no-perms         Skip file permission normalization
    -s   --slow             Pause briefly between operations
EOF
exit
}

# parse options
# https://stackoverflow.com/questions/402377/using-getopts-to-process-long-and-short-command-line-options#answer-12523979
while getopts ':dfhps-' OPTION ; do
  case "$OPTION" in
    d ) SKIP_DB_SYNC=yes               ;;
    f ) SKIP_RSYNC=yes                 ;;
    h ) _usage                         ;;
    p ) SKIP_PERMS=yes                 ;;
    s ) SLOW_MODE=yes                  ;;
    - ) [ $OPTIND -ge 1 ] && optind=$(expr $OPTIND - 1 ) || optind=$OPTIND
        eval OPTION="\$$optind"
        OPTARG=$(echo $OPTION | cut -d'=' -f2)
        OPTION=$(echo $OPTION | cut -d'=' -f1)
        case $OPTION in
            --no-db-sync        ) SKIP_DB_SYNC=yes               ;;
            --no-file-sync      ) SKIP_RSYNC=yes                 ;;
            --no-perms          ) SKIP_PERMS=yes                 ;;
            --slow              ) SLOW_MODE=yes                  ;;
            --help              ) _usage                         ;;
            * )  "invalid option $OPTION" exit                   ;;
        esac
        OPTIND=1
        shift
        ;;
    ? )  "invalid option $OPTION" exit 1 ;;
  esac
done

# MULTISITE is normally undefined on single-site installs. Test its existence
# explicitly so that this expected case does not trip the failure guard.
IS_MULTISITE=0
if wp config has MULTISITE --quiet; then
    IS_MULTISITE=$(wp config get MULTISITE)
fi

# These markers are controlled by this process, rather than accepted from a
# caller, so database-only hooks cannot mistake a file-only run for an import.
export WP_ENV_SYNC_DB_IMPORTED=no
export WP_ENV_SYNC_DB_SYNC=yes
if [[ $SKIP_DB_SYNC == "yes" ]]; then
    export WP_ENV_SYNC_DB_SYNC=no
fi

echo "SKIP_DB_SYNC=$SKIP_DB_SYNC"
echo "SKIP_RSYNC=$SKIP_RSYNC"
echo "SKIP_PERMS=$SKIP_PERMS"
echo "SLOW_MODE=$SLOW_MODE"
echo "IS_MULTISITE=$IS_MULTISITE"

if [[ $SLOW_MODE == "yes" ]]; then sleep 2; fi

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
if [[ -f "./additional-rsync-excludes-local-override.txt" && $LOCAL_ENV == "local" ]]; then
    RSYNC_EXCLUDES="./additional-rsync-excludes-local-override.txt"
fi

# Only pass --exclude-from when a file exists; an empty value makes rsync fail with
# "rsync: open: : No such file or directory"
RSYNC_EXCLUDE_FROM_ARGS=()
if [[ -n "$RSYNC_EXCLUDES" ]]; then
    RSYNC_EXCLUDE_FROM_ARGS=(--exclude-from="$RSYNC_EXCLUDES")
    echo "using additional rsync excludes from $RSYNC_EXCLUDES"
else
    echo "no additional rsync excludes file found, using built-in excludes only"
fi

if [[ $SLOW_MODE == "yes" ]]; then sleep 2; fi

PORT="22"

if [[ $SSH_PORT != "" ]]; then
PORT="$SSH_PORT"
fi

echo "using ssh port $PORT"

if [[ $SLOW_MODE == "yes" ]]; then sleep 2; fi

echo "checking ssh connection..."
ssh -p $PORT -i $SSH_KEY_PATH -q -o BatchMode=yes -o ConnectTimeout=5 $SSH_USER 'exit 0'

if [[ $? != "0" ]]; then
    echo "SSH connection failed :("
    exit 1
else
    echo "Success!"
fi

if [[ $SLOW_MODE == "yes" ]]; then sleep 2; fi

echo "activating wp maintenance mode..."
wp maintenance-mode activate --force

# multiline inline comment trick below from...
# https://stackoverflow.com/questions/9522631/how-to-put-a-line-comment-for-a-multi-line-command/12797512#12797512

if [[ $SKIP_RSYNC == "no" ]]; then
    echo "Syncing files from production..."
    rsync --progress "${RSYNC_EXCLUDE_FROM_ARGS[@]}" \
    --exclude '/wp-env-sync/' ${comment# wp-env-sync} \
    --exclude '/wp-env-sync.sh' ${comment# wp-env-sync} \
    --exclude '/sync-prod.sh' ${comment# wp-env-sync} \
    --exclude '/sync-prod-ext.sh' ${comment# wp-env-sync} \
    --exclude '/sync-prod-ext-local.sh' ${comment# wp-env-sync} \
    --exclude '/sync-prod-ext-staging.sh' ${comment# wp-env-sync} \
    --exclude '/sync-stage.sh' ${comment# wp-env-sync} \
    --exclude '/sync-stage-ext.sh' ${comment# wp-env-sync} \
    --exclude '/rsync-excludes.txt' ${comment# wp-env-sync} \
    --exclude '/additional-rsync-excludes.txt' ${comment# wp-env-sync} \
    --exclude '/additional-rsync-excludes-local.txt' ${comment# wp-env-sync} \
    --exclude '/additional-rsync-excludes-staging.txt' ${comment# wp-env-sync} \
    --exclude '/additional-rsync-excludes-local-override.txt' ${comment# wp-env-sync} \
    --exclude '/deploy-scripts/' ${comment# GitHub webhook deploys} \
    --exclude '/deployscripts/' ${comment# GitHub webhook deploys} \
    --exclude '/gitdeploy.php' ${comment# GitHub webhook deploys} \
    --exclude '/git-deploy.php' ${comment# GitHub webhook deploys} \
    --exclude '/local-xdebuginfo.php' ${comment# Local WP} \
    --exclude 'nexcess-mapps' ${comment# Nexcess Hosting} \
    --exclude 'nexcess-mapps.php' ${comment# Nexcess Hosting} \
    --exclude 'wp-content/fatal-error-handler.php' ${comment# Nexcess Hosting} \
    --exclude '/cache/' ${comment# general web hosting} \
    --exclude '/cgi-bin/' ${comment# general web hosting} \
    --exclude '/.htaccess' ${comment# general web hosting} \
    --exclude '/.htaccess~' ${comment# general web hosting} \
    --exclude '/.htpasswd' ${comment# general web hosting} \
    --exclude '/.well-known/' ${comment# general web hosting} \
    --exclude '/.git' ${comment# git} \
    --exclude '/.gitignore' ${comment# git} \
    --exclude '/.github' ${comment# git} \
    --exclude '/README.md' ${comment# git} \
    --exclude '/robots.txt' \
    --exclude 'wp-content/object-cache.php' ${comment# wp} \
    --exclude 'wp-content/advanced-cache.php' ${comment# wp} \
    --exclude 'wp-content/db.php' ${comment# wp} \
    --exclude 'wp-content/uploads/wp-migrate-db/' ${comment# wp} \
    --exclude 'wp-content/db.php' ${comment# wp} \
    --exclude 'wp-content/cache/' ${comment# wp} \
    --exclude 'wp-config.php' ${comment# wp} \
    --exclude 'wp-content/et-cache/' ${comment# Divi} \
    --exclude 'ShortpixelBackups' ${comment# ShortPixel} \
    --exclude '*.log' \
    --exclude '/.env' \
    --exclude '/.env.development' \
    --exclude '/.env.production' \
    --exclude '/.env.wpenvsync' \
    --exclude '/composer.json' \
    --exclude '/composer.lock' \
    --exclude '/vendor' \
    --exclude '/wp-cli.yml' \
    --exclude '.maintenance' \
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
    if [[ -z "$WP_DB_EXPORT_ARGS" ]]; then
        echo "Exporting and compressing DB on remote..."
    else
        echo "Exporting and compressing DB on remote with additional arguments: $WP_DB_EXPORT_ARGS ..."
    fi
    ssh -i $SSH_KEY_PATH $SSH_USER -p $PORT /bin/bash << EOF
    # Fail inside the remote shell too; a successful gzip must not mask a failed export.
    set -e
    wp db export ${REMOTE_ENV}_db_${START}.sql --path=$REMOTE_PATH ${WP_DB_EXPORT_ARGS}
    gzip -v ${REMOTE_ENV}_db_${START}.sql
EOF

    echo "Copying DB from remote..."
    scp -i $SSH_KEY_PATH -P $PORT $SSH_USER:~/${REMOTE_ENV}_db_${START}.sql.gz ./${REMOTE_ENV}_db_${START}.sql.gz
    echo "Decompressing..."
    gunzip ./${REMOTE_ENV}_db_${START}.sql.gz

    echo "Deleting prod db export on remote..."
    ssh -i $SSH_KEY_PATH -p $PORT $SSH_USER /bin/bash << EOF
    rm ./${REMOTE_ENV}_db_${START}.sql.gz
EOF

    if [ $LOCAL_ENV = 'local' ]; then
        echo "Backing up the database..."
        wp db export ./_db.sql
    fi

    _run_hook before-db-import.sh

    echo "Flushing object cache..."
    wp cache flush

    echo "Clearing the database..."
    wp db reset --yes

    # fix for remote environments on mysql 8.0 with local environment on 5.7 (or MariaDB)
    if [[ $LOCAL_MYSQL_VER == "5.7" && $REMOTE_MYSQL_VER == "8.0" ]]; then
        echo "Reformatting MySQL 8.0 db export for MySQL 5.7..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # OSX
            sed -i '' -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' ${REMOTE_ENV}_db_${START}.sql
        else
            # Linux
            sed -i -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' ${REMOTE_ENV}_db_${START}.sql
        fi
    fi

    echo "Importing production database..."
    wp db import ./${REMOTE_ENV}_db_${START}.sql
    export WP_ENV_SYNC_DB_IMPORTED=yes

    # Renew the guard before any plugin-specific repair hook starts, even if an
    # external import command removed the marker during database replacement.
    wp maintenance-mode activate --force

    # Imported secrets must be repaired before URL/path rewriting or any ordinary
    # post-sync operations. This hook never runs on failed imports or --no-db-sync.
    # A nonzero result stops the sync without disabling the native maintenance
    # marker; WordPress's ordinary timeout remains in effect.
    _run_hook after-db-import.sh

    echo "Deleting prod db download..."
    rm ./${REMOTE_ENV}_db_${START}.sql

    if [[ -f "wp-env-sync/db-search-replace.sh" ]]; then
        # This is here to support multi-site since our generic
        # search-replace method doesn't work on multisite.
        # A custom one will need to be written in this case
        _run_hook db-search-replace.sh
    else
        echo "Running search-replace on url's..."
        wp search-replace //$REMOTE_DOMAIN //$LOCAL_DOMAIN --all-tables  --skip-columns=guid --precise

        echo "Running search-replace on files paths..."
        wp search-replace $FULL_REMOTE_PATH $PWD --all-tables  --skip-columns=guid --precise

        if [ $REMOTE_ENV_IS_HTTPS = true ] && [ $LOCAL_ENV_IS_HTTPS = false ]; then
        # make sure all https domain references are changed to http
        echo "Changing https references to http..."
        wp search-replace https://$LOCAL_DOMAIN http://$LOCAL_DOMAIN --all-tables  --skip-columns=guid --precise
        fi
    fi

fi # END db sync

if [[ $IS_MULTISITE == 1 ]]; then
    echo "flushing multisite caches and rewrite rules..."
    wp cache flush
    wp site list --field=url | xargs -n1 -I % wp --url=% rewrite flush
    rm -rf ./wp-content/cache

    echo "clearing multisite transients..."
    wp transient delete --all --network && wp site list --field=url | xargs -n1 -I % wp --url=% transient delete --all

    echo "discourage search engines from indexing multisite..."
    wp site list --field=url | xargs -n1 -I % wp --url=% option update blog_public 0
else
    echo "flushing caches and rewrite rules..."
    wp cache flush
    wp rewrite flush
    rm -rf ./wp-content/cache

    echo "clearing transients..."
    wp transient delete --all

    echo "discourage search engines from indexing..."
    wp option update blog_public 0
fi # END is_multisite

if [[ -f "wp-env-sync/sync-prod-ext-staging.sh" && $LOCAL_ENV == "staging" ]]; then
    _run_hook sync-prod-ext-staging.sh
fi

if [[ -f "wp-env-sync/sync-prod-ext-local.sh" && $LOCAL_ENV == "local" ]]; then
    _run_hook sync-prod-ext-local.sh
fi

# backwards compatibility with older script versions
if [[ -f "wp-env-sync/sync-prod-ext.sh" ]]; then
    _run_hook sync-prod-ext.sh
fi

echo "deactivating wp maintenance mode..."
wp maintenance-mode deactivate

END=$(date +%s)
DIFF=$(( $END - $START ))
echo ""
echo "Sync completed in $DIFF seconds"

if [ $LOCAL_ENV = 'local' ]; then
    echo ""
    echo "** If all went well, you can delete the _db.sql backup file. **"
    echo ""
fi
