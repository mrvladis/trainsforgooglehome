terraform {
  backend "azurerm" {
    storage_account_name = "crstlrsatptteraf01"
    container_name       = "terraformstatus"
    key                  = "ATPTGOV.terraform.tfstate"
  }
  required_version = "~>  0.12"
}
provider "azurerm" {
  version = "< 2"
}
