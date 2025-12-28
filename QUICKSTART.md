# Quick Start Guide - Torrents to IDM

Choose the deployment option that best fits your needs:

## Option 1: Local Deployment (Free, but uses your machine)

**Best for:** Testing, small files, or if you have a good internet connection

```bash
# Install and run
git clone https://github.com/russellpeiris/torrents-to-idm.git
cd torrents-to-idm
npm install
npm start
```

Access at: `http://localhost:3000`

**Pros:** Free, instant setup
**Cons:** Uses your bandwidth and machine resources

---

## Option 2: AWS ECS Fargate Spot (Recommended for large torrents)

**Best for:** Large files, don't want to use your own bandwidth
**Cost:** ~$4-5/month (if used 8 hrs/day) or ~$28-30/month (24/7)

```bash
# One-time setup (5-10 minutes)
./deploy-aws.sh

# Start when you need to download
./scripts/start-service.sh

# Stop when done (IMPORTANT for saving money!)
./scripts/stop-service.sh
```

**Pros:** 
- High-speed AWS network
- No bandwidth usage on your connection
- Easy start/stop to control costs
- Automatic S3 cleanup

**Cons:** 
- Costs money (but minimal if managed well)
- Requires AWS account

---

## Option 3: AWS EC2 Spot Instance (Ultra-low cost)

**Best for:** Maximum cost savings, comfortable with basic AWS
**Cost:** ~$2-5/month (24/7)

```bash
# Launch EC2 instance with user data script
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.micro \
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"MaxPrice":"0.01"}}' \
  --user-data file://ec2-user-data.sh \
  --security-group-ids sg-xxx \
  --key-name your-key

# Or use AWS Console and paste ec2-user-data.sh into User Data field
```

**Pros:** 
- Cheapest option (~$2-5/month)
- Simple setup
- No ALB costs

**Cons:** 
- Spot instances can be terminated (rare for t3.micro)
- Need to manage EC2 directly
- Static IP not guaranteed

---

## Usage Flow

1. **Add a torrent:**
   - Go to your service URL
   - Paste magnet link or .torrent URL
   - Wait for it to connect

2. **Download with IDM:**
   - Click on file you want
   - Copy the HTTP URL
   - Open IDM → Add URL
   - Paste and download at full speed!

3. **Save money (AWS deployments):**
   - Stop service when done: `./scripts/stop-service.sh`
   - Restart when needed: `./scripts/start-service.sh`

---

## Cost Comparison

| Deployment | Setup Time | Monthly Cost | When to Use |
|------------|------------|--------------|-------------|
| Local | 1 min | $0 | Testing, small files |
| AWS Fargate (on-demand) | 10 min | $4-5 | Regular use, large files |
| AWS Fargate (24/7) | 10 min | $28-30 | Always available |
| AWS EC2 Spot | 5 min | $2-5 | Ultra-low cost, 24/7 |

---

## Cost Optimization Tips

### 1. Use Start/Stop Scripts (Fargate)
```bash
# Only run when downloading
./scripts/start-service.sh    # Start
# ... download your files ...
./scripts/stop-service.sh     # Stop
```

**Savings:** Reduces cost from $28/month to $4-5/month or less!

### 2. Set Up Billing Alerts
```bash
# Get notified if costs exceed $10
aws cloudwatch put-metric-alarm \
  --alarm-name torrents-cost-alert \
  --alarm-description "Alert when costs exceed $10" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold
```

### 3. Clean Up When Done
```bash
# Remove all AWS resources
./scripts/cleanup-aws.sh
```

### 4. Use S3 Lifecycle (Already Configured)
- Files automatically deleted after 7 days
- Edit `cloudformation-template.yml` to change retention

---

## Troubleshooting

### "Service won't start"
```bash
# Check logs
aws logs tail /ecs/torrents-to-idm --follow

# Or for EC2
ssh ec2-user@your-instance
/home/ec2-user/check-status.sh
```

### "Costs are too high"
```bash
# Check if service is running
aws ecs describe-services \
  --cluster torrents-to-idm-cluster \
  --services torrents-to-idm-service

# Stop immediately
./scripts/stop-service.sh
```

### "Can't connect to service"
```bash
# Fargate: Get URL
aws cloudformation describe-stacks \
  --stack-name torrents-to-idm-stack \
  --query 'Stacks[0].Outputs'

# EC2: Get public IP
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=torrents-to-idm" \
  --query 'Reservations[0].Instances[0].PublicIpAddress'
```

---

## Next Steps

1. **Check estimated costs:** `./scripts/cost-calculator.sh`
2. **Deploy:** Choose your option above
3. **Test:** Add a small torrent first
4. **Download:** Use IDM with the HTTP URLs
5. **Save money:** Stop service when done!

For detailed information, see:
- [AWS-DEPLOYMENT.md](AWS-DEPLOYMENT.md) - Complete AWS guide
- [README.md](README.md) - Full documentation

---

## Support

- Issues: https://github.com/russellpeiris/torrents-to-idm/issues
- Questions: Open a GitHub Discussion

**Remember:** Always stop AWS services when not in use to save money! 💰
