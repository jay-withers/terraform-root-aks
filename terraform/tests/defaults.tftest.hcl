# Module tests. The azurerm provider is mocked, so these run with no Azure
# credentials — both locally (`make test`) and in CI (ci-terraform).
#
# Add `assert` blocks as the module grows; see the commented example below.

mock_provider "azurerm" {}

run "plan_with_defaults" {
  command = plan

  # Example assertion — uncomment once the module creates resources/outputs:
  #
  # assert {
  #   condition     = output.name == var.name
  #   error_message = "output name did not match the requested name"
  # }
}
