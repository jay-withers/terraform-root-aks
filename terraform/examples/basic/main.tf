# Basic example — the configuration ci-terraform plans against.
#
# subscription_id is supplied via the ARM_SUBSCRIPTION_ID environment variable;
# use_oidc lets the provider authenticate with GitHub's OIDC token in CI.

provider "azurerm" {
  features {}
  use_oidc = true
}

module "basic" {
  source = "../../"
}
