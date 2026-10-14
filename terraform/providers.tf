terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # The Open WebUI stack is disposable and its resource group is meant to
      # be disposable with it, so `terraform destroy` must be able to remove
      # the group even when it still holds things Terraform does not manage.
      #
      # Right now those are the Azure OpenAI account, the Log Analytics
      # workspace, the data collection endpoint, the action group and the
      # metric alert rules: they were created by hand, not declared here.
      # With the default (true) Terraform refuses to destroy a non-empty
      # resource group, so destroy silently stops partway and leaves a
      # half-deleted environment. Flipping the flag makes destroy honest.
      #
      # Long term, declare those resources in Terraform (or move them to their
      # own resource group) so the group's contents are fully described and
      # this override is not needed.
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription_id
}