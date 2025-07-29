# Percona Xtradb Cluster - POC
This repo contains all the information needed to run 2 **Percona Xtradb Clusters** on 2 different namespaces
- Namespace: `percona-prod`
Cluster: `pxc-db-prod`
- Namespace: `percona-stage`
Cluster: `pxc-db-stage`

Performing a full backup of the first cluster `pxc-db-prod` and then restoring it into the second cluster `pxc-db-stage`.  

## Goals
1. Fully functional MySQL database (pxc)
2. Fully functional backups using xtradb-backup
3. Restore the backed up DB onto a different cluster

## Steps
0. Setup the environment
   - Create a StorageClass that will serve the PVC of the backup
   - Optional: Set up MetalLB to access the DB outside the cluster
   - Get the percona-helm-chart
   - Install the percona-operator
   - Install 2 **pxc-db** clusters
1. Setup DB
   - Install the DB using helm-chart
   - Put some data into the db
2. Backup `prod`
   - Launch manual backup  
3. Restore into `stage`
   - Move the backup PVC from `percona-prod` to `percona-stage`
   - Run the restoration
---
# Setting up the environment
For my environment, I am using a local NAT network that will serve the host (that runs k3d), the nodes of k3d, and the cluster itself.  
The IPs are assigned to the pods that are running in the cluster using `MetalLB`.  
For the **PVCs**, I am using an **NFS** that's exported by my host and a `StorageClass` that accesses the share using the **nfs-csi**.
### Set it up yourself
  1. [Internal NAT & MetalLB](network/)
  2. [Storage - NFS](storage/)

# Setting up Percona
## Before we begin
I have included the [`create-k3d.sh`](create-k3d.sh) script that basically sets up a `k3d` cluster from scratch and installs all the needed prerequisites for the **Percona-Xtradb-Cluster** to run succesfully according to my needs & standards. If you want a deeper understanding of the process, feel free to coninute reading (or read the script) 
## Prequisites
These environment variables will be used for the different Percona Xtradb Clusters:
#### Bash Syntax
```bash
# Release Names
STAGE_REL_NAME="pxc-db-stage"
PROD_REL_NAME="pxc-db-prod"
OPERATOR_REL_NAME="pxc-operator"
# Namespaces
STAGE_NAMESPACE="percona-stage"
PROD_NAMESPACE="percona-prod"
OPERATOR_NAMESPACE="percona-operator"
```
#### Fish syntax
```bash
# Release Names
set -l STAGE_REL_NAME "pxc-db-stage"
set -l PROD_REL_NAME "pxc-db-prod"
set -l OPERATOR_REL_NAME "pxc-operator"
# Namespaces
set -l STAGE_NAMESPACE "percona-stage"
set -l PROD_NAMESPACE "percona-prod"
set -l OPERATOR_NAMESPACE "percona-operator"
```
#### Create the necessary namespaces
```bash
# Create the namespaces
kubectl create namespace "$STAGE_NAMESPACE" 
kubectl create namespace "$PROD_NAMESPACE"
kubectl create namespace "$OPERATOR_NAMESPACE"
```

