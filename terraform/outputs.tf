output "service_url" {
  description = "Cloud Run service URL — use this as the gateway URL in OpenClaw clients"
  value       = google_cloud_run_v2_service.openclaw.uri
}

output "gateway_ws_url" {
  description = "WebSocket URL for OpenClaw clients to connect to (wss://)"
  value       = "wss://${replace(google_cloud_run_v2_service.openclaw.uri, "https://", "")}"
}

output "workspace_bucket" {
  description = "GCS bucket name where OpenClaw config and workspace files are persisted"
  value       = google_storage_bucket.openclaw_memory.name
}

output "service_account_email" {
  description = "Service account email used by Cloud Run"
  value       = google_service_account.openclaw.email
}
