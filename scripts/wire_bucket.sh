#!/usr/bin/env bash
# Post-deploy wiring for the uploads bucket.
# The bucket, its CORS (minus MaxAgeSeconds) and the S3->Lambda trigger are
# managed by CloudFormation (see serverless.yml). This script only tops up
# what CloudFormation cannot express here:
#   1. MaxAgeSeconds on the CORS rule (CFN's EarlyValidation hook rejects it;
#      the S3 API accepts it fine) — applied from cors.json.
#   2. Re-asserts the S3 trigger (harmless if CloudFormation already owns an
#      identical notification; S3 keeps a single configuration per bucket).
# Usage: ./scripts/wire_bucket.sh [stage]   (default: dev)
set -euo pipefail

STAGE="${1:-dev}"
REGION="ap-south-1"
SERVICE="loan-engine"

BUCKET="$(aws cloudformation describe-stacks --stack-name "${SERVICE}-${STAGE}" \
  --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='UploadsBucketName'].OutputValue" \
  --output text)"
FN_ARN="$(aws lambda get-function --function-name "${SERVICE}-${STAGE}-processCsv" \
  --region "$REGION" --query "Configuration.FunctionArn" --output text)"

echo "Bucket:   $BUCKET"
echo "Function: $FN_ARN"

# 1. CORS (same rules as cors.json in repo root)
aws s3api put-bucket-cors --bucket "$BUCKET" --region "$REGION" \
  --cors-configuration file://cors.json
echo "CORS applied."

# 2. Let S3 invoke processCsv (idempotent: drop old statement first)
aws lambda remove-permission --function-name "$FN_ARN" --region "$REGION" \
  --statement-id s3-upload-trigger 2>/dev/null || true
aws lambda add-permission --function-name "$FN_ARN" --region "$REGION" \
  --statement-id s3-upload-trigger --action lambda:InvokeFunction \
  --principal s3.amazonaws.com --source-arn "arn:aws:s3:::$BUCKET" \
  --source-account "$(aws sts get-caller-identity --query Account --output text)"
echo "Lambda invoke permission granted."

# 3. Fire processCsv on every new uploads/*.csv object
NOTIFY="$(mktemp)"
cat > "$NOTIFY" <<EOF
{"LambdaFunctionConfigurations": [{
  "Id": "process-csv-uploads",
  "LambdaFunctionArn": "$FN_ARN",
  "Events": ["s3:ObjectCreated:*"],
  "Filter": {"Key": {"FilterRules": [
    {"Name": "prefix", "Value": "uploads/"},
    {"Name": "suffix", "Value": ".csv"}
  ]}}
}]}
EOF
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" \
  --region "$REGION" --notification-configuration "file://$NOTIFY"
rm -f "$NOTIFY"
echo "S3 trigger wired. Verifying:"
aws s3api get-bucket-notification-configuration --bucket "$BUCKET" --region "$REGION"
