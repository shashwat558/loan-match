import sys
from lambdas.process_csv.handler import handler

batch_id = sys.argv[1]
event = {"Records": [{"s3": {
    "bucket": {"name": "loanmatch-dev-uploads-shashwat"},
    "object": {"key": f"uploads/{batch_id}.csv"},
}}]}
print(handler(event, None))
