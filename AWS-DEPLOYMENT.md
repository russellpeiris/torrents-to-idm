# AWS Deployment Guide for Torrents to IDM

This guide provides step-by-step instructions for deploying the Torrents to IDM application on AWS using cost-effective strategies.

## Cost Optimization Strategy

This deployment uses several AWS services optimized for minimal cost:

1. **ECS Fargate Spot Instances** - Save up to 70% compared to regular Fargate
2. **Minimal CPU/Memory** - 0.5 vCPU and 1GB RAM (~$10-15/month if running 24/7)
3. **S3 Lifecycle Policies** - Auto-delete files after 7 days
4. **Short Log Retention** - 7 days to minimize CloudWatch costs
5. **ECR Image Cleanup** - Keep only last 3 images

### Estimated Monthly Costs

**Scenario 1: On-Demand Usage (Start/Stop as needed)**
- Run 8 hours/day: ~$4-5/month
- Run only when downloading: < $1/month

**Scenario 2: 24/7 Operation**
- Fargate Spot (0.5 vCPU, 1GB): ~$10-12/month
- ALB: ~$16/month
- S3 Storage (100GB): ~$2.3/month
- **Total**: ~$28-30/month

**Recommendation**: Use on-demand approach - start the service only when needed!

## Prerequisites

1. AWS Account
2. AWS CLI installed and configured
3. Docker installed locally
4. Node.js 18+ (for local testing)

## Deployment Options

### Option 1: Quick Deploy with ECS Fargate Spot (Recommended for Cost)

This is the most cost-effective option for running the service.

#### Step 1: Create ECR Repository and Build Docker Image

```bash
# Set your AWS region
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create ECR repository
aws ecr create-repository \
    --repository-name torrents-to-idm \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and tag the Docker image
docker build -t torrents-to-idm .
docker tag torrents-to-idm:latest \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/torrents-to-idm:latest

# Push to ECR
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/torrents-to-idm:latest
```

#### Step 2: Deploy Using CloudFormation

```bash
# Get your VPC ID and Subnet IDs
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" --output text --region $AWS_REGION)

export SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[0:2].SubnetId" --output text --region $AWS_REGION | tr '\t' ',')

# Deploy the stack
aws cloudformation create-stack \
    --stack-name torrents-to-idm-stack \
    --template-body file://cloudformation-template.yml \
    --parameters \
        ParameterKey=VpcId,ParameterValue=$VPC_ID \
        ParameterKey=SubnetIds,ParameterValue=\"$SUBNET_IDS\" \
        ParameterKey=DesiredCount,ParameterValue=1 \
    --capabilities CAPABILITY_IAM \
    --region $AWS_REGION

# Wait for stack creation (takes 5-10 minutes)
aws cloudformation wait stack-create-complete \
    --stack-name torrents-to-idm-stack \
    --region $AWS_REGION

# Get the service URL
aws cloudformation describe-stacks \
    --stack-name torrents-to-idm-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceURL`].OutputValue' \
    --output text \
    --region $AWS_REGION
```

#### Step 3: Access Your Service

Once deployed, you can access your service at the LoadBalancer DNS name output from the CloudFormation stack.

### Option 2: Manual ECS Deployment (More Control)

If you prefer manual setup or need custom configurations:

1. **Create ECS Cluster**:
```bash
aws ecs create-cluster \
    --cluster-name torrents-to-idm-cluster \
    --capacity-providers FARGATE_SPOT \
    --default-capacity-provider-strategy capacityProvider=FARGATE_SPOT,weight=1 \
    --region $AWS_REGION
```

2. **Register Task Definition**:
```bash
# Create a task definition JSON file (see task-definition.json)
aws ecs register-task-definition \
    --cli-input-json file://task-definition.json \
    --region $AWS_REGION
```

3. **Create Service**:
```bash
aws ecs create-service \
    --cluster torrents-to-idm-cluster \
    --service-name torrents-to-idm-service \
    --task-definition torrents-to-idm:1 \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[sg-xxx],assignPublicIp=ENABLED}" \
    --region $AWS_REGION
```

### Option 3: EC2 Spot Instances (Ultra-Low Cost)

For the absolute lowest cost (< $5/month), use EC2 Spot Instances:

```bash
# Launch a t3.micro Spot instance (should cost ~$0.003/hour)
aws ec2 run-instances \
    --image-id ami-0c55b159cbfafe1f0 \
    --instance-type t3.micro \
    --instance-market-options '{"MarketType":"spot","SpotOptions":{"MaxPrice":"0.01"}}' \
    --user-data file://user-data.sh \
    --region $AWS_REGION
```

User data script (`user-data.sh`):
```bash
#!/bin/bash
yum update -y
yum install -y docker git
service docker start
usermod -a -G docker ec2-user

# Clone and run the application
git clone https://github.com/russellpeiris/torrents-to-idm.git
cd torrents-to-idm
docker build -t torrents-to-idm .
docker run -d -p 3000:3000 --restart unless-stopped torrents-to-idm
```

## Cost Optimization Tips

### 1. Start/Stop on Demand

**Best Practice**: Don't run 24/7. Start the service only when you need to download.

```bash
# Stop the service when not in use
aws ecs update-service \
    --cluster torrents-to-idm-cluster \
    --service torrents-to-idm-service \
    --desired-count 0 \
    --region $AWS_REGION

