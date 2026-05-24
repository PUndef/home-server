#!/bin/bash
# Trim Morphic researcher down to be usable on a 3B-on-ARM LLM:
#  - maxSteps 20 -> 3 (cap the tool-call loop)
#  - drop the `fetch` tool (only use search snippets, no full HTML pull)
#  - cap max_results 20 -> 5 (less prompt bloat from search)
set -e

cd /opt/morphic

# 1) researcher.ts: maxSteps 20 -> 3, drop fetch from quick-mode tools
sed -i "s/maxSteps = 20/maxSteps = 3/" lib/agents/researcher.ts
sed -i "s|activeToolsList = \['search', 'fetch'\]|activeToolsList = ['search']|" lib/agents/researcher.ts
sed -i "s|'\[Researcher\] Quick mode: maxSteps=20, tools=\[search, fetch\]'|'[Researcher] Quick mode (trimmed): maxSteps=3, tools=[search]'|" lib/agents/researcher.ts

# also adaptive mode
sed -i "s/maxSteps = 50/maxSteps = 5/" lib/agents/researcher.ts
sed -i "s|activeToolsList = \['search', 'fetch', 'todoWrite'\]|activeToolsList = ['search']|" lib/agents/researcher.ts

# 2) search.ts: lower default max_results
sed -i "s/max_results = 20/max_results = 5/" lib/tools/search.ts
sed -i "s/effectiveMaxResults || minResults/effectiveMaxResults/" lib/tools/search.ts || true

echo "=== diff of researcher.ts ==="
grep -nE "maxSteps|activeToolsList|Quick mode|Adaptive mode" lib/agents/researcher.ts | head
echo "=== diff of search.ts ==="
grep -nE "max_results" lib/tools/search.ts | head

echo
echo "=== rebuild morphic only ==="
docker compose build morphic 2>&1 | tail -8

echo
echo "=== restart morphic ==="
docker compose up -d morphic
sleep 5
docker logs --tail 10 morphic-stack-morphic-1 2>&1 | tail -10
