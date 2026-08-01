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

run "dev_derives_name_and_tag" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = azurerm_resource_group.this.name == "rg-main-dev"
    error_message = "resource group name did not derive from environment"
  }

  assert {
    condition     = azurerm_resource_group.this.tags["environment"] == "dev"
    error_message = "resource group tag did not derive from environment"
  }
}

run "stg_derives_name" {
  command = plan

  variables {
    environment = "stg"
  }

  assert {
    condition     = azurerm_resource_group.this.name == "rg-main-stg"
    error_message = "resource group name did not derive from environment"
  }
}

run "prd_derives_name" {
  command = plan

  variables {
    environment = "prd"
  }

  assert {
    condition     = azurerm_resource_group.this.name == "rg-main-prd"
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
    condition     = azurerm_resource_group.this.name == "rg-widgets-dev"
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
      azurerm_network_security_group.nodes.name == "nsg-widgets-stg-nodes",
      azurerm_network_security_group.api_server.name == "nsg-widgets-stg-apiserver",
      azurerm_network_security_group.jumpbox[0].name == "nsg-widgets-stg-jumpbox",
      azurerm_network_interface.jumpbox[0].name == "nic-widgets-stg-jumpbox",
      azurerm_linux_virtual_machine.jumpbox[0].name == "vm-widgets-stg-jumpbox",
    ])
    error_message = "role-named resources must be <naming module name>-<role>, e.g. nsg-widgets-stg-nodes — the role goes last so the workload/environment prefix matches every other resource"
  }

  # The naming module's bastion_host slug is "snap", not "bas", so this name is
  # built by hand and has to stay that way.
  assert {
    condition     = azurerm_bastion_host.this[0].name == "bas-widgets-stg"
    error_message = "the Bastion name must be the CAF \"bas-\" form, not the naming module's \"snap-\" slug"
  }

  # The deliberate exception. The node pools take vnet_subnet_id at create time
  # only, so renaming a subnet replaces the cluster — and the destroy fails while
  # node pools are attached. They are scoped inside a VNet that already names the
  # workload and environment, so role-only is enough.
  assert {
    condition = alltrue([
      azurerm_subnet.nodes.name == "snet-nodes",
      azurerm_subnet.api_server.name == "snet-apiserver",
      azurerm_subnet.jumpbox[0].name == "snet-jumpbox",
    ])
    error_message = "subnet names are deliberately role-only — renaming them is a cluster tear-down, not a rename"
  }
}

run "rejects_a_workload_name_the_key_vault_cannot_hold" {
  command = plan

  # The naming module would truncate rather than fail, so this has to be caught
  # here — silently, the vault name becomes a collision risk.
  variables {
    workload_name = "platform-services"
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
