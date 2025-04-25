import json
import boto3
import os
import uuid

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

def lambda_handler(event, context):
    body = json.loads(event.get("body", "{}"))

    item = {
        "id": str(uuid.uuid4()),
        "name": body.get("name", "Anonymous"),
        "email": body.get("email", "no-email@example.com")
    }

    table.put_item(Item=item)

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "User registered", "user": item})
    }