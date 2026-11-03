# wp-env-sync

This script syncs the files and database from the production site/server of a Wordpress install to a local or staging copy.
It assumes a few things...

1. You have ssh access between the local/staging and remote machines and they both have WP CLI installed globally
2. You may optionally add an additional-rsync-excludes.txt or (additional-rsync-excludes-staging.txt or additional-rsync-excludes-local.txt) file to reflect any files and/or folders that you don't want synced from the remote for this specific environment
3. The .env.wpenvsync, and if applicable additional-rsync-excludes-local-override.txt, files are gitignored
4. If using composer, your composer.json file is in the wp root

## __Migration from 2.x__
If you are migrating from v2.x to v3.x.  A few important breaking changes have been made...

1. The main script has been renamed from `sync-prod.sh` to `wp-env-sync.sh`
2. All other files aside from the main script and the `.env.wpenvsync` file now belong in a `wp-env-sync` folder which should be in the same location at the `wp-env-sync.sh` and `.env.wpenvsync` files... the Wordpress root directory

## __Migration from 3.x__

When upgrading from v3.x to v4.x, review existing hooks before updating each
project. Version 4 changes failure handling in both the main script and hook
processes, so a hook that completed under v3 may now stop the sync.

### Command and hook failures

The main script enables `set -e` and `pipefail`, and all shell hooks run with
`bash -eo pipefail`. This includes existing `before-db-import.sh`,
`db-search-replace.sh`, `sync-prod-ext-local.sh`, `sync-prod-ext-staging.sh`, and
legacy `sync-prod-ext.sh` hooks, as well as the new `after-db-import.sh` hook.
The remote database export shell also stops when export fails.

- Unhandled command failures can stop a hook before its remaining commands run.
- A failed command inside a pipeline can fail the pipeline even when its final
  command succeeds.
- A nonzero hook exit stops the main sync instead of allowing later operations
  to continue.

Review optional commands, standalone checks such as `grep` with no matches, and
pipelines whose producers may exit early. Express expected conditions with `if`
or explicitly handle their exit statuses. Bash's normal conditional exceptions
to `-e` still apply; these options do not guarantee that every failure is caught.

Completed operations are not automatically rolled back. A failed import may leave
an incomplete destination database, and a later hook failure may occur after the
new database has already been imported.

### Maintenance and verification

Maintenance uses WordPress's ordinary marker and normal ten-minute expiry.
Successful runs explicitly deactivate maintenance. Failed or interrupted runs
leave that standard marker to expire normally; v4 does not make maintenance
persist indefinitely on local or staging destinations. Inspect the failure and
the destination database before retrying a failed sync.

The lifecycle tests use command fakes without connecting to WordPress, a database,
or a remote server:

```sh
bash tests/database-hooks.sh
```

## __Install (if using composer)__
add these things to your composer.json file...

```json
"repositories": [
  {
    "type": "vcs",
    "url": "git@github.com:reggieofarrell/wp-env-sync.git"
  }
],
"scripts": {
  "post-install-cmd": [
    "cp ./vendor/reggieofarrell/wp-env-sync/wp-env-sync.sh ./",
    "if [ ! -d ./wp-env-sync ]; then cp -r ./vendor/reggieofarrell/wp-env-sync/wp-env-sync/ ./wp-env-sync; fi;"
  ],
  "post-update-cmd": [
    "cp ./vendor/reggieofarrell/wp-env-sync/wp-env-sync.sh ./",
    "if [ ! -d ./wp-env-sync ]; then cp -r ./vendor/reggieofarrell/wp-env-sync/wp-env-sync/ ./wp-env-sync; fi;"
  ]
}
```
then run...

`composer require reggieofarrell/wp-env-sync`

