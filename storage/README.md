# Set up an NFS server on your host
>**_Note_**: all the commands in this section, must be ran with root privileges
Before we start, we must install these packages in order to host an NFS share:
 - `nfs-kernel-server` - for Debian & Fedora 
 - `nfsutils`
 - `rpcbind`

In order to start the nfs-server correctly, first make sure this exists on `/etc/nfs.conf`:
```ini
[nfsd]
vers3=y
```
And then start the services 
```bash
 # Start the necessary services
systemctl enable --now rpcbind nfs-server
```
In order to start the nfs share, run this
```bash
# Append the exports of the NFS to /etc/exports
cat exports >> /etc/exports

# Make sure the shared dir exists 
mkdir -p /shares/nfs/kubernetes-stoarge

# Apply the changes
exportfs -rav
```

In order to verify that the share works. You can try and mount it locally
```bash
mount -t nfs 127.1:/shares/nfs/kubernetes-storage /mnt
```

# Add the NFS to Kubernetes
In order to make kubernetes aware that it can use this storage, simply apply the [StorageClass file](nfs-storage-class.yaml)
```bash 
kubectl create -f nfs-storage-class.yaml
```
