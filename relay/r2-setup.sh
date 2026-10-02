#!/bin/sh
# Creates the voice-reply bucket and its 7-day expiry rule (idempotent enough: errors on "already exists" are fine).
set -e
cd "$(dirname "$0")"
npx wrangler r2 bucket create herald-relay-audio || true
npx wrangler r2 bucket lifecycle add herald-relay-audio expire-audio-7d "" --expire-days 7 -y || true
