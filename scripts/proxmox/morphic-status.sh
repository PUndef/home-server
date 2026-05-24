#!/bin/bash
echo === containers ===
docker ps -a --format '{{.Names}}: {{.Status}} ({{.Ports}})'
echo
echo === images ===
docker images | head
echo
echo === build/run procs ===
ps -ef | grep -E 'docker|buildkit|next|node|bun' | grep -v grep | head
echo
echo === free ===
free -h
