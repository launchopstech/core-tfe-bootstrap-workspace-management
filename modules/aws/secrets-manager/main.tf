locals {
  base_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })

  github_actions_repositories      = try(var.github_actions.repositories, {})
  github_actions_oidc_provider_arn = trimspace(try(var.github_actions.oidc_provider_arn, ""))

  github_actions_oidc_repositories = {
    for repo_key, repo in local.github_actions_repositories :
    repo_key => repo
    if lower(trimspace(repo.aws_access.mode)) == "oidc_role"
  }

  github_actions_static_key_repositories = {
    for repo_key, repo in local.github_actions_repositories :
    repo_key => repo
    if lower(trimspace(repo.aws_access.mode)) == "static_keys"
  }

  create_github_actions_oidc_provider = length(local.github_actions_oidc_repositories) > 0 && local.github_actions_oidc_provider_arn == ""
  resolved_github_actions_oidc_provider_arn = local.create_github_actions_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : (
    local.github_actions_oidc_provider_arn != "" ? local.github_actions_oidc_provider_arn : null
  )

  github_actions_role_names = {
    for repo_key, repo in local.github_actions_oidc_repositories :
    repo_key => substr(
      regexreplace(
        format(
          "%s-gha-%s",
          var.name_prefix,
          trimspace(try(repo.aws_access.role_name_suffix, "")) != "" ? trimspace(try(repo.aws_access.role_name_suffix, "")) : replace(repo_key, "/", "-"),
        ),
        "[^A-Za-z0-9+=,.@_-]",
        "-",
      ),
      0,
      64,
    )
  }

  github_actions_subject_claims = {
    for repo_key, repo in local.github_actions_oidc_repositories :
    repo_key => length(try(repo.aws_access.subject_claims, [])) > 0 ? try(repo.aws_access.subject_claims, []) : ["repo:${repo_key}:*"]
  }

  github_actions_managed_policy_attachments = {
    for item in flatten([
      for repo_key, repo in local.github_actions_oidc_repositories : [
        for policy_arn in try(repo.aws_access.managed_policy_arns, []) : {
          map_key    = "${repo_key}|${policy_arn}"
          repo_key   = repo_key
          policy_arn = policy_arn
        }
      ]
    ]) : item.map_key => item
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = var.secret_definitions

  name                    = "${var.name_prefix}-${each.value.name_suffix}"
  description             = try(each.value.description, null)
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = try(each.value.recovery_window_in_days, 30)
  tags                    = merge(local.base_tags, try(each.value.tags, {}))
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = local.create_github_actions_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  for_each = local.github_actions_oidc_repositories

  statement {
    sid     = "GitHubActionsAssumeRole"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.resolved_github_actions_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_actions_subject_claims[each.key]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  for_each = local.github_actions_oidc_repositories

  name               = local.github_actions_role_names[each.key]
  description        = "GitHub Actions OIDC role for ${each.key}."
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role[each.key].json
  tags               = merge(local.base_tags, { GitHubRepository = each.key })
}

resource "aws_iam_role_policy_attachment" "github_actions_managed" {
  for_each = local.github_actions_managed_policy_attachments

  role       = aws_iam_role.github_actions[each.value.repo_key].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "github_actions_inline" {
  for_each = {
    for repo_key, repo in local.github_actions_oidc_repositories :
    repo_key => repo
    if trimspace(try(repo.aws_access.inline_policy_json, "")) != ""
  }

  name   = substr("${local.github_actions_role_names[each.key]}-inline", 0, 128)
  role   = aws_iam_role.github_actions[each.key].id
  policy = each.value.aws_access.inline_policy_json
}
