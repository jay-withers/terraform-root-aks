locals {
  tags = merge(var.tags, {
    environment = var.environment
    managed-by  = "terraform"
  })
}
