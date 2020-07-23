# wp-env-sync

This script syncs the untracked files and database from the production server.
It assumes a few things...

1. You have ssh access between the local and remote machines and they both have WP CLI installed globally
2. You have added an additional-rsync-excludes.txt file to reflect any files and/or folders
   that you don't want synced from the remote for this specific environment
3. The .env file and, if applicable, the additional-rsync-excludes.txt file and sync-prod-ext.sh
   files are gitignored
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
      "cp ./vendor/reggieofarrell/wp-env-sync/rsync-excludes.txt ./",
      "cp ./vendor/reggieofarrell/wp-env-sync/sync-prod.sh ./"
   ],
   "post-update-cmd": [
      "cp ./vendor/reggieofarrell/wp-env-sync/rsync-excludes.txt ./",
      "cp ./vendor/reggieofarrell/wp-env-sync/sync-prod.sh ./"
   ]
}
```
then run...

`composer require reggieofarrell/wp-env-sync`

### Usage
1. Setup your .env file (see below)
2. Add any necessary additional rsync exclues not already in rsync-excludes.txt for 
   this environment to a file named additional-rsync-excludes.txt
3. Add any additional shell commands to run at the end of the script to a file name sync-prod-ext.sh
4. Run script (bash sync-prod.sh)

## .env file variables
You should have a `.env` file in the root of the wp project with all of these defined.  Values are just examples...

###### locaion of your ssh key for the remote server
`SSH_KEY_PATH=~/.ssh/id_rsa`
###### user@domain for the remote
`SSH_USER=someuser@1.1.1.1`
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
