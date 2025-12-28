#!/bin/bash

# Helper script to deploy Torrents to IDM on AWS
# Usage: ./deploy-aws.sh [region]

set -e

# Configuration
AWS_REGION=${1:-us-east-1}
STACK_NAME="torrents-to-idm-stack"
REPOSITORY_NAME="torrents-to-idm"

echo "🚀 Deploying Torrents to IDM on AWS"
echo "Region: $AWS_REGION"
echo "Stack: $STACK_NAME"
echo ""

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Aborting."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting."; exit 1; }

# Get AWS Account ID
echo "📋 Getting AWS Account ID..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $AWS_ACCOUNT_ID"

# Check if ECR repository exists, create if not
echo ""
echo "🏗️  Setting up ECR repository..."
if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $AWS_REGION >/dev/null 2>&1; then
    echo "✓ ECR repository already exists"
else
    echo "Creating ECR repository..."
    aws ecr create-repository \
        --repository-name $REPOSITORY_NAME \
        --region $AWS_REGION \
        --image-scanning-configuration scanOnPush=true
    echo "✓ ECR repository created"
fi

# Login to ECR
echo ""
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
echo "✓ Logged in to ECR"

# Build Docker image
echo ""
echo "🐳 Building Docker image..."
docker build -t $REPOSITORY_NAME .
echo "✓ Docker image built"

# Tag and push to ECR
echo ""
echo "📤 Pushing image to ECR..."
docker tag $REPOSITORY_NAME:latest \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY_NAME:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY_NAME:latest
echo "✓ Image pushed to ECR"

# Get VPC and Subnet information
echo ""
echo "🌐 Getting VPC and Subnet information..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" --output text --region $AWS_REGION 2>/dev/null || echo "")

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "❌ No default VPC found. Please specify VpcId and SubnetIds manually."
    echo "You can deploy using:"
    echo "  aws cloudformation create-stack --stack-name $STACK_NAME \\"
    echo "    --template-body file://cloudformation-template.yml \\"
    echo "    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxx \\"
    echo "                 ParameterKey=SubnetIds,ParameterValue=\\\"subnet-xxx,subnet-yyy\\\" \\"
    echo "    --capabilities CAPABILITY_IAM --region $AWS_REGION"
    exit 1
fi

SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[0:2].SubnetId" --output text --region $AWS_REGION | tr '\t' ',')

echo "VPC ID: $VPC_ID"
echo "Subnet IDs: $SUBNET_IDS"

# Check if stack exists
echo ""
echo "📦 Checking if stack exists..."
if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION >/dev/null 2>&1; then
    echo "Stack exists, updating..."
    COMMAND="update-stack"
    WAIT_COMMAND="stack-update-complete"
else
    echo "Stack doesn't exist, creating..."
    COMMAND="create-stack"
    WAIT_COMMAND="stack-create-complete"
fi

# Deploy CloudFormation stack
echo ""
echo "☁️  Deploying CloudFormation stack..."
aws cloudformation $COMMAND \
    --stack-name $STACK_NAME \
    --template-body file://cloudformation-template.yml \
    --parameters \
        ParameterKey=VpcId,ParameterValue=$VPC_ID \
        ParameterKey=SubnetIds,ParameterValue=\"$SUBNET_IDS\" \
        ParameterKey=DesiredCount,ParameterValue=1 \
    --capabilities CAPABILITY_IAM \
    --region $AWS_REGION

echo "⏳ Waiting for stack deployment (this takes 5-10 minutes)..."
aws cloudformation wait $WAIT_COMMAND \
    --stack-name $STACK_NAME \
    --region $AWS_REGION

echo ""
echo "✅ Deployment complete!"
echo ""

# Get outputs
echo "📊 Stack Outputs:"
SERVICE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceURL`].OutputValue' \
    --output text \
    --region $AWS_REGION)

S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text \
    --region $AWS_REGION)

echo "🌍 Service URL: $SERVICE_URL"
echo "📦 S3 Bucket: $S3_BUCKET"
echo ""
echo "🎉 Your service is ready!"
echo ""
echo "💡 To save costs, stop the service when not in use:"
echo "   ./scripts/stop-service.sh"
echo ""
echo "💡 To start the service again:"
echo "   ./scripts/start-service.sh"
echo ""
echo "💡 Estimated cost if running 24/7: ~\$28-30/month"
echo "💡 Estimated cost if using on-demand (8hrs/day): ~\$4-5/month"
