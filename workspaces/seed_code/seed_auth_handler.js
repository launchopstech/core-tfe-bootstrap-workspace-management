// Seed placeholder for auth-handler (provided.al2023 / bootstrap binary).
// This file is uploaded to S3 so Terraform can provision the Lambda function.
// The real auth-handler binary is deployed by the forge-core CI pipeline.
exports.handler = async () => ({ statusCode: 503, body: "auth-handler not yet deployed" });
