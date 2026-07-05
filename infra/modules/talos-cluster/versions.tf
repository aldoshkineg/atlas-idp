terraform {
  required_version = ">= 1.9.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    terracurl = {
      source  = "devops-rob/terracurl"
      version = "~> 1.0"
    }
  }
}
