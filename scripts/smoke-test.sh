#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${1:-http://localhost:5000}"

echo "Health:"
curl --fail --silent "$BASE_URL/health"
echo

echo "Readiness:"
curl --fail --silent "$BASE_URL/ready"
echo

echo "Application info:"
curl --fail --silent "$BASE_URL/api/info"
echo
