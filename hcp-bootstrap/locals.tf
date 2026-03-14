locals {
  control_plane_workspaces = {
    "00-bootstrap-account-workspace-management" = {
      working_directory   = "bootstrap-accounts-varset"
      description         = "Control-plane workspace that manages shared HCP Terraform projects and variable sets."
      global_remote_state = true
      tags                = ["control-plane", "workspace-class-varset", "hcp-terraform"]
    }
    "bootstrap-account-workspace-management-dev" = {
      working_directory   = "bootstrap-accounts-dev"
      description         = "Control-plane workspace that manages bootstrap workspaces for the dev project."
      global_remote_state = false
      tags                = ["control-plane", "workspace-class-bootstrap-manager", "env-dev", "hcp-terraform"]
    }
    "bootstrap-account-workspace-management-workbench" = {
      working_directory   = "bootstrap-accounts-workbench"
      description         = "Control-plane workspace that manages bootstrap workspaces for the workbench project."
      global_remote_state = false
      tags                = ["control-plane", "workspace-class-bootstrap-manager", "env-workbench", "hcp-terraform"]
    }
  }
}
