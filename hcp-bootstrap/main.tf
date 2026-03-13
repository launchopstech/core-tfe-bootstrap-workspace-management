terraform {
  required_version = ">= 1.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.49.0"
    }
  }
}

resource "tfe_workspace" "control_plane" {
  for_each = local.control_plane_workspaces

  name                = each.key
  description         = each.value.description
  organization        = var.organization
  execution_mode      = "remote"
  working_directory   = each.value.working_directory
  auto_apply          = false
  terraform_version   = var.terraform_version
  queue_all_runs      = false
  speculative_enabled = true
  tag_names           = each.value.tags

  vcs_repo {
    identifier     = var.vcs_repo_identifier
    branch         = var.vcs_branch
    oauth_token_id = var.vcs_oauth_token_id
  }
}
