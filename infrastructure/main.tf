# Each core vnet contains an ER circuit, gateway subnet, nva subnet and a vnet peering
# it is designed for on-prem DC connections + connections to BUs hubs
# this is the Azure network backbone

#Automation Azure Function
resource "azurerm_resource_group" "MrvTrain" {
  name     = "MRV-RG-GH-TRN-01"
  location = "${var.location}"
}

resource "azurerm_storage_account" "MrvTrainFunctionStorage" {
  name                     = "mrvstlr${lower(var.appName)}${var.deployment_id}"
  resource_group_name      = "${azurerm_resource_group.MrvTrain.name}"
  location                 = "${azurerm_resource_group.MrvTrain.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# resource "azurerm_app_service_plan" "MrvTrainFunctionSP" {
#   name                = "CR-ASP-AUTOF-${var.deployment_id}"
#   location            = "${azurerm_resource_group.MrvTrain.location}"
#   resource_group_name = "${azurerm_resource_group.MrvTrain.name}"

#   sku {
#     tier = "Dynamic"
#     size = "Y1"
#     }
# }


resource "azurerm_key_vault" "MrvTrainKV" {
  name                = "MRV-KV-${upper(var.appName)}-${var.deployment_id}"
  location            = "${azurerm_resource_group.MrvTrain.location}"
  resource_group_name = "${azurerm_resource_group.MrvTrain.name}"

  sku {
    name = "standard"
  }

  tenant_id = "${data.azurerm_client_config.current.tenant_id}"

  enabled_for_disk_encryption = false
  enabled_for_deployment      = true

  tags {
    environment = "Production"
  }
}
