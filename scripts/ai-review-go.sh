#!/bin/bash

# Exit immediately on error
set -e

# Load .env safely
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# Validate
if [ -z "$OPENAI_API_KEY" ]; then
  echo "❌ OPENAI_API_KEY not set in environment"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "❌ 'jq' is not installed. Please install it (e.g., 'brew install jq')"
  exit 1
fi

# Collect staged Go files
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.go$')

if [ -z "$FILES" ]; then
  echo "✅ No Go files to review"
  exit 0
fi

# Combine content
CONTENT=""
for file in $FILES; do
  CODE=$(<"$file")
  CONTENT="${CONTENT}\n\nFile: ${file}\n${CODE}"
done

# Send to OpenAI
API_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/openai_response.json https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {
        "role": "system",
        "content": "You are a strict senior Go reviewer. Classify problems as:\n1. NEED TO FIX\n2. NEED TO FIX or TODO\n3. Just INFO.\nIf level 1 or 2, explain why. Use plain output, not markdown."
      },
      {
        "role": "user",
        "content": "'"$(echo -e "$CONTENT" | jq -Rs .)"'"
      }
    ],
    "temperature": 0.3
  }')

# Separate HTTP status code from output
HTTP_STATUS="${API_RESPONSE: -3}"

if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "❌ OpenAI API request failed with status $HTTP_STATUS"
  cat /tmp/openai_response.json
  exit 1
fi

RESPONSE=$(jq -r '.choices[0].message.content' /tmp/openai_response.json)

echo -e "\n🔍 AI Review Results:\n$RESPONSE"

# Block if level 1 or level 2 without // TODO or // CONFIRM
BLOCK=false
if echo "$RESPONSE" | grep -q "NEED TO FIX"; then
  echo -e "\n⛔ Commit blocked: Fix level 1 issues first."
  BLOCK=true
elif echo "$RESPONSE" | grep -q "NEED TO FIX or TODO"; then
  for file in $FILES; do
    if ! grep -Eq "// TODO|// CONFIRM" "$file"; then
      echo -e "\n⛔ Commit blocked: Level 2 but no TODO/CONFIRM comment."
      BLOCK=true
      break
    fi
  done
fi

if [ "$BLOCK" = true ]; then
  exit 1
fi

echo "✅ AI review passed."
exit 0
