output "service_url" {
  description = "Cloud Run service URL — use this as the Telegram webhook base URL"
  value       = google_cloud_run_v2_service.openclaw.uri
}

output "webhook_url" {
  description = "Full Telegram webhook URL to register with setWebhook"
  value       = "${google_cloud_run_v2_service.openclaw.uri}/telegram/webhook"
}

output "memory_bucket" {
  description = "GCS bucket name where per-user memory files are stored"
  value       = google_storage_bucket.openclaw_memory.name
}

output "service_account_email" {
  description = "Service account email used by Cloud Run"
  value       = google_service_account.openclaw.email
}
