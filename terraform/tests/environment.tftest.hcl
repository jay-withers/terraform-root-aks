# Naming/tagging is derived from var.workload_name and var.environment via the
# Azure naming module; validate the environment allow-list and the derivation.
# The azurerm provider is mocked, so these run with no Azure credentials —
# both locally (`make test`) and in CI (ci-terraform).

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

run "dev_derives_name_and_tag" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = module.resource_group.name == "rg-main-dev"
    error_message = "resource group name did not derive from environment"
  }

  assert {
    condition     = local.tags["environment"] == "dev"
    error_message = "resource group tag did not derive from environment"
  }
}

run "stg_derives_name" {
  command = plan

  variables {
    environment = "stg"
  }

  assert {
    condition     = module.resource_group.name == "rg-main-stg"
    error_message = "resource group name did not derive from environment"
  }
}

run "prd_derives_name" {
  command = plan

  variables {
    environment = "prd"
  }

  assert {
    condition     = module.resource_group.name == "rg-main-prd"
    error_message = "resource group name did not derive from environment"
  }
}

run "workload_name_derives_name" {
  command = plan

  variables {
    environment   = "dev"
    workload_name = "widgets"
  }

  assert {
    condition     = module.resource_group.name == "rg-widgets-dev"
    error_message = "resource group name did not derive from workload_name"
  }
}

run "role_named_resources_carry_workload_and_environment" {
  command = plan

  variables {
    environment   = "stg"
    workload_name = "widgets"
  }

  # These carry a role on top of the module's name, so they are built by appending
  # to it rather than generated outright. Role last, keeping the
  # <type>-<workload>-<environment> prefix the module produces — a bare role name
  # would repeat identically in every environment, indistinguishable in a
  # subscription-wide list and useless to anything that keys off resource name.
  assert {
    condition = alltrue([
      module.nsg_nodes.name == "nsg-widgets-stg-nodes",
      module.nsg_api_server.name == "nsg-widgets-stg-apiserver",
      module.nsg_jumpbox[0].name == "nsg-widgets-stg-jumpbox",
      module.nsg_privatelink[0].name == "nsg-widgets-stg-privatelink",
      local.jumpbox_network_interfaces["internal"].name == "nic-widgets-stg-jumpbox",
      module.jumpbox[0].name == "vm-widgets-stg-jumpbox",
      local.jumpbox_key_vault_name == "kv-widgets-stg-jumpbox",
      local.workload_key_vault_name == "kv-widgets-stg-secrets",
    ])
    error_message = "role-named resources must be <naming module name>-<role>, e.g. nsg-widgets-stg-nodes — the role goes last so the workload/environment prefix matches every other resource"
  }

  # The naming module's bastion_host slug is "snap", not "bas", so this name is
  # built by hand and has to stay that way.
  assert {
    condition     = local.bastion_name == "bas-widgets-stg"
    error_message = "the Bastion name must be the CAF \"bas-\" form, not the naming module's \"snap-\" slug"
  }

  # The deliberate exception. The node pools take vnet_subnet_id at create time
  # only, so renaming a subnet replaces the cluster — and the destroy fails while
  # node pools are attached. They are scoped inside a VNet that already names the
  # workload and environment, so role-only is enough.
  assert {
    condition = alltrue([
      local.subnets["nodes"].name == "snet-nodes",
      local.subnets["api_server"].name == "snet-apiserver",
      local.subnets["jumpbox"].name == "snet-jumpbox",
      local.subnets["privatelink"].name == "snet-privatelink",
    ])
    error_message = "subnet names are deliberately role-only — renaming them is a cluster tear-down, not a rename"
  }
}

run "key_vault_names_fit_at_the_workload_name_limit" {
  command = plan

  # Nine characters is the cap, and this is why: both vault names land on exactly 24,
  # Key Vault's limit. Past that the naming module truncates rather than failing, and
  # a truncated global DNS label is both unreadable and likelier to collide.
  variables {
    workload_name = "platforms"
    environment   = "prd"
  }

  assert {
    condition = alltrue([
      local.jumpbox_key_vault_name == "kv-platforms-prd-jumpbox",
      local.workload_key_vault_name == "kv-platforms-prd-secrets",
      length(local.jumpbox_key_vault_name) == 24,
      length(local.workload_key_vault_name) == 24,
    ])
    error_message = "at the workload_name cap both Key Vault names must land on exactly 24 characters — if they do not, the cap and the names have drifted apart"
  }
}

run "rejects_a_workload_name_the_key_vault_cannot_hold" {
  command = plan

  # Ten characters — one past the cap. The naming module would truncate rather than
  # fail, eating into the random component of the workload vault's name, so this has
  # to be caught here: silently, the vault name becomes a collision risk.
  variables {
    workload_name = "platformsv"
  }

  expect_failures = [var.workload_name]
}

run "rejects_environment_outside_allow_list" {
  command = plan

  variables {
    environment = "production"
  }

  expect_failures = [var.environment]
}
