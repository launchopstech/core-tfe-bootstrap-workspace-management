variable "api_name" {
  description = "Name of the API Gateway REST API."
  type        = string
}

variable "client_id" {
  description = "Client identifier."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, qa, prod, workbench)."
  type        = string
}

variable "authorizers" {
  description = "Map of TOKEN authorizers. Key is the authorizer name."
  type = map(object({
    lambda_invoke_arn              = string
    lambda_function_arn            = string
    lambda_function_name           = string
    identity_validation_expression = optional(string, "^Bearer [-_A-Za-z0-9.]+$")
    result_ttl_seconds             = optional(number, 0)
  }))
  default = {}
}

variable "custom_domains" {
  description = "Optional map of resolved custom domains for this Regional REST API. Each entry provisions ACM, Route53 validation, API Gateway custom domain, and a base path mapping. This lower-level module expects hosted_zone_id to already be resolved."
  type = map(object({
    domain_name    = string
    hosted_zone_id = string
    base_path      = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, domain in var.custom_domains :
      trimspace(domain.domain_name) != "" &&
      can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$", trimspace(domain.domain_name))) &&
      trimspace(domain.hosted_zone_id) != "" &&
      can(regex("^Z[A-Z0-9]+$", upper(trimspace(domain.hosted_zone_id))))
    ])
    error_message = "Each custom domain requires a non-empty domain_name and Route53 hosted_zone_id. Domain names must be valid hostnames and hosted_zone_id must look like a Route53 zone ID (for example Z1234567890)."
  }

  validation {
    condition     = length(distinct([for key, domain in var.custom_domains : lower(trimspace(domain.domain_name))])) == length(var.custom_domains)
    error_message = "custom_domains domain_name values must be unique."
  }

  validation {
    condition = alltrue([
      for key, domain in var.custom_domains :
      !startswith(trimspace(try(domain.base_path, "")), "/") &&
      !endswith(trimspace(try(domain.base_path, "")), "/")
    ])
    error_message = "custom_domains base_path must omit leading and trailing slashes. Use an empty string for root mapping or a value like \"api\"."
  }
}

variable "integrations" {
  description = "Map of Lambda integrations. Key is referenced by routes."
  type = map(object({
    lambda_invoke_arn    = string
    lambda_function_name = string
  }))
}

variable "routes" {
  description = "Map of API routes. Each route creates a resource, methods, and integrations."
  type = map(object({
    path_part       = string
    methods         = list(string)
    integration_key = string
    authorizer_key  = optional(string, null)
  }))
}

variable "cors" {
  description = "CORS configuration for OPTIONS preflight. Only a single origin is supported for static REST API CORS."
  type = object({
    allowed_origins = list(string)
    allowed_methods = optional(string, "GET,POST,PUT,PATCH,DELETE,OPTIONS")
    allowed_headers = optional(string, "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token")
  })
  default = { allowed_origins = ["*"] }

  validation {
    condition     = length(var.cors.allowed_origins) == 1
    error_message = "This REST API CORS implementation requires exactly one origin. Use a single origin (e.g. [\"https://app.example.com\"]) or [\"*\"] for open access."
  }
}

variable "stage" {
  description = "Stage configuration."
  type = object({
    name               = optional(string, "v1")
    log_retention_days = optional(number, 90)
  })
  default = {}
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