## __Usage__
1. Setup your `.env.wpenvsync` file (see below) in the WP root directory
2. In a `wp-env-sync` directory within the WP root directory...
   - Add any necessary additional rsync exclues not already in `wp-env-sync.sh` for this environment (typically files or folders for your WP project that are in version control) to a file named `additional-rsync-excludes.txt` or (`additional-rsync-excludes-staging.txt` or `additional-rsync-excludes-local.txt` if you need different excludes per environment) depending on the environment type
   - If you're running wp multisite, the default search-replace command that we run will not work properly. In this case you'll need to add your own `db-search-replace.sh` file in the `wp-env-sync` directory. If this file is detected, the commands in that file will be run instead of the default search-replace commands
   - Add any additional shell commands to run at the end of the script to a file name `sync-prod-ext-local.sh` or `sync-prod-ext-staging.sh` depending on the environment type
3. Run script (`bash wp-env-sync.sh`)
4. You may want to create your own script that calls `wp-env-sync.sh` with the correct options for your use case already added.

### __options__

`-d --no-db-sync` :: skips the step of syncing the database from the remove environment

`-f --no-file-sync` :: skips the step of syncing the files from the remote environment

`-p --no-perms` :: skips the step of tring to reset file permissions after the file sync

`-s --slow` :: pauses 2 seconds after some commands to show output

### __hooks__

There are a few places in the main script where it will look for specifically named `.sh` or `.txt` files in the `wp-env-sync` directory and execute them or include them if found...

Shell hooks inherit the exported `.env.wpenvsync` settings. The runner also exports:

- `WP_ENV_SYNC_DB_SYNC`: `yes` unless `--no-db-sync` was selected.
- `WP_ENV_SYNC_DB_IMPORTED`: initially `no`, then `yes` after import succeeds.

Post-sync extensions still run on file-only syncs; use these flags when an
extension requires a newly imported database.

#### `additional-rsync-excludes.txt`

- [all environments] specify additional excludes for the file sync operation. See the rsync manual on `--exclude-from=FILE` for syntax

#### `additional-rsync-excludes-staging.txt`

- [staging only] specify additional excludes for the file sync operation. See the rsync manual on `--exclude-from=FILE` for syntax

#### `additional-rsync-excludes-local.txt`

- [local only] specify additional excludes for the file sync operation. See the rsync manual on `--exclude-from=FILE` for syntax

#### `sync-prod-ext-staging.sh`

- [staging only] script to be run at the end of the main `wp-env-sync` script

#### `sync-prod-ext-local.sh`

- [local only] script to be run at the end of the main `wp-env-sync` script

#### `before-db-import.sh`

- [all environments] script to be run just before the db is cleared and production is imported

#### `after-db-import.sh`

- [all environments, database sync only] runs after a successful database import and before URL/path search-replace or post-sync extensions. Skipped when the import fails or `--no-db-sync` is selected.

#### `db-search-replace.sh`

- [all environments] script to be run instead of the standard db search-replace commands. useful for multisite where the standard commands don't do the trick

### __.env file variables__
You should have a `.env.wpenvsync` file in the root of the wp project with all of these defined.  Values are just examples...

```bash
# locaion of your ssh key for the remote server
SSH_KEY_PATH=~/.ssh/id_rsa
# user@domain for the remote
SSH_USER=someuser@1.1.1.1
# ssh port on the remote server (typically 22)
SSH_PORT=22
# is this site env running on https?
LOCAL_ENV_IS_HTTPS=false
# your local domain for this site
LOCAL_DOMAIN=example.com
# is the remote site env running on https?
REMOTE_ENV_IS_HTTPS=true
# remote wordpress site domain
REMOTE_DOMAIN=anothersite.com
# relative remote path of wp from remote home folder (no leading slash)
REMOTE_PATH=files
# full path to the install on the remote server
FULL_REMOTE_PATH=/sites/example.com/files
# remote env name (prod, staging, etc..) for db file naming purposes
REMOTE_ENV=prod
# local env being synced to ['local', 'staging']
LOCAL_ENV=local
# local mysql version
LOCAL_MYSQL_VER=5.7
# remote mysql version
REMOTE_MYSQL_VER=8.0
# optional - additional options to pass to wp db export
# https://developer.wordpress.org/cli/commands/db/export/
WP_DB_EXPORT_ARGS=
```
