import json


def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "message": "Seed lambda artifact",
                "function_name": getattr(context, "function_name", "unknown"),
            }
        ),
    }
