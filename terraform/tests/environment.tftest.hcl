# Naming/tagging is derived from var.workload_name and var.environment via the
# Azure naming module; validate the environment allow-list and the derivation.
# The azurerm provider is mocked, so these run with no Azure credentials —
# both locally (`make test`) and in CI (ci-terraform).

mock_provider "azurerm" {}

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

run "rejects_environment_outside_allow_list" {
  command = plan

  variables {
    environment = "production"
  }

  expect_failures = [var.environment]
}
