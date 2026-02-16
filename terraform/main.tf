terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Uncomment to use GCS backend for state storage
  # backend "gcs" {
  #   bucket = "YOUR_PROJECT-terraform-state"
  #   prefix = "openclaw/state"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ──────────────────────────────────────────────
# GCS Bucket for persistent OpenClaw workspace
# ──────────────────────────────────────────────
resource "google_storage_bucket" "openclaw_memory" {
  name                        = "${var.project_id}-openclaw-memory"
  location                    = var.region
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 7
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    managed_by = "terraform"
    app        = "openclaw"
  }
}

# ──────────────────────────────────────────────
# Service Account for Cloud Run
# ──────────────────────────────────────────────
resource "google_service_account" "openclaw" {
  account_id   = "openclaw-family"
  display_name = "OpenClaw Gateway Service Account"
}

# Allow Cloud Run SA to read secrets
resource "google_project_iam_member" "openclaw_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

# Allow Cloud Run SA to access GCS bucket
resource "google_storage_bucket_iam_member" "openclaw_gcs" {
  bucket = google_storage_bucket.openclaw_memory.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.openclaw.email}"
}

# ──────────────────────────────────────────────
# Secret Manager — Telegram Bot Token
# ──────────────────────────────────────────────
resource "google_secret_manager_secret" "telegram_token" {
  secret_id = "openclaw-telegram-bot-token"

  replication {
    auto {}
  }

  labels = {
    app = "openclaw"
  }
}

resource "google_secret_manager_secret_version" "telegram_token" {
  secret      = google_secret_manager_secret.telegram_token.id
  secret_data = var.telegram_bot_token
}

# ──────────────────────────────────────────────
# Secret Manager — OpenClaw Gateway Token
# ──────────────────────────────────────────────
resource "google_secret_manager_secret" "gateway_token" {
  secret_id = "openclaw-gateway-token"

  replication {
    auto {}
  }

  labels = {
    app = "openclaw"
  }
}

resource "google_secret_manager_secret_version" "gateway_token" {
  secret      = google_secret_manager_secret.gateway_token.id
  secret_data = var.gateway_token
}

# ──────────────────────────────────────────────
# Secret Manager — Groq API Key (optional)
# ──────────────────────────────────────────────
resource "google_secret_manager_secret" "groq_api_key" {
  secret_id = "openclaw-groq-api-key"

  replication {
    auto {}
  }

  labels = {
    app = "openclaw"
  }
}

resource "google_secret_manager_secret_version" "groq_api_key" {
  count       = var.groq_api_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.groq_api_key.id
  secret_data = var.groq_api_key
}

# ──────────────────────────────────────────────
# Secret Manager — Gemini API Key (optional)
# ──────────────────────────────────────────────
resource "google_secret_manager_secret" "gemini_api_key" {
  secret_id = "openclaw-gemini-api-key"

  replication {
    auto {}
  }

  labels = {
    app = "openclaw"
  }
}

resource "google_secret_manager_secret_version" "gemini_api_key" {
  count       = var.gemini_api_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.gemini_api_key.id
  secret_data = var.gemini_api_key
}

# ──────────────────────────────────────────────
# Secret Manager — Anthropic API Key (optional)
# ──────────────────────────────────────────────
resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "openclaw-anthropic-api-key"

  replication {
    auto {}
  }

  labels = {
    app = "openclaw"
  }
}

resource "google_secret_manager_secret_version" "anthropic_api_key" {
  count       = var.anthropic_api_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.anthropic_api_key.id
  secret_data = var.anthropic_api_key
}

# ──────────────────────────────────────────────
# Cloud Run Service
# ──────────────────────────────────────────────
resource "google_cloud_run_v2_service" "openclaw" {
  name     = "openclaw-family"
  location = var.region

  template {
    service_account = google_service_account.openclaw.email

    containers {
      image = var.container_image

      # Write openclaw.json config then start the gateway.
      # --bind lan  → listen on 0.0.0.0 (not loopback)
      # --port 8080 → Cloud Run's required port
      command = ["sh", "-c"]
      args = [
        join(" ", [
          "mkdir -p /home/node/.openclaw &&",
          "printf '%s' '{\"agents\":{\"defaults\":{\"model\":{\"primary\":\"google/gemini-2.0-flash\",\"fallbacks\":[\"groq/llama-3.3-70b-versatile\"]},\"compaction\":{\"reserveTokensFloor\":4000}}},\"channels\":{\"telegram\":{\"enabled\":true,\"dmPolicy\":\"allowlist\",\"allowFrom\":[\"${var.allowed_user_ids}\"]}}}' > /home/node/.openclaw/openclaw.json &&",
          "node openclaw.mjs gateway --allow-unconfigured --bind lan --port 8080",
        ])
      ]

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        startup_cpu_boost = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name = "TELEGRAM_BOT_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.telegram_token.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "OPENCLAW_GATEWAY_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gateway_token.secret_id
            version = "latest"
          }
        }
      }

      # GROQ_API_KEY — only mounted if secret has a version
      dynamic "env" {
        for_each = var.groq_api_key != "" ? [1] : []
        content {
          name = "GROQ_API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.groq_api_key.secret_id
              version = "latest"
            }
          }
        }
      }

      # GEMINI_API_KEY — only mounted if secret has a version
      dynamic "env" {
        for_each = var.gemini_api_key != "" ? [1] : []
        content {
          name = "GEMINI_API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.gemini_api_key.secret_id
              version = "latest"
            }
          }
        }
      }

      # ANTHROPIC_API_KEY — only mounted if secret has a version
      dynamic "env" {
        for_each = var.anthropic_api_key != "" ? [1] : []
        content {
          name = "ANTHROPIC_API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.anthropic_api_key.secret_id
              version = "latest"
            }
          }
        }
      }

    }

    scaling {
      min_instance_count = 1 # Keep alive — WebSocket clients need a persistent target
      max_instance_count = 1 # Single-user gateway
    }
  }

  depends_on = [
    google_secret_manager_secret_version.telegram_token,
    google_secret_manager_secret_version.gateway_token,
    google_project_iam_member.openclaw_secret_accessor,
    google_storage_bucket_iam_member.openclaw_gcs,
  ]
}

# ──────────────────────────────────────────────
# Allow clients to connect without GCP auth
# ──────────────────────────────────────────────
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.openclaw.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
