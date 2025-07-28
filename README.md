# Setting up percona on my kind cluster and testing backups
This repo contains all the information needed to run 2 **Percona Xtradb Clusters** on 2 different namespaces, `percona` & `percona-stage`.   
Performing a full backup of the first cluster `percona` and then restoring it into the second cluster `percona-stage`.  

## Goals
1. Fully functional MySQL database (pxc)
2. Fully functional backups using xtradb-backup
3. Restore the backed up DB onto a different cluster

## How
0. Setup the environment
   - Create a StorageClass that will serve the PVC of the backup
   - Optional: Set up MetalLB to access the DB outside the cluster
   - Get the percona-helm-chart
   - Install the percona-operator
     - Grant the operator full access to the pxc-db clusters' namespaces (RBAC)
   - 
1. Setup DB
   - Install the DB using helm-chart
   - Put some data into the db
2. Verify backups
   - Launch manual backup  
   - Delete all DB Data
   - Recover from backup
3. Replicate DB
   - Set up a replication
   - Create a secondery db schema in the pxc
   - Replicate all data from the main db to the secondary
   - Verify integrity 
4. Simulate a schema change in the db
   - With the replicated db, stop the replication
   - Update the secondary DB 
   - Migrate the update to the main DB 

# Creating the operator
>**_Note_**:  If you want to settle all the RBAC stuff using a custom `values.yaml` file, [see this](#pxc-operator-values) first
```bash
# Deploy the operator
helm install -n percona-operator percona-helm-charts/charts/pxc-operator --create-namespace
```
### Granting permissions to the operator 
#### Using RBAC
```bash
# Create cluster-wide ClusterRole for the operator
kubectl create -f cluster-role.yaml

# Grant access to the relevant namespaces
kubectl create -f role-binding.yaml -n percona-operator
kubectl create -f role-binding.yaml -n percona
kubectl create -f role-binding.yaml -n percona-stage

# Make the operator watch the namespaces of our pxc-dbs 
kubectl -n percona-operator edit deployment percona-operator-pxc-operator
# Change the WATCH_NAMESPACE env variable to "percona,percona-stage,percona-operator"

# Rollout the operator to apply the changes
kubectl rollout restart deployment percona-operator-pxc-operator -n percona-operator
```
#### <a name="pxc-operator-values"> Using a custom values file
>**_Note:_**:  This file watches the namespaces `percona` and `percona-stage`. Unless these are the namespaces you use, make sure to change those. 

I have included a file named [`pxc-operator-values.yaml`](pxc-operator-values.yaml) that already grants these permisisons. Copy this file into the `pxc-operator` chart and deploy using it to grant the permissions, then simply create the rolebindings
```bash
# Grant access to the relevant namespaces
kubectl create -f role-binding.yaml -n percona-operator
kubectl create -f role-binding.yaml -n percona
kubectl create -f role-binding.yaml -n percona-stage
```

# Setting up the Database
>_**Note:**_ my `values.yaml` file uses a `LoadBalancer` with an external IP to expose the **ProxySQL**, this could be problematic if you can't expose this IP on your environment. Please make sure to modify this accordingly.

I have included [`pxc-db-values.yaml`](pxc-db-values.yaml), this is the `values.yaml` I used when deploying my own **percona pxc-db** instance, it's modified to fit my `k3d` cluster and therefore also be lightweight.


```bash
# Create namespace
set -l NAMESPACE "percona"
set -l STAGE_NAMESPACE "percona-stager"

# Install percona
helm install percona-pxc-db -n $NAMESPACE percona-helm-charts/charts/pxc-db

# Install percona-stage 
helm install percona-pxc-db-stage -n $STAGE_NAMESPACE percona-helm-charts/charts/pxc-db
```