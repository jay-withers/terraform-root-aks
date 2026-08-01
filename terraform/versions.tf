terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # Generates the throwaway admin key the Azure VM API insists on; see
    # jumpbox.tf. Entra ID is the actual login path.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    # Key Vault names are soft-deleted, not released, so without these a destroy
    # followed by an apply fails on a name that appears free but is not. The
    # jump box vault holds one regenerable SSH key, so recovering it on re-apply
    # and purging it on destroy is the behaviour that matches its lifecycle.
    key_vault {
      recover_soft_deleted_key_vaults = true
      purge_soft_delete_on_destroy    = true
    }
  }
}
