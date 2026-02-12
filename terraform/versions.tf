terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform"
    storage_account_name = "tfstatefiles01"
    container_name       = "tfstate"
    key                  = "github-runners.tfstate"
  }
}

provider "azurerm" {
  features {}
}
