import json

def lambda_handler(event, context):
    print("EVENT:", event)
    print("CONTEXT:", context)
    print("PARAMS", event.query_params)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }
