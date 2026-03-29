def handler(event, context):
    method_arn = event.get("methodArn", "*")

    return {
        "principalId": "seed-initializer",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": "Allow",
                    "Resource": method_arn,
                }
            ],
        },
        "context": {
            "authorized": "true",
            "source": "seed",
        },
    }
