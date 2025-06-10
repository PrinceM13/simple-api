#!/bin/bash
set -e

echo "🔍 Running SonarQube Scanner..."

# Optional: Load .env with SONAR_TOKEN and SONAR_HOST_URL
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# Run SonarQube analysis
sonar-scanner \
  -Dsonar.projectKey=my-project-key \
  -Dsonar.sources=. \
  -Dsonar.host.url=$SONAR_HOST_URL \
  -Dsonar.login=$SONAR_TOKEN

echo "✅ SonarQube analysis passed."
