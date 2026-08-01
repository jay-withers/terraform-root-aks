# Pins the auth posture so a refactor cannot quietly reintroduce local accounts
# or in-cluster admin bindings.

mock_provider "azurerm" {
  # azurerm_key_vault validates tenant_id as a UUID at plan time; the provider
  # mock otherwise generates a random string.
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

run "entra_id_and_azure_rbac_are_enabled" {
  command = plan

  assert {
    condition     = local.aad_profile.managed
    error_message = "managed Entra ID integration must be enabled"
  }

  assert {
    condition     = local.aad_profile.enable_azure_rbac
    error_message = "Azure RBAC must authorize cluster access"
  }
}

run "no_admin_groups_bypass_azure_rbac" {
  command = plan

  assert {
    condition     = !contains(keys(local.aad_profile), "admin_group_object_ids")
    error_message = "aad_profile must not grant cluster-admin to Entra ID groups directly — use an Azure role assignment"
  }
}

run "tenant_comes_from_the_deploying_identity" {
  command = plan

  # The provider is mocked, so only the fact that a tenant resolves is testable.
  assert {
    condition     = local.aad_profile.tenant_id != null
    error_message = "the cluster's Entra ID tenant must be resolved from the identity running Terraform"
  }
}
