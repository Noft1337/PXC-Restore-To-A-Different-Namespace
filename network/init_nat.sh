#!/bin/bash
set -euo pipefail

# ← Exit unless run as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root. Please re-run with sudo or as root."
  exit 1
fi

PHYSICAL_IF="eth0"
BRIDGE_NAME="inet0"
IP_PREFIX="172.31.0"
IP_ADDR="1"
CIDR="16"
DOCKER_NET="host_inet"

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1

# Create the bridge (ignore “already exists” errors)
ip link add name "${BRIDGE_NAME}" type bridge || true

# Disable IPv6 on the bridge
sysctl -w net.ipv6.conf."${BRIDGE_NAME}".disable_ipv6=1

# Assign it an IPv4 address
ip addr add "${IP_PREFIX}.${IP_ADDR}/${CIDR}" dev "${BRIDGE_NAME}"

# Bring the bridge up
ip link set dev "${BRIDGE_NAME}" up

# Masquerade outgoing IPv4 traffic from the subnet
iptables -t nat -A POSTROUTING -s "${IP_PREFIX}.0/${CIDR}" -o "${PHYSICAL_IF}" -j MASQUERADE

# Allow forwarding between bridge and physical interface
iptables -A FORWARD -i "${BRIDGE_NAME}" -o "${PHYSICAL_IF}" -j ACCEPT
iptables -A FORWARD -i "${PHYSICAL_IF}" -o "${BRIDGE_NAME}" -m state --state RELATED,ESTABLISHED -j ACCEPT

# Create (or reuse) a Docker network on that bridge
docker network create --subnet "${IP_PREFIX}.0/${CIDR}" --gateway "${IP_PREFIX}.${IP_ADDR}" -o "com.docker.network.bridge.name=${BRIDGE_NAME}" "${DOCKER_NET}" 2>/dev/null || true

# Connect all k3d containers to that network
mapfile -t CONTAINERS < <(docker ps -q --filter "name=k3d-")
i=2
for container in "${CONTAINERS[@]}"; do
  docker network connect --ip "${IP_PREFIX}.${i}" "${DOCKER_NET}" "${container}"
  i=$((i + 1))
done

