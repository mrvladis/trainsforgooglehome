data "azurerm_builtin_role_definition" "builtin_role_definition" {
  name = "Contributor"
}
data "azurerm_client_config" "current" {}