Before we start, I suggest cloning the `percona-helm-charts` git repo to be able to modify the charts and then install them using `helm`
```bash
git clone git@github.com:percona/percona-helm-charts.git
```
---
## Creating the operator
>**_Note_**:  If you want to settle all the RBAC stuff using a custom `values.yaml` file, [see this](#pxc-operator-values) first
```bash
# Deploy the operator
helm install "$OPERATOR_REL_NAME" -n "$OPERATOR_NAMESPACE" percona-helm-charts/charts/pxc-operator
```
### Granting permissions to the operator 
#### **Creating ClusterRole**
```bash
# Create modified ClusterRole
yq ".metadata.name = \"$OPERATOR_REL_NAME\"" templates/cluster-role.yaml | kubectl create -f -

# Make the operator watch the namespaces of our pxc-dbs 
kubectl -n "$OPERATOR_NAMESPACE" edit deployment "$OPERATOR_REL_NAME"
# Change the WATCH_NAMESPACE env variable to ""$OPERATOR_NAMESPACE,$PROD_NAMESPACE,$STAGE_NAMESPACE""

# Rollout the operator to apply the changes
kubectl rollout restart deployment "$OPERATOR_REL_NAME" -n "$OPERATOR_NAMESPACE"
```
---
#### <a name="pxc-operator-values"> **Using a custom values file**
>**_Note:_**:  This file watches the namespaces `percona` and `percona-stage`. Unless these are the namespaces you use, make sure to change those. 

I have included a file named [`pxc-operator-values.yaml`](pxc-operator-values.yaml) that already grants these permisisons. Copy this file into the `pxc-operator` chart and deploy using it to grant the permissions, then simply create the rolebindings
--- 
### **Creating the RoleBinds** 
##### **Bash**
```bash
ns_list=("$OPERATOR_NAMESPACE" "$PROD_NAMESPACE" "$STAGE_NAMESPACE")
# Grant access to the relevant namespaces
for ns in "${ns_list[@]}"; do 
   yq "
   .metadata.name = \"$OPERATOR_REL_NAME\" |
   .metadata.namespace = \"$OPERATOR_NAMESPACE\" |
   .roleRef.name = \"$OPERATOR_REL_NAME\" |
   .subjects[0].name = \"$OPERATOR_REL_NAME\" |
   .subjects[0].namespace = \"$OPERATOR_NAMESPACE\"
   " templates/role-binding.yaml | kubectl create -f -n $ns - 
done
```
---
##### **Fish**
```bash
set ns_list "$OPERATOR_NAMESPACE" "$PROD_NAMESPACE" "$STAGE_NAMESPACE"
# Grant access to the relevant namespaces
for ns in $ns_list
   yq "
   .metadata.name = \"$OPERATOR_REL_NAME\" |
   .metadata.namespace = \"$OPERATOR_NAMESPACE\" |
   .roleRef.name = \"$OPERATOR_REL_NAME\" |
   .subjects[0].name = \"$OPERATOR_REL_NAME\" |
   .subjects[0].namespace = \"$OPERATOR_NAMESPACE\"
   " templates/role-binding.yaml | kubectl create -f -n $ns - 
end
```

## Setting up the Database
>_**Note:**_ my `values.yaml` file uses a `LoadBalancer` with an external IP to expose the **ProxySQL**, this could be problematic if you can't expose this IP on your environment. Please make sure to modify this accordingly.

I have included [`pxc-db-prod-values.yaml`](pxc-db-prod-values.yaml) & [`pxc-db-stage-values.yaml`](pxc-db-stage-values.yaml).  \
These are the `values.yaml` files I used to deploy both of the **percona pxc-db** instances, it's modified to fit my `k3d` cluster and therefore also be lightweight.

```bash
# Create namespace
# Install percona
helm install "$PROD_REL_NAME" -n "$PROD_NAMESPACE" percona-helm-charts/charts/pxc-db --values pxc-db-prod-values.yaml

# Install percona-stage 
helm install "$STAGE_REL_NAME" -n "$STAGE_NAMESPACE" percona-helm-charts/charts/pxc-db --values pxc-db-stage-values.yaml
```

### Test the DBs
Run these commands after the states of all the pods in both namespaces has turned into `Running`. If both commands result in a MySQL prompt, then the deployment has been successful
```bash
# Test percona-stage
set -l ROOT_STAGE_PASSWORD $(kubectl -n "$STAGE_NAMESPACE" get secrets "$STAGE_REL_NAME-secrets" -o jsonpath="{.data.root}" | base64 --decode)
kubectl -n "$STAGE_NAMESPACE" exec -ti "$STAGE_REL_NAME-pxc-0" -c pxc -- mysql -uroot -p"$ROOT_STAGE_PASSWORD"

# Test percona
set -l ROOT_PROD_PASSWORD $(kubectl -n "$PROD_NAMESPACE" get secrets "$PROD_REL_NAME-secrets" -o jsonpath="{.data.root}" | base64 --decode)
kubectl -n "$PROD_NAMESPACE" exec -ti "$PROD_REL_NAME-pxc-0" -c pxc -- mysql -uroot -p"$ROOT_PROD_PASSWORD"
```

## Add (test) data to the DB 
>**_Note_**: The `"$PERCONA_IP`" variable is the ip address that's set in the `proxysql.expose.loadBalancerIP` field inside `pxc-db/values.yaml` 

For this POC, I am using [test_db](https://github.com/datacharmer/test_db)'s test databases in order to put data in my DB. For this reason, I found it very convenient to set up external access to the **ProxySQL**, so I can use the `mysql` command in order to load the example database into my **pxc-db**. This is how its done using en external IP:
```bash 
set -l ROOT_PASSWORD $(kubectl -n percona get secrets percona-pxc-db-secrets -o jsonpath="{.data.root}" | base64 --decode)
mysql -h "$PERCONA_IP" -u root -p"$ROOT_PASSWORD" --skip-ssl < employees.sql
```

# Backup & Restore the DB
For the **Backup & Restore** section see [this section](backup/)


