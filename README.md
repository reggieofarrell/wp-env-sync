# wp-env-sync

This script syncs the files and database from the production site/server of a Wordpress install to a local or staging copy.
It assumes a few things...

1. You have ssh access between the local/staging and remote machines and they both have WP CLI installed globally
2. You have added an additional-rsync-excludes.txt or (additional-rsync-excludes-staging.txt or additional-rsync-excludes-local.txt) file to reflect any files and/or folders that you don't want synced from the remote for this specific environment
3. The .env.wpenvsync, and if applicable additional-rsync-excludes-local-override.txt, files are gitignored
4. If using composer, your composer.json file is in the wp root

## __Migration from 2.x__
If you are migrating from v2.x to v3.x.  A few important breaking changes have been made...

1. The main script has been renamed from `sync-prod.sh` to `wp-env-sync.sh`
2. All other files aside from the main script and the `.env.wpenvsync` file now belong in a `wp-env-sync` folder which should be in the same location at the `wp-env-sync.sh` and `.env.wpenvsync` files... the Wordpress root directory

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
    "if [ ! -f ./wp-env-sync/ ]; then cp -r ./vendor/reggieofarrell/wp-env-sync/wp-env-sync/ ./wp-env-sync; fi;"
  ],
  "post-update-cmd": [
    "cp ./vendor/reggieofarrell/wp-env-sync/wp-env-sync.sh ./",
    "if [ ! -f ./wp-env-sync/ ]; then cp -r ./vendor/reggieofarrell/wp-env-sync/wp-env-sync/ ./wp-env-sync; fi;"
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
   - Add any additional shell commands to run at the end of the script to a file name `wp-env-sync-ext-local.sh` or`wp-env-sync-ext-staging.sh` depending on the environment type
3. Run script (`bash wp-env-sync.sh`)
4. You may want to create your own script that calls `wp-env-sync.sh` with the correct options for your use case already added.

### __options__

`-d --no-db-sync` :: skips the step of syncing the database from the remove environment

`-f --no-file-sync` :: skips the step of syncing the files from the remote environment

`-p --no-perms` :: skips the step of tring to reset file permissions after the file sync

`-s --slow` :: pauses 2 seconds after some commands to show output

### __hooks__
There are a few places in the main script where it will look for specifically named `.sh` or `.txt` files in the `wp-env-sync` directory and execute them or include them if found...

#### `additional-rsync-excludes.txt`
- [all environments] specify additional excludes for the file sync operation. See the rsync manual on `--exclude-from=FILE` for syntax
#### `additional-rsync-excludes-staging.txt`
- [staging only] specify additional excludes for the file sync operation. See the rsync manual on `--exclude-from=FILE` for syntax
#### `additional-rsync-excludes-local.txt`
- [local only] specify additional excludes for the file sync operation. See the rsync manual on `--exclude-from=FILE` for syntax
#### `wp-env-sync-ext-staging.sh`
- [staging only] script to be run at the end of the main `wp-env-sync` script
#### `wp-env-sync-ext-local.sh`
- [local only] script to be run at the end of the main `wp-env-sync` script
#### `before-db-import.sh`
- [all environments] script to be run just before the db is cleared and production is imported
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
# local mysql version (choose 5.7 if running MariaDB)
LOCAL_MYSQL_VER=5.7
# remote mysql version
REMOTE_MYSQL_VER=8.0
# LocalWP db socket path in case wp db commands are complaining about not being able to connect this can be used to execute mysql commands
DB_SOCKET=
```
