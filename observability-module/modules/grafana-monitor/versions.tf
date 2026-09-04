terraform {
  required_version = ">= 1.5"

  required_providers {
    grafana = {
      source = "grafana/grafana"
      # Pinned to a specific minor line (allows patch-level bumps only) so
      # that alert-rule behavior doesn't silently change under a provider
      # upgrade. 4.45.x was the latest stable line as of this writing.
      version = "~> 4.45.2"
    }
  }
}
