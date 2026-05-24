#!/bin/bash
echo "=== morphic logs tail ==="
docker logs --tail 40 morphic-stack-morphic-1 2>&1 | tail -40
echo
echo "=== morphic container stats ==="
docker stats --no-stream morphic-stack-morphic-1 morphic-stack-searxng-1
