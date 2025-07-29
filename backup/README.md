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
Here, I'm going to restore the backup I've done of `percona-prod`. Percona doesn't support restoring backups on different namespaces natively. **BUT**, it supports specifying a `backupSource` to restore from a storage which is super helpful and makes this process much easier.  

The only thing that's problematic is when the PVC is not accessible from the `percona-stage` cluster but we will take care of that. 
```bash
yq '.metadata.name = "'"$BACKUP_NAME"'-restoration" | 
.spec.pxcCluster = "'"$STAGE_REL_NAME"'" | 
.spec.backupSource.destination = "pvc/xb-'"$BACKUP_NAME"'" | 
.spec.backupSource.storageName = "fs-pvc"' restore.yaml | kubectl create -n $STAGE_NAMESPACE -f -
```

Now, incase your restoration pod is stuck on `Pending`, it usually will be because it can't access the PVC of the backup (which is located on `percona-prod`). This is how you transfer the **PVC** from `percona-prod` to `percona-stage`:
```bash 
# Get all the required info
set VOLUME_NAME $(kubectl get -n "$PROD_NAMESPACE" "pvc/xb-$BACKUP_NAME" -o yaml | yq -r ".spec.volumeName")

# Change the ReclaimPolicy
kubectl patch pv $VOLUME_NAME -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

# Create the new PVC yaml
set NEW_PVC $(kubectl get -n "$PROD_NAMESPACE" "pvc/xb-$BACKUP_NAME" -o yaml | yq "{kind: .kind, apiVersion: .apiVersion, metadata: {name: .metadata.name}, spec: .spec}")

# Delete the original PVC
kubectl delete -n "$PROD_NAMESPACE" "pvc/xb-$BACKUP_NAME" & 
# Disable finalizers of the PVC
kubectl patch --type merge -n "$PROD_NAMESPACE" "pvc/xb-$BACKUP_NAME" -p '{"metadata": {"finalizers": []}}'

# Rereate the PVC on the new namespace
echo $NEW_PVC | kubectl create -n $STAGE_NAMESPACE -f -

# Patch again the PV to not be claimed by old PVC
kubectl patch pv $VOLUME_NAME -p $(printf '{"spec":{"claimRef": {"namespace": "%s", "uid": null}}}' $STAGE_NAMESPACE)
```

After that your restoration process should start (it will be pending until your **PVC** will Bind successfully).