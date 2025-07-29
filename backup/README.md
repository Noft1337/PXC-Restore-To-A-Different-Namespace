# Backup & Restoration of PXC Databases
In this section, we're going to launch an on-demand **PXC-Backup** on the **pxc-db** that's ran inside the `percona-prod` namespace and then restore the data into the **pxc-db** that's ran in `percona-stage`

In this Section, I will use the variables set in [the root](..) of the project
---
# <a name="backup"> Backup
The backup name is set dynamically with
#### Bash
```bash
BACKUP_NAME="test-backup$(date +'%Y-%d-%m')"
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
## Procedure
Here, I'm going to restore the backup I've done of `percona-prod`. This procedure is much more complex as Percona doesn't support restoring backups on different namespaces.  
The procedure is simply to move the pvc from the `percona-prod` namespace to the `percona-stage` namespace. A littel complicated but not impossible.

These are the steps that we need to do in order to be able to restore the backup on `percona-stage`:
  - Change the PV **ReclaimPolicy** to `Retain`
  - Remove the PVC from `percona-prod`
  - Create the PVC on `percona-stage`
  - Move the **PerconaXtradbClusterBackup** object to `percona-stage` 
  - Run the restoration process 
```bash
# Get all the required info
set VOLUME_NAME $(kubectl get -n "$PROD_NAMESPACE" "pvc/xb-$BACKUP_NAME" -o yaml | yq -r ".spec.volumeName")

# Change the ReclaimPolicy
kubectl patch pv $VOLUME_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

# Create the new PVC yaml
set NEW_PVC $(kubectl get -n "$PROD_NAMESPACE" "pvc/xb-$BACKUP_NAME" -o yaml | yq "{kind: .kind, apiVersion: .apiVersion, metadata: {name: .metadata.name}, spec: .spec}")

# Disable finalizers of the PVC
kubectl patch --type merge -n "$PROD_NAMESPACE" "pvc/xb-$BACKUP_NAME" -p '{"metadata": {"finalizers": []}}'
# Delete the original PVC
kubectl delete -n "$PROD_NAMESPACE" "pvc/xb-$BACKUP_NAME"

# Rereate the PVC on the new namespace
echo $NEW_PVC | kubectl create -n $STAGE_NAMESPACE -f -

# Patch again the PV to not be claimed by old PVC
kubectl patch pv $VOLUME_NAME -p $(printf '{"spec":{"claimRef": {"namespace": "%s", "uid": null}}}' $STAGE_NAMESPACE)

# Patch the PerconaXtradbClusterBackup namespace (i.e move it to the new namespace)
# Save the pxc-backup object
set NEW_PXC_BACKUP $(kubectl get -n "$PROD_NAMESPACE" pxc-backup $BACKUP_NAME -o yaml | yq "{apiVersion: .apiVersion, kind: .kind, metadata: {name: .metadata.name, namespace: \"$STAGE_NAMESPACE\", finalizers: .metadata.finalizers}, spec: .spec}")

# Delete the current pxc-backup 
kubectl delete -n "$PROD_NAMESPACE" pxc-backup $BACKUP_NAME

# Recreate it on the new namespace
echo $NEW_PXC_BACKUP | kubectl create -n $STAGE_NAMESPACE -f -

# Restore the backup 
yq "
.metadata.name = \"$BACKUP_NAME-restoration\" |
.spec.pxcCluster = \"$STAGE_REL_NAME\" |
.spec.backupName = \"$BACKUP_NAME\"
" restore.yaml | kubectl apply -n "$STAGE_NAMESPACE" -f - 
```