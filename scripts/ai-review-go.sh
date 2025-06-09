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

GO_MOD_CONTENT=$(<go.mod)

JSON_PAYLOAD=$(jq -n \
  --arg gomod "$GO_MOD_CONTENT" \
  --arg content "$CONTENT" \
  '{
    model: "gpt-3.5-turbo",
    temperature: 0.3,
    messages: [
      {
        role: "system",
        content: "You are a strict senior Go reviewer. The project uses Go modules, so imports should use full module paths, not relative imports. Classify problems as:\n1. NEED TO FIX\n2. NEED TO FIX or TODO\n3. Just INFO.\nIf level 1 or 2, explain why. Use plain output, not markdown."
      },
      {
        role: "user",
        content: $content
      }
    ]
  }')

API_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/openai_response.json https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD")

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
  BLOCKED=false

  # Extract import paths from AI response
  IMPORTS_TO_FIX=$(echo "$RESPONSE" | grep "NEED TO FIX" | grep -oE '"[^"]+"' | tr -d '"')

  for file in $FILES; do
    while IFS= read -r line; do
      for path in $IMPORTS_TO_FIX; do
        if [[ "$line" == *"$path"* ]] && [[ "$line" != *"// CONFIRM"* ]]; then
          echo -e "\n⛔ Commit blocked in $file: \"$line\" needs fixing or explicit // CONFIRM."
          BLOCKED=true
        fi
      done
    done < "$file"
  done

  if [ "$BLOCKED" = true ]; then
    exit 1
  fi
fi


echo "✅ AI review passed."
exit 0
