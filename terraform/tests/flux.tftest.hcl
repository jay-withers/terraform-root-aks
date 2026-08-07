# Flux is installed through ARM as a cluster extension, so the wiring between the
# extension, the git repository and the credential encoding is the part that can
# silently produce a cluster that never syncs. Pin it here.

mock_provider "azurerm" {
  # The landing zone resource group, the hub VNet and the hub's private DNS zone are
  # looked up, not created (see data.tf). Their IDs are fed to AVM modules that
  # validate the resource ID format; the provider mock otherwise generates a random
  # string. Names here are fixed rather than derived — assertions about derived names
  # use module.naming, which is real.
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-aks-dev"
      name     = "rg-aks-dev"
      location = "westeurope"
    }
  }

  mock_data "azurerm_virtual_network" {
    defaults = {
      id   = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-hub-dev/providers/Microsoft.Network/virtualNetworks/vnet-hub-dev"
      name = "vnet-hub-dev"
    }
  }

  mock_data "azurerm_private_dns_zone" {
    defaults = {
      id   = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-hub-dev/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
      name = "privatelink.vaultcore.azure.net"
    }
  }

  # azurerm_key_vault validates tenant_id as a UUID at plan time; the provider
  # mock otherwise generates a random string.
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

# The AVM modules reach Azure through azapi, and build resource IDs from the
# client config — an unmocked subscription_id fails ID validation at plan time.
mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "22222222-2222-2222-2222-222222222222"
      tenant_id       = "00000000-0000-0000-0000-000000000000"
      object_id       = "11111111-1111-1111-1111-111111111111"
    }
  }
}
mock_provider "random" {}

run "extension_is_installed_by_default" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster_extension.flux[0].extension_type == "microsoft.flux"
    error_message = "the GitOps extension must be microsoft.flux — no other extension type installs Flux"
  }
}

run "no_configuration_without_a_repository" {
  command = plan

  # Flux installed and idle. Better than a configuration pointed at nothing, which
  # the ARM API rejects.
  assert {
    condition     = length(azurerm_kubernetes_flux_configuration.this) == 0
    error_message = "no Flux configuration may be created while flux_git_repository_url is null"
  }
}

run "repository_url_creates_the_configuration" {
  command = plan

  variables {
    flux_git_repository_url = "https://github.com/org/repo.git"
    flux_git_path           = "clusters/dev"
  }

  assert {
    condition     = azurerm_kubernetes_flux_configuration.this[0].git_repository[0].url == "https://github.com/org/repo.git"
    error_message = "the Flux configuration did not track flux_git_repository_url"
  }

  assert {
    condition     = azurerm_kubernetes_flux_configuration.this[0].git_repository[0].reference_value == "main"
    error_message = "the Flux configuration did not default to the main branch"
  }

  assert {
    condition     = one(azurerm_kubernetes_flux_configuration.this[0].kustomizations).path == "clusters/dev"
    error_message = "the Kustomization did not build from flux_git_path"
  }

  # Without pruning, a manifest deleted from git stays applied to the cluster and
  # the repository stops being the source of truth.
  assert {
    condition     = one(azurerm_kubernetes_flux_configuration.this[0].kustomizations).garbage_collection_enabled
    error_message = "the Kustomization must prune objects removed from the repository"
  }

  # Namespace scope would confine the reconciler to flux-system, which cannot
  # install the namespaces and CRDs a cluster repository carries.
  assert {
    condition     = azurerm_kubernetes_flux_configuration.this[0].scope == "cluster"
    error_message = "the Flux configuration must be cluster-scoped"
  }
}

run "flux_can_be_turned_off_entirely" {
  command = plan

  variables {
    flux_enabled            = false
    flux_git_repository_url = "https://github.com/org/repo.git"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_extension.flux) == 0
    error_message = "flux_enabled = false must install no extension"
  }

  # A configuration without the extension is an ARM error, so the URL must not be
  # enough to create one on its own.
  assert {
    condition     = length(azurerm_kubernetes_flux_configuration.this) == 0
    error_message = "flux_enabled = false must create no Flux configuration, even with a repository URL set"
  }
}

