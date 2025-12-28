#!/bin/bash

# Stop the Torrents to IDM service on AWS
# This will stop charges (except for S3 storage)

set -e

AWS_REGION=${1:-us-east-1}
CLUSTER_NAME="torrents-to-idm-cluster"
SERVICE_NAME="torrents-to-idm-service"
STACK_NAME="torrents-to-idm-stack"

echo "🛑 Stopping Torrents to IDM service..."
echo "Region: $AWS_REGION"
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION >/dev/null 2>&1; then
    echo "⚠️  Stack '$STACK_NAME' not found. Nothing to stop."
    exit 0
fi

# Stop the service
echo "⏸️  Setting desired count to 0..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --desired-count 0 \
    --region $AWS_REGION >/dev/null

echo "⏳ Waiting for service to stop..."

# Wait for service to stop
SECONDS=0
while [ $SECONDS -lt 60 ]; do
    RUNNING_COUNT=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].runningCount' \
        --output text)
    
    if [ "$RUNNING_COUNT" = "0" ]; then
        break
    fi
    
    echo -n "."
    sleep 3
done
echo ""

echo ""
echo "✅ Service stopped!"
echo ""
echo "💰 You are no longer being charged for compute (Fargate)"
echo "📦 S3 storage costs still apply (minimal, ~\$0.023/GB/month)"
echo ""
echo "💡 To start again: ./scripts/start-service.sh"
echo "💡 To delete everything: ./scripts/cleanup-aws.sh"
