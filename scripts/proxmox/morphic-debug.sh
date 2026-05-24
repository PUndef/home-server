#!/bin/bash
echo "=== morphic container logs (last 80) ==="
docker logs --tail 80 morphic-stack-morphic-1 2>&1 | tail -80
echo
echo === direct chat-completion test to phoneserver ===
curl -sS -m 30 -X POST http://192.168.1.116:8080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"qwen2.5-3b","messages":[{"role":"user","content":"Say hi in one short sentence."}],"max_tokens":40}' | head -c 800
echo
