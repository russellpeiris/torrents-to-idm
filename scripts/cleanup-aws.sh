#!/bin/bash

# Clean up all AWS resources for Torrents to IDM
# WARNING: This will delete everything including downloaded files in S3

set -e

AWS_REGION=${1:-ap-south-1}
STACK_NAME="torrents-to-idm-stack"
REPOSITORY_NAME="torrents-to-idm"

echo "🗑️  AWS Cleanup for Torrents to IDM"
echo "Region: $AWS_REGION"
echo ""
echo "⚠️  WARNING: This will delete:"
echo "   - ECS Cluster and Service"
echo "   - Load Balancer"
echo "   - S3 Bucket (and all downloaded files)"
echo "   - ECR Repository (and Docker images)"
echo "   - All CloudFormation resources"
echo ""
read -p "Are you sure? (type 'yes' to continue): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "🗑️  Deleting CloudFormation stack..."
if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION >/dev/null 2>&1; then
    # First, empty the S3 bucket (CloudFormation can't delete non-empty buckets)
    S3_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
        --output text \
        --region $AWS_REGION 2>/dev/null || echo "")
    
    if [ -n "$S3_BUCKET" ] && [ "$S3_BUCKET" != "None" ]; then
        echo "📦 Emptying S3 bucket: $S3_BUCKET..."
        aws s3 rm s3://$S3_BUCKET --recursive --region $AWS_REGION 2>/dev/null || true
    fi
    
    aws cloudformation delete-stack \
        --stack-name $STACK_NAME \
        --region $AWS_REGION
    
    echo "⏳ Waiting for stack deletion (this takes 5-10 minutes)..."
    aws cloudformation wait stack-delete-complete \
        --stack-name $STACK_NAME \
        --region $AWS_REGION || true
    
    echo "✓ Stack deleted"
else
    echo "⚠️  Stack not found, skipping..."
fi

echo ""
echo "🗑️  Deleting ECR repository..."
if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $AWS_REGION >/dev/null 2>&1; then
    aws ecr delete-repository \
        --repository-name $REPOSITORY_NAME \
        --force \
        --region $AWS_REGION
    echo "✓ ECR repository deleted"
else
    echo "⚠️  ECR repository not found, skipping..."
fi

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "💰 All resources deleted. No more charges."
echo ""
echo "💡 To redeploy: ./deploy-aws.sh"
