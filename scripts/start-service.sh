#!/bin/bash

# Start the Torrents to IDM service on AWS
# This will incur charges while running

set -e

AWS_REGION=${1:-us-east-1}
CLUSTER_NAME="torrents-to-idm-cluster"
SERVICE_NAME="torrents-to-idm-service"
STACK_NAME="torrents-to-idm-stack"

echo "🚀 Starting Torrents to IDM service..."
echo "Region: $AWS_REGION"
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION >/dev/null 2>&1; then
    echo "❌ Stack '$STACK_NAME' not found. Please deploy first using ./deploy-aws.sh"
    exit 1
fi

# Start the service
echo "▶️  Setting desired count to 1..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --desired-count 1 \
    --region $AWS_REGION >/dev/null

echo "⏳ Waiting for service to start (this takes 2-3 minutes)..."

# Wait for service to be stable
SECONDS=0
while [ $SECONDS -lt 180 ]; do
    RUNNING_COUNT=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].runningCount' \
        --output text)
    
    if [ "$RUNNING_COUNT" = "1" ]; then
        break
    fi
    
    echo -n "."
    sleep 5
done
echo ""

# Get service URL
SERVICE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceURL`].OutputValue' \
    --output text \
    --region $AWS_REGION)

echo ""
echo "✅ Service is starting!"
echo ""
echo "🌍 Service URL: $SERVICE_URL"
echo "📊 Status: http://$SERVICE_URL/torrents"
echo ""
echo "⏰ The service will be fully ready in 1-2 minutes"
echo "💰 Cost while running: ~\$0.01-0.02/hour"
echo ""
echo "⚠️  Remember to stop the service when done using ./scripts/stop-service.sh"
