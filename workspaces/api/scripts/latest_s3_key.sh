#!/bin/bash
# Called by Terraform external data source.
# Reads JSON from stdin: { "bucket": "...", "prefix": "...", "fallback": "..." }
# Returns JSON: { "key": "..." }
set -e

QUERY=$(cat)
BUCKET=$(echo "$QUERY" | jq -r '.bucket')
PREFIX=$(echo "$QUERY" | jq -r '.prefix')
FALLBACK=$(echo "$QUERY" | jq -r '.fallback')

KEY=$(aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "$PREFIX" \
  --query 'sort_by(Contents, &LastModified)[-1].Key' \
  --output text 2>/dev/null)

if [ -z "$KEY" ] || [ "$KEY" = "None" ]; then
  KEY="$FALLBACK"
fi

jq -n --arg key "$KEY" '{"key": $key}'
