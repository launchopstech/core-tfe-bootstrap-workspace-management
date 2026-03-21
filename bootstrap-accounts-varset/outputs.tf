output "bootstrap_global_variable_set_id" {
  value = tfe_variable_set.bootstrap_global.id
}

output "environment_variable_set_ids" {
  value = {
    for environment, variable_set in tfe_variable_set.bootstrap_environment : environment => variable_set.id
  }
}

output "security_tier_variable_set_ids" {
  value = {
    for security_tier, variable_set in tfe_variable_set.bootstrap_security_tier : security_tier => variable_set.id
  }
}

output "control_plane_secrets_variable_set_id" {
  value = try(tfe_variable_set.control_plane_secrets[0].id, null)
}

output "project_ids" {
  value = {
    sbx       = tfe_project.bootstrap_sbx.id
    dev       = tfe_project.bootstrap_dev.id
    qa        = tfe_project.bootstrap_qa.id
    prod      = tfe_project.bootstrap_prod.id
    workbench = tfe_project.bootstrap_workbench.id
  }
}

output "bootstrap_dev_project_id" {
  value = tfe_project.bootstrap_dev.id
}

output "bootstrap_workbench_project_id" {
  value = tfe_project.bootstrap_workbench.id
}

output "team_dev_project_id" {
  value = tfe_project.team_dev.id
}

output "team_workbench_project_id" {
  value = tfe_project.team_workbench.id
}

output "team_project_ids" {
  value = {
    sbx       = tfe_project.team_sbx.id
    dev       = tfe_project.team_dev.id
    qa        = tfe_project.team_qa.id
    prod      = tfe_project.team_prod.id
    workbench = tfe_project.team_workbench.id
  }
}
