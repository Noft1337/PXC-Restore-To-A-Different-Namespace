# Backup & Restoration of PXC Databases
In this section, we're going to launch an on-demand **PXC-Backup** on the **pxc-db** that's ran inside the `percona-prod` namespace and then restore the data into the **pxc-db** that's ran in `percona-stage`

In this Section, I will use the variables set in [the root](..) of the project
---
# <a name="backup"> Backup
The backup name is set dynamically with
#### Bash
```bash
BACKUP_NAME="backup-test-$(date +'%Y-%m-%d')"
```
#### Fish
```bash
set BACKUP_NAME "backup-test-$(date +'%Y-%m-%d')"
```
## Procedure
Here, I'm going to backup the db on the `percona-prod` namespace.  
The Backup Procedure is a fairly simple process, all you need to do is to apply the `backup.yaml` file and let the magic happen.
```bash
yq "
.metadata.name = \"$BACKUP_NAME\" |
.spec.pxcCluster = \"$PROD_REL_NAME\"
" backup.yaml | kubectl apply -n "$PROD_NAMESPACE" -f - 
```
---
# Restoration
I will be using the `BACKUP_NAME` set in the [Backup](#backup) section
### Procedure
Here, I'm going to restore the backup I've done of `percona-prod`. Percona doesn't support restoring backups on different namespaces natively. **BUT**, it supports specifying a `backupSource` to restore from a storage which is super helpful and makes this process a piece of cake!   
```bash
yq '.metadata.name = "'"$BACKUP_NAME"'-restoration" | 
.spec.pxcCluster = "'"$STAGE_REL_NAME"'" | 
.spec.backupSource.destination = "pvc/xb-'"$BACKUP_NAME"'" | 
.spec.backupSource.storageName = "fs-pvc"' restore.yaml | kubectl create -n $STAGE_NAMESPACE -f -
```