# Set up an internal NAT network 
In this folder, are all the files needed in order to create the local NAT that will serve your cluster. This has been made simple with the help of a script I've written that does the following:
  - Create a bridge interface with IP
  - Config the required `iptables` rules to make it functional
  - Create a docker network that's associated with this interface
  - Connect all the k3d to the **docker-network**

In order to configure the script to your needs, the script has these variables that you can modify according to your needs.
```bash
PHYSICAL_IF="eth0"
BRIDGE_NAME="inet0"
IP_PREFIX="172.31.0"
IP_ADDR="1"
CIDR="16"
DOCKER_NET="host_inet"
```

# Set up MetalLB Address Pool 
First, [Install MetalLB](https://metallb.universe.tf/installation/).  
After installing, all that's left to do is to apply these files:
```bash
kubectl create -f metallb-ip-pool.yaml metallb-l2-config.yaml
```