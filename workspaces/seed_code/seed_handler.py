import json


def handler(event, context):
    headers = event.get("headers") or {}
    origin = headers.get("origin") or headers.get("Origin") or "*"
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": origin,
        },
        "body": json.dumps(
            {
                "message": "Seed lambda artifact",
                "function_name": getattr(context, "function_name", "unknown"),
            }
        ),
    }
