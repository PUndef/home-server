#!/bin/bash
# Install llama-server on phoneserver as an OpenRC service.
#   - listens on 0.0.0.0:8080 with OpenAI-compatible /v1 endpoints
#   - serves the Qwen2.5-3B-Instruct-Q4_K_M.gguf model
#   - supervised by openrc-run with auto-restart
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'set -e
echo "=== install init script ==="
sudo tee /etc/init.d/llama-server > /dev/null <<INIT
#!/sbin/openrc-run

name="llama-server"
description="llama.cpp HTTP server (OpenAI-compatible) serving Qwen2.5-3B"

command="/home/pmos/llama.cpp/build/bin/llama-server"
command_args="--host 0.0.0.0 --port 8080 --model /home/pmos/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf --ctx-size 4096 --threads 6 --n-predict -1 --jinja --alias qwen2.5-3b"
command_user="pmos:pmos"
command_background="yes"
pidfile="/run/llama-server.pid"
output_log="/var/log/llama-server.log"
error_log="/var/log/llama-server.log"

supervisor="supervise-daemon"
respawn_delay="5"
respawn_max="0"

depend() {
    need net
    after networking
}

start_pre() {
    checkpath --file --owner pmos:pmos --mode 0644 /var/log/llama-server.log
    export LD_LIBRARY_PATH=/home/pmos/llama.cpp/build/bin
}
INIT

sudo chmod 0755 /etc/init.d/llama-server
sudo rc-update add llama-server default
sudo rc-service llama-server start
sleep 8
echo
echo "=== service status ==="
sudo rc-service llama-server status
echo
echo "=== listening ports ==="
sudo ss -tln | grep -E ":8080|LISTEN"
echo
echo "=== api ping ==="
curl -sS -m 5 http://127.0.0.1:8080/health
echo
echo "=== /v1/models ==="
curl -sS -m 5 http://127.0.0.1:8080/v1/models'
