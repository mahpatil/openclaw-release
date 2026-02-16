# OpenClaw Gateway on GCP Cloud Run

Self-host the [alpine/openclaw](https://hub.docker.com/r/alpine/openclaw) WebSocket gateway on GCP Cloud Run, so you can connect Claude Code from anywhere using `/gateway connect`.

## Architecture

```
Claude Code (laptop/phone)
        │  wss://
        ▼
  Cloud Run (OpenClaw gateway)   ←── OPENCLAW_GATEWAY_TOKEN auth
        │
        ├── Groq / Gemini / Anthropic API  (LLM)
        └── GCS Bucket  (workspace persistence across restarts)
```

**Why Cloud Run:**

| | Self-hosted VM | Cloud Run |
|---|---|---|
| Cost idle | ~$5–10/mo | ~$0/mo (1 min-instance ≈ $2/mo) |
| HTTPS | Manual cert | Auto (managed) |
| Image updates | Manual | One command |
| Auth | DIY | Gateway token |

---

## Prerequisites

- GCP project with billing enabled
- [`gcloud` CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated (`gcloud auth login`)
- [`terraform`](https://developer.hashicorp.com/terraform/install) >= 1.0
- [Claude Code](https://claude.ai/claude-code) installed locally
- At least one LLM API key (see Phase 1 below)

---

## Setup

### Phase 1 — Get an LLM API Key (5 min)

| Provider | Sign-up | Free Tier |
|---|---|---|
| **Groq** | [console.groq.com](https://console.groq.com) | 6 000 tokens/min, Llama 3.3 70B |
| **Google Gemini** | [aistudio.google.com](https://aistudio.google.com/app/apikey) | 15 RPM, 1M tokens/day |
| **Anthropic** | [console.anthropic.com](https://console.anthropic.com) | Pay-per-use |

You only need one. Groq is the recommended starting point — free and fast.

### Phase 2 — Configure Terraform

```bash
cd openclaw-gcp
cp .env.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
project_id    = "your-gcp-project-id"
gateway_token = "your-strong-random-token"   # openssl rand -hex 32
groq_api_key  = "gsk_..."                    # at least one LLM key
```

> `terraform.tfvars` is in `.gitignore` — it will never be committed.

### Phase 3 — Deploy

```bash
./scripts/deploy.sh your-gcp-project-id
```

The script:
1. Enables Cloud Run, Secret Manager, Storage, and IAM APIs
2. Runs `terraform apply` (creates all GCP resources)

**Expected output:**
```
=== Deployment Summary ===
  Service URL:      https://openclaw-family-abc123-uc.a.run.app
  Gateway WS URL:   wss://openclaw-family-abc123-uc.a.run.app
  Workspace bucket: gs://your-project-openclaw-memory/
```

### Phase 4 — Connect Claude Code

In any Claude Code session, run:

```
/gateway connect wss://openclaw-family-abc123-uc.a.run.app
```

When prompted for a token, enter the value you set as `gateway_token` in `terraform.tfvars`.

To make the connection permanent (auto-connect on startup), add it to your Claude Code config:

```json
{
  "gateway": {
    "url": "wss://openclaw-family-abc123-uc.a.run.app",
    "token": "your-gateway-token"
  }
}
```

---

## Operations

### View Logs

```bash
# Recent logs
gcloud run services logs read openclaw-family --region us-central1 --limit 50

# Stream live
gcloud beta run services logs tail openclaw-family --region us-central1
```

### Update the OpenClaw Image

```bash
cd terraform && terraform apply -var="project_id=YOUR_PROJECT"
```

Or force a new revision without config changes:

```bash
gcloud run deploy openclaw-family \
  --image docker.io/alpine/openclaw:latest \
  --region us-central1
```

### Rotate the Gateway Token

```bash
# Add a new secret version
echo -n "new-token-value" | gcloud secrets versions add openclaw-gateway-token --data-file=-

# Update terraform.tfvars and re-apply to keep state in sync
cd terraform && terraform apply -var="project_id=YOUR_PROJECT"
```

### Rotate an LLM API Key

```bash
echo -n "new-key-value" | gcloud secrets versions add openclaw-groq-api-key --data-file=-

# Force Cloud Run to pick up the new version
gcloud run deploy openclaw-family \
  --image docker.io/alpine/openclaw:latest \
  --region us-central1
```

### Tear Down

```bash
cd terraform && terraform destroy
```

---

## Cost

With `min_instance_count = 1` (keeps the gateway always on):

| Resource | Always-on cost | Notes |
|---|---|---|
| Cloud Run (2 vCPU / 2 Gi, 1 min-instance) | ~$2–4/mo | Billed for idle time |
| GCS workspace storage | ~$0 | < 10 MB typical |
| Secret Manager | $0 | Within free tier (6 secrets) |
| LLM API | $0 | Groq / Gemini free tiers |
| **Total** | **~$2–4/mo** | |

To reduce to ~$0 when not in use, set `min_instance_count = 0` in `main.tf` — but expect a 5–10s cold start when reconnecting.

---

## Project Structure

```
openclaw-gcp/
├── .env.example                  # Template for terraform/terraform.tfvars
├── .gitignore                    # Excludes tfstate, tfvars, .env files
├── terraform/
│   ├── main.tf                   # All GCP resources (Cloud Run, GCS, IAM, secrets)
│   ├── variables.tf              # Input variables (project, gateway token, LLM keys)
│   ├── outputs.tf                # service_url, gateway_ws_url, workspace_bucket
│   └── terraform.tfvars          # Your values — gitignored, never committed
└── scripts/
    └── deploy.sh                 # Full deploy: enable APIs → terraform apply
```

### GCP Resources Created

| Resource | Name | Purpose |
|---|---|---|
| Cloud Run service | `openclaw-family` | Runs the OpenClaw gateway |
| GCS bucket | `PROJECT-openclaw-memory` | Persistent workspace across restarts |
| Service account | `openclaw-family@...` | Least-privilege identity for Cloud Run |
| Secret | `openclaw-gateway-token` | Shared auth token for client connections |
| Secret | `openclaw-groq-api-key` | Groq API key |
| Secret | `openclaw-gemini-api-key` | Gemini API key (if provided) |
| Secret | `openclaw-anthropic-api-key` | Anthropic API key (if provided) |

---

## Troubleshooting

**Gateway won't start / OOM crash**
- The gateway requires at least 2 Gi of memory. Check `terraform/main.tf` resources limits.
- View crash logs: `gcloud logging read 'resource.labels.service_name="openclaw-family"' --project YOUR_PROJECT --limit 20`

**`/gateway connect` says connection refused**
- Verify the service is running: `gcloud run services describe openclaw-family --region us-central1`
- Check that port 8080 is bound: look for `[gateway] listening on ws://0.0.0.0:8080` in logs

**Auth error on connect**
- The token entered must match `gateway_token` in `terraform.tfvars` (stored in Secret Manager as `openclaw-gateway-token`)
- Verify the secret: `gcloud secrets versions access latest --secret=openclaw-gateway-token`

**`Secret not found` on deploy**
- The secret version may not exist (empty variable). Add the key to `terraform.tfvars` and re-run `terraform apply`.

**Cold start takes too long**
- With `min_instance_count = 1` the gateway is always warm. If you set it to 0, expect 5–10s cold starts.
- Extend the startup probe timeout in Cloud Run if needed.
