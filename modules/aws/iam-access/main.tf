locals {
  base_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    ClientId    = var.client_id
    Environment = var.environment
  })

  oidc_provider_arn = try(trimspace(var.oidc_provider_arn), "")
  oidc_roles        = var.oidc_roles
  oidc_claim_namespace = (
    trimspace(var.oidc_issuer_url) != "" ?
    trimprefix(trimspace(var.oidc_issuer_url), "https://") :
    ""
  )

  oidc_role_name_components = {
    for role_key, role in local.oidc_roles :
    role_key => (
      try(trimspace(role.role_name_suffix), "") != "" ?
      replace(try(trimspace(role.role_name_suffix), ""), "/", "-") :
      replace(role_key, "/", "-")
    )
  }

  create_oidc_provider = length(local.oidc_roles) > 0 && local.oidc_provider_arn == ""
  resolved_oidc_provider_arn = local.create_oidc_provider ? aws_iam_openid_connect_provider.this[0].arn : (
    local.oidc_provider_arn != "" ? local.oidc_provider_arn : null
  )

  oidc_role_names = {
    for role_key, role in local.oidc_roles :
    role_key => substr(
      format("%s-role-%s", var.name_prefix, local.oidc_role_name_components[role_key]),
      0,
      64,
    )
  }

  oidc_role_audience_values = {
    for role_key, role in local.oidc_roles :
    role_key => length(try(role.audience_values, [])) > 0 ? try(role.audience_values, []) : ["sts.amazonaws.com"]
  }

  oidc_managed_policy_attachments = {
    for item in flatten([
      for role_key, role in local.oidc_roles : [
        for policy_arn in try(role.managed_policy_arns, []) : {
          map_key    = "${role_key}|${policy_arn}"
          role_key   = role_key
          policy_arn = policy_arn
        }
      ]
    ]) : item.map_key => item
  }
}

resource "aws_iam_openid_connect_provider" "this" {
  count = local.create_oidc_provider ? 1 : 0

  url             = var.oidc_issuer_url
  client_id_list  = var.oidc_client_id_list
  thumbprint_list = var.oidc_thumbprint_list
  tags            = local.base_tags
}

data "aws_iam_policy_document" "oidc_assume_role" {
  for_each = local.oidc_roles

  statement {
    sid     = "FederatedAssumeRole"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.resolved_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_claim_namespace}:aud"
      values   = local.oidc_role_audience_values[each.key]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_claim_namespace}:sub"
      values   = each.value.subject_claims
    }
  }
}

resource "aws_iam_role" "oidc" {
  for_each = local.oidc_roles

  name               = local.oidc_role_names[each.key]
  description        = try(each.value.description, null) != null ? each.value.description : "Federated OIDC role for ${each.key}."
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_role[each.key].json
  tags               = merge(local.base_tags, try(each.value.tags, {}))
}

resource "aws_iam_role_policy_attachment" "oidc_managed" {
  for_each = local.oidc_managed_policy_attachments

  role       = aws_iam_role.oidc[each.value.role_key].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "oidc_inline" {
  for_each = {
    for role_key, role in local.oidc_roles :
    role_key => role
    if trimspace(try(role.inline_policy_json, "")) != ""
  }

  name   = substr("${local.oidc_role_names[each.key]}-inline", 0, 128)
  role   = aws_iam_role.oidc[each.key].id
  policy = each.value.inline_policy_json
}
