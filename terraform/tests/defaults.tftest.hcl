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
  #   condition     = output.cluster_name == module.naming.kubernetes_cluster.name
  #   error_message = "cluster name did not match the generated default"
  # }
}
