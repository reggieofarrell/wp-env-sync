# wp-env-sync

This script syncs the files and database from the production site/server of a Wordpress install to a local or staging copy.
It assumes a few things...

1. You have ssh access between the local/staging and remote machines and they both have WP CLI installed globally
2. You have added an additional-rsync-excludes.txt or (additional-rsync-excludes-staging.txt or additional-rsync-excludes-local.txt) file to reflect any files and/or folders that you don't want synced from the remote for this specific environment
3. The .env.wpenvsync, and if applicable additional-rsync-excludes-local-override.txt, files are gitignored
4. If using composer, your composer.json file is in the wp root

### Install (if using composer)
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
      "cp ./vendor/reggieofarrell/wp-env-sync/sync-prod.sh ./"
   ],
   "post-update-cmd": [
      "cp ./vendor/reggieofarrell/wp-env-sync/sync-prod.sh ./"
   ]
}
```
then run...

`composer require reggieofarrell/wp-env-sync`

### Usage
1. Setup your .env.wpenvsync file (see below)
2. Add any necessary additional rsync exclues not already in sync-prod.sh for this environment (typically files or folders for your WP project that are in version control) to a file named additional-rsync-excludes.txt or (additional-rsync-excludes-staging.txt or additional-rsync-excludes-local.txt if you need different excludes per environment) depending on the environment type
3. Add any additional shell commands to run at the end of the script to a file name sync-prod-ext-local.sh or sync-prod-ext-staging.sh depending on the environment type
4. Run script (bash sync-prod.sh)

## .env.wpenvsync file variables
You should have a `.env.wpenvsync` file in the root of the wp project with all of these defined.  Values are just examples...

###### locaion of your ssh key for the remote server
`SSH_KEY_PATH=~/.ssh/id_rsa`
###### user@domain for the remote
`SSH_USER=someuser@1.1.1.1`
###### ssh port on the remote server (typically 22)
`SSH_PORT=22`
###### is this site env running on https?
`LOCAL_ENV_IS_HTTPS=false`
###### your local domain for this site
`LOCAL_DOMAIN=example.com`
###### is the remote site env running on https?
`REMOTE_ENV_IS_HTTPS=true`
###### remote wordpress site domain
`REMOTE_DOMAIN=anothersite.com`
###### relative remote path of wp from remote home folder (no leading slash)
`REMOTE_PATH=files`
###### full path to the install on the remote server
`FULL_REMOTE_PATH=/sites/example.com/files`
###### remote env name (prod, staging, etc..) for db file naming purposes
`REMOTE_ENV=prod`
###### local env being synced to ['local', 'staging']
`LOCAL_ENV=local`
###### local mysql version
`LOCAL_MYSQL_VER=5.7`
###### remote mysql version
`REMOTE_MYSQL_VER=8.0`
