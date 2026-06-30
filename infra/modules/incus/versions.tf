terraform {
  required_version = ">= 1.5.0"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
