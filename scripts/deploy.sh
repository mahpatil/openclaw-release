#!/usr/bin/env bash
# deploy.sh — Full deploy: enable APIs, terraform apply, register Telegram webhook
# Usage: ./scripts/deploy.sh <project-id>
#
# Prerequisites:
#   - gcloud CLI installed and authenticated (`gcloud auth login`)
#   - terraform CLI installed
#   - TELEGRAM_BOT_TOKEN exported in the environment
#   - terraform.tfvars configured (see .env.example for guidance)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# ── Args ──────────────────────────────────────
PROJECT_ID="${1:-}"
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Usage: $0 <project-id>"
  echo "  Example: $0 my-gcp-project-123"
  exit 1
fi

echo "=== OpenClaw Family Bot — Deploy ==="
echo "Project: ${PROJECT_ID}"
echo ""

# ── Set GCP project ───────────────────────────
gcloud config set project "${PROJECT_ID}"

# ── Enable required APIs ──────────────────────
echo "Enabling GCP APIs (this may take a minute)..."
gcloud services enable \
  run.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  --quiet

echo "APIs enabled."
echo ""

# ── Terraform ─────────────────────────────────
echo "Running Terraform..."
cd "${TERRAFORM_DIR}"

terraform init -upgrade

terraform apply -auto-approve \
  -var="project_id=${PROJECT_ID}"

echo ""
echo "Terraform apply complete."

# ── Show outputs ──────────────────────────────
SERVICE_URL=$(terraform output -raw service_url)
WEBHOOK_URL=$(terraform output -raw webhook_url)
MEMORY_BUCKET=$(terraform output -raw memory_bucket)

echo ""
echo "=== Deployment Summary ==="
echo "  Service URL:    ${SERVICE_URL}"
echo "  Webhook URL:    ${WEBHOOK_URL}"
echo "  Memory bucket:  gs://${MEMORY_BUCKET}/"
echo ""

# ── Register Telegram webhook ─────────────────
echo "Registering Telegram webhook..."
cd "${SCRIPT_DIR}"
"${SCRIPT_DIR}/register_webhook.sh"

echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "  1. Message your bot on Telegram — expect 2-5s cold start on first message"
echo "  2. Check logs: gcloud run logs read --service openclaw-family --region ${TERRAFORM_DIR}"
echo "  3. Browse memory: gsutil ls gs://${MEMORY_BUCKET}/"
echo ""
