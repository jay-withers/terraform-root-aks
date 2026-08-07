terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # Used only by the AVM modules, but declared here so the tests can mock it —
    # `mock_provider "azapi"` otherwise resolves to hashicorp/azapi.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    # Generates the jump box's local administrator password; see main.jumpbox.tf.
    # Windows has no SSH-key equivalent, and Bastion Developer cannot do Entra ID,
    # so a password is the only sign-in path the free SKU leaves open.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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
