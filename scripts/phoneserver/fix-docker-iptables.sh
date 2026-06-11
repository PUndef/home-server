#!/bin/sh
# Docker on pmOS may fail NAT/bridge setup; host-network stacks work with iptables off.
set -eu
sudo mkdir -p /etc/docker
printf '%s\n' '{"iptables": false, "ip6tables": false}' | sudo tee /etc/docker/daemon.json >/dev/null
sudo modprobe br_netfilter 2>/dev/null || true
sudo rc-service docker restart
sleep 5
sudo docker ps
