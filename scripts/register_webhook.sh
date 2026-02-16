#!/usr/bin/env bash
# register_webhook.sh — Register the Cloud Run URL as the Telegram webhook
# Usage: ./scripts/register_webhook.sh
#        TELEGRAM_BOT_TOKEN must be set in the environment

set -euo pipefail

# Resolve the service URL from Terraform output (must be run from repo root or terraform dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "ERROR: TELEGRAM_BOT_TOKEN is not set."
  echo "  Export it before running: export TELEGRAM_BOT_TOKEN=<your-token>"
  exit 1
fi

echo "Reading service URL from Terraform outputs..."
SERVICE_URL=$(cd "${TERRAFORM_DIR}" && terraform output -raw service_url)

if [[ -z "${SERVICE_URL}" ]]; then
  echo "ERROR: Could not read service_url from terraform output."
  echo "  Make sure you have run 'terraform apply' first."
  exit 1
fi

WEBHOOK_URL="${SERVICE_URL}/telegram/webhook"

echo "Registering webhook..."
echo "  Bot token: ${TELEGRAM_BOT_TOKEN:0:10}..."
echo "  Webhook URL: ${WEBHOOK_URL}"
echo ""

RESPONSE=$(curl -s \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  --data-urlencode "url=${WEBHOOK_URL}" \
  --data-urlencode "allowed_updates=[\"message\",\"callback_query\"]")

echo "Response from Telegram:"
echo "${RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "${RESPONSE}"

# Check if registration succeeded
if echo "${RESPONSE}" | grep -q '"ok":true'; then
  echo ""
  echo "Webhook registered successfully!"
  echo ""
  echo "To verify:"
  echo "  curl \"https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/getWebhookInfo\" | python3 -m json.tool"
else
  echo ""
  echo "ERROR: Webhook registration failed. Check the response above."
  exit 1
fi