run "https_credentials_are_base64_encoded_for_arm" {
  command = plan

  variables {
    flux_git_repository_url = "https://github.com/org/repo.git"
    flux_git_credentials = {
      https_user = "git"
      https_key  = "a-personal-access-token"
    }
  }

  # The variable takes the PAT verbatim; ARM only accepts it encoded.
  assert {
    condition     = nonsensitive(azurerm_kubernetes_flux_configuration.this[0].git_repository[0].https_key_base64) == base64encode("a-personal-access-token")
    error_message = "the HTTPS key must reach ARM base64-encoded"
  }

  assert {
    condition     = nonsensitive(azurerm_kubernetes_flux_configuration.this[0].git_repository[0].ssh_private_key_base64) == null
    error_message = "HTTPS credentials must not also send an SSH key"
  }
}

run "ssh_credentials_are_base64_encoded_for_arm" {
  command = plan

  # Deliberately not PEM-shaped. The module never parses the key — it only
  # base64-encodes whatever it is given — so a realistic
  # "-----BEGIN OPENSSH PRIVATE KEY-----" fixture would buy nothing and trip
  # gitleaks on every commit, which is how real findings end up ignored.
  variables {
    flux_git_repository_url = "ssh://git@github.com/org/repo.git"
    flux_git_credentials = {
      ssh_private_key = "a-fake-ssh-key"
      ssh_known_hosts = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
    }
  }

  assert {
    condition     = nonsensitive(azurerm_kubernetes_flux_configuration.this[0].git_repository[0].ssh_private_key_base64) == base64encode("a-fake-ssh-key")
    error_message = "the SSH private key must reach ARM base64-encoded"
  }

  # Flux verifies the host key, so this travelling with the key is what makes the
  # sync work at all.
  assert {
    condition     = nonsensitive(azurerm_kubernetes_flux_configuration.this[0].git_repository[0].ssh_known_hosts_base64) == base64encode("github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl")
    error_message = "the known_hosts entry must reach ARM base64-encoded"
  }
}

run "public_repository_sends_no_credentials" {
  command = plan

  variables {
    flux_git_repository_url = "https://github.com/org/repo.git"
  }

  assert {
    condition = alltrue([
      nonsensitive(azurerm_kubernetes_flux_configuration.this[0].git_repository[0].https_user) == null,
      nonsensitive(azurerm_kubernetes_flux_configuration.this[0].git_repository[0].https_key_base64) == null,
      nonsensitive(azurerm_kubernetes_flux_configuration.this[0].git_repository[0].ssh_private_key_base64) == null,
    ])
    error_message = "an unauthenticated repository must send no credential fields"
  }
}

run "rejects_mixed_https_and_ssh_credentials" {
  command = plan

  variables {
    flux_git_credentials = {
      https_user      = "git"
      https_key       = "a-personal-access-token"
      ssh_private_key = "a-fake-ssh-key"
      ssh_known_hosts = "github.com ssh-ed25519 AAAA"
    }
  }

  expect_failures = [var.flux_git_credentials]
}

run "rejects_ssh_key_without_known_hosts" {
  command = plan

  variables {
    flux_git_credentials = {
      ssh_private_key = "a-fake-ssh-key"
    }
  }

  expect_failures = [var.flux_git_credentials]
}

run "rejects_a_half_configured_https_credential" {
  command = plan

  variables {
    flux_git_credentials = {
      https_key = "a-personal-access-token"
    }
  }

  expect_failures = [var.flux_git_credentials]
}

run "rejects_a_repository_url_that_is_not_git" {
  command = plan

  variables {
    flux_git_repository_url = "github.com/org/repo"
  }

  expect_failures = [var.flux_git_repository_url]
}

run "rejects_a_sync_interval_below_the_floor" {
  command = plan

  variables {
    flux_sync_interval_seconds = 5
  }

  expect_failures = [var.flux_sync_interval_seconds]
}
