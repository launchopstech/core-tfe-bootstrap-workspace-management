resource "aws_security_group" "lambda" {
  count = local.has_vpc ? 1 : 0

  name        = "${var.function_name}-sg"
  description = "Security group for Lambda function ${var.function_name}."
  vpc_id      = var.vpc_id
  tags        = local.base_tags
}

resource "aws_security_group_rule" "lambda_egress" {
  count = local.has_vpc ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lambda[0].id
  description       = "Allow all outbound"
}
