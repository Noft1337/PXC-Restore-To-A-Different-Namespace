# Backup & Restoration of PXC Databases
In this section, we're going to launch an on-demand **PXC-Backup** on the **pxc-db** that's ran inside the `percona-prod` namespace and then restore the data into the **pxc-db** that's ran in `percona-stage`

In this Section, I will use the variables set in [the root](..) of the project
---
# Backup
The backup name is set dynamically with
#### Bash
```bash
BACKUP_NAME="test-backup$(date +'%Y-%d-%m')"
```
#### Fish
```bash
set BACKUP_NAME "test-backup$(date +'%Y-%d-%m')"
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