#!/bin/bash
# Called by Terraform external data source.
# Reads JSON from stdin: { "bucket": "...", "prefix": "...", "fallback": "..." }
# Returns JSON: { "key": "..." }
set -u

QUERY=$(cat)
BUCKET=$(echo "$QUERY" | jq -r '.bucket')
PREFIX=$(echo "$QUERY" | jq -r '.prefix')
FALLBACK=$(echo "$QUERY" | jq -r '.fallback')

OBJECTS_JSON=$(aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "$PREFIX" \
  --output json 2>/dev/null || true)

KEY=$(echo "$OBJECTS_JSON" | jq -r '(.Contents // []) | sort_by(.LastModified) | last | .Key // empty' 2>/dev/null || true)

if [ -z "$KEY" ]; then
  KEY="$FALLBACK"
fi

jq -n --arg key "$KEY" '{"key": $key}'
