#!/bin/bash
echo "=== researcher config (env + maxSteps + tools) ==="
grep -RiEn 'maxSteps|process.env|RESEARCHER|FAST_MODEL|TOOL_MODEL|QUICK_MODE|tools.*\[' /opt/morphic/lib/researcher/ /opt/morphic/lib/agents/ 2>/dev/null | head -60
echo
echo "=== process.env references that might control behavior ==="
grep -RnE 'process\.env\.' /opt/morphic/lib/ /opt/morphic/app/ 2>/dev/null | grep -iE 'search|max|step|fetch|tool|research' | head -40
