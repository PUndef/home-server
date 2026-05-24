#!/bin/bash
echo "=== env vars hinting at search/context ==="
grep -iE 'max_context|search|chunk|fetch|tavily|exa|firecrawl|max_tokens|searxng|researcher|tools|maxstep' /opt/morphic/.env.local.example | head -80
echo
echo "=== current .env.local ==="
cat /opt/morphic/.env.local
echo
echo "=== researcher config ==="
grep -RiEn 'maxStep|maxResults|max_results|MAX_CONTEXT|chunkSize|SEARCH_FETCH' /opt/morphic/config/ /opt/morphic/lib/ 2>/dev/null | head -30