# Start when needed
aws ecs update-service \
    --cluster torrents-to-idm-cluster \
    --service torrents-to-idm-service \
    --desired-count 1 \
    --region $AWS_REGION
```

Create helper scripts for easy start/stop:

**start.sh**:
```bash
#!/bin/bash
aws ecs update-service --cluster torrents-to-idm-cluster \
    --service torrents-to-idm-service --desired-count 1 --region us-east-1
echo "Service starting... It will be ready in 2-3 minutes"
```

**stop.sh**:
```bash
#!/bin/bash
aws ecs update-service --cluster torrents-to-idm-cluster \
    --service torrents-to-idm-service --desired-count 0 --region us-east-1
echo "Service stopped. No charges while stopped!"
```

### 2. Use AWS Free Tier

If you're within the first 12 months of AWS:
- EC2: 750 hours/month of t2.micro or t3.micro
- S3: 5GB storage
- ECS/Fargate: No free tier, but minimal cost

### 3. Clean Up Resources

Always clean up when done with large downloads:

```bash
# Delete old torrents via API
curl -X DELETE http://your-service-url/torrents/{infoHash}

# Or delete the entire stack
aws cloudformation delete-stack \
    --stack-name torrents-to-idm-stack \
    --region $AWS_REGION
```

### 4. Use S3 Lifecycle Policies

The CloudFormation template includes automatic file deletion after 7 days. Adjust if needed:

```bash
# Files older than 7 days are automatically deleted
# Edit cloudformation-template.yml ExpirationInDays if you need more/less time
```

### 5. Monitor Costs

Set up billing alerts:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name torrents-to-idm-cost-alert \
    --alarm-description "Alert when costs exceed $10" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 21600 \
    --evaluation-periods 1 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold
```

## Local Testing

Before deploying to AWS, test locally:

```bash
# Using Docker Compose
docker-compose up -d

# Or using Docker directly
docker build -t torrents-to-idm .
docker run -p 3000:3000 torrents-to-idm

# Or using Node.js directly
npm install
npm start
```

Access at: http://localhost:3000

## Accessing from IDM

Once deployed, you can use IDM to download files:

1. Add a torrent via the web interface or API
2. Copy the download URL for the file (e.g., `http://your-alb-url/d/{infoHash}/{fileIndex}/{fileName}`)
3. Paste the URL into IDM
4. IDM will download at full speed using HTTP range requests

## Troubleshooting

### Service won't start
```bash
# Check service status
aws ecs describe-services \
    --cluster torrents-to-idm-cluster \
    --services torrents-to-idm-service \
    --region $AWS_REGION

# Check task logs
aws logs tail /ecs/torrents-to-idm --follow --region $AWS_REGION
```

### High costs
```bash
# Check if service is running when it shouldn't be
aws ecs describe-services \
    --cluster torrents-to-idm-cluster \
    --services torrents-to-idm-service \
    --region $AWS_REGION

# Stop immediately
aws ecs update-service \
    --cluster torrents-to-idm-cluster \
    --service torrents-to-idm-service \
    --desired-count 0 \
    --region $AWS_REGION
```

### Can't connect to service
```bash
# Check security group allows your IP
# Get public IP
curl https://checkip.amazonaws.com

# Update security group if needed
aws ec2 authorize-security-group-ingress \
    --group-id sg-xxx \
    --protocol tcp \
    --port 3000 \
    --cidr YOUR_IP/32 \
    --region $AWS_REGION
```

## Cleanup

To completely remove all resources and stop all charges:

```bash
# Delete CloudFormation stack (this removes everything)
aws cloudformation delete-stack \
    --stack-name torrents-to-idm-stack \
    --region $AWS_REGION

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name torrents-to-idm-stack \
    --region $AWS_REGION

# Delete ECR images (optional)
aws ecr delete-repository \
    --repository-name torrents-to-idm \
    --force \
    --region $AWS_REGION
```

## Security Considerations

1. **Restrict Access**: Update the security group to allow only your IP address
2. **Use HTTPS**: Consider adding ACM certificate to ALB for HTTPS
3. **VPN/Bastion**: For better security, deploy in private subnet with VPN access
4. **IAM Roles**: Never hardcode AWS credentials; use IAM roles (already configured in template)

## Advanced: Auto-Shutdown After Idle

Save costs by automatically stopping after idle period:

```python
# Lambda function to check and stop if idle (run every hour)
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ecs = boto3.client('ecs')
    cloudwatch = boto3.client('cloudwatch')
    
    # Check network activity in last hour
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/ECS',
        MetricName='NetworkIn',
        Dimensions=[
            {'Name': 'ServiceName', 'Value': 'torrents-to-idm-service'},
            {'Name': 'ClusterName', 'Value': 'torrents-to-idm-cluster'}
        ],
        StartTime=datetime.now() - timedelta(hours=1),
        EndTime=datetime.now(),
        Period=3600,
        Statistics=['Sum']
    )
    
    # If no activity, stop the service
    if not response['Datapoints'] or response['Datapoints'][0]['Sum'] < 1000000:  # Less than 1MB
        ecs.update_service(
            cluster='torrents-to-idm-cluster',
            service='torrents-to-idm-service',
            desiredCount=0
        )
        print("Service stopped due to inactivity")
    
    return {'statusCode': 200, 'body': json.dumps('Checked')}
```

## Support

For issues or questions, please open an issue on GitHub.
