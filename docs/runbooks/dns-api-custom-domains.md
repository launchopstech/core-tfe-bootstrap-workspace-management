# DNS and API Custom Domains

This runbook covers API Gateway custom domains managed by the `api` workspace
when DNS validation and alias records are managed in Route53.

## Two DNS Patterns

### Delegated Subdomain

Use this when the parent domain remains hosted somewhere else, but a child zone
is delegated to Route53.

Example:
- parent domain: `mindrithm.app`
- Route53 zone: `dev.mindrithm.app`
- API domains: `api.dev.mindrithm.app`, `auth.dev.mindrithm.app`

Steps:
1. Add `dns` to `services`.
2. Set `dns_config_json.zone_name` to the child zone, for example `dev.mindrithm.app`.
3. Apply the control-plane workspace.
4. Apply the account portal workspace.
5. Apply the DNS workspace and copy its `name_servers` output.
6. In the parent DNS host, add an `NS` record for the child label.
   - For `dev.mindrithm.app`, add an `NS` record named `dev`.
   - The record values are the four Route53 nameservers from the DNS workspace output.
7. Wait for delegation to propagate.
8. Apply the API workspace.

Do not create manual `A`, `CNAME`, or ACM validation records for API hostnames
in the parent zone. After delegation, Terraform manages those records inside the
Route53 child zone.

### Whole Domain in Route53

Use this when the registered domain itself should become a Route53 hosted zone.

Example:
- registered domain: `mindrithm.ai`
- Route53 zone: `mindrithm.ai`
- API domains: `api.mindrithm.ai`, `auth.mindrithm.ai`

Steps:
1. Add `dns` to `services`.
2. Set `dns_config_json.zone_name` to the root domain, for example `mindrithm.ai`.
3. Apply the control-plane workspace.
4. Apply the account portal workspace.
5. Apply the DNS workspace and copy its `name_servers` output.
6. In the registrar, replace the domain nameservers with the four Route53 nameservers.
7. Before or immediately after the nameserver change, recreate any required existing
   DNS records in Route53, such as apex, `www`, MX, TXT verification, SPF, DKIM,
   DMARC, and app-specific records.
8. Wait for nameserver propagation.
9. Apply or rerun the API workspace.

For GoDaddy, update **Nameservers** for the domain, not ordinary DNS records.
Choose custom nameservers and enter the four Route53 nameservers without trailing
dots.

## Mindrithm.ai Current Route53 Nameservers

As of the initial `mindrithm.ai` Route53 zone creation, GoDaddy should point
`mindrithm.ai` at:

```text
ns-329.awsdns-41.com
ns-1695.awsdns-19.co.uk
ns-977.awsdns-58.net
ns-1452.awsdns-53.org
```

If the hosted zone is recreated, these values can change. Always prefer the
current `name_servers` output from the DNS workspace or the Route53 hosted zone.

## Verification

Check public nameserver propagation:

```bash
dig +short NS mindrithm.ai
```

Expected output should be the Route53 nameservers, not GoDaddy defaults such as
`ns61.domaincontrol.com` or `ns62.domaincontrol.com`.

Check ACM validation records are public:

```bash
dig +short CNAME _ad705f61943d5444a7e1b9af5263bcd3.api.mindrithm.ai
dig +short CNAME _01860648c0dacadddcccfa28a90bd5a4.auth.mindrithm.ai
```

Check ACM status:

```bash
aws acm list-certificates \
  --region us-east-1 \
  --query 'CertificateSummaryList[?contains(DomainName, `mindrithm.ai`)]' \
  --output json
```

The certificates must move from `PENDING_VALIDATION` to `ISSUED` before API
Gateway custom domains can be created.

Check API Gateway custom domains:

```bash
aws apigateway get-domain-names \
  --region us-east-1 \
  --query 'items[?contains(domainName, `mindrithm.ai`)]' \
  --output json
```

## Apply Order

For a new custom-domain setup, use this order:

```text
bootstrap-account-workspace-management-dev
mindrithm-dev
mindrithm-dns-dev
GoDaddy or parent DNS delegation
mindrithm-api-dev
```

If the API workspace is already waiting on ACM validation, leave it waiting or
rerun it after public DNS shows the Route53 nameservers and ACM CNAMEs.
