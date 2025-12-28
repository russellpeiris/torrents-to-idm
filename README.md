# Torrents to IDM

This project allows you to download torrent files and transfer them to Internet Download Manager (IDM) for faster downloads.

## Features
- Download torrent files
- Integrate with IDM for high-speed downloads
- Support for large torrent files
- **AWS deployment support for cost-effective cloud downloading**

## Requirements

### Local Deployment
- Node.js (version 14.0 or higher)
- Internet Download Manager (IDM)

### AWS Deployment (for large torrents)
- AWS Account
- Docker (for building images)
- AWS CLI (for deployment)

## Installation

### Local Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/russellpeiris/torrents-to-idm.git
   cd torrents-to-idm
   ```
2. Install dependencies:
   ```bash
   npm install
   ```

### AWS Deployment (Recommended for Large Torrents)

For downloading large torrent files without using your local machine, you can deploy this on AWS:

**Quick Deploy:**
```bash
./deploy-aws.sh
```

**Cost-Effective Options:**
- **On-Demand Usage** (~$4-5/month if used 8hrs/day): Start only when downloading
- **24/7 Operation** (~$28-30/month): Always available
- **Ultra-Low Cost** (< $5/month): EC2 Spot instances

See [AWS-DEPLOYMENT.md](AWS-DEPLOYMENT.md) for detailed instructions and cost optimization strategies.

**Start/Stop Service to Save Costs:**
```bash
# Start when you need to download
./scripts/start-service.sh

# Stop when done (saves money!)
./scripts/stop-service.sh
```

## Usage

### Local Usage
1. Start the server:
   ```bash
   npm start
   ```
2. Open your browser to `http://localhost:3000`
3. Add a magnet link or .torrent URL
4. Copy the download URLs and paste them into IDM

### AWS Usage
1. Deploy using `./deploy-aws.sh`
2. Access your service at the provided URL (e.g., `http://your-alb-url.amazonaws.com`)
3. Add torrents via the web interface
4. Use the generated HTTP URLs with IDM for high-speed downloads
5. Stop the service when done to avoid charges: `./scripts/stop-service.sh`

### Using with IDM
Once you have the HTTP URL for a file:
1. Copy the URL (e.g., `http://localhost:3000/d/{infoHash}/{fileIndex}/{fileName}`)
2. Open IDM
3. Click "Add URL" or press Ctrl+U
4. Paste the URL and start download
5. IDM will download at maximum speed using HTTP range requests

## Configuration

### Environment Variables
- `PORT` - Server port (default: 3000)
- `NODE_ENV` - Environment (production/development)
- `AWS_REGION` - AWS region for S3 storage (optional)
- `AWS_S3_BUCKET` - S3 bucket for storing downloads (optional)

### Docker Deployment
```bash
# Build and run locally
docker build -t torrents-to-idm .
docker run -p 3000:3000 torrents-to-idm

# Or use docker-compose
docker-compose up
```

## Cost Optimization Tips

If using AWS deployment:

1. **Always stop the service when not downloading** - This is the #1 way to save money
   ```bash
   ./scripts/stop-service.sh
   ```

2. **Use Fargate Spot instances** - Already configured in the CloudFormation template for 70% savings

3. **Clean up old files** - S3 lifecycle policies automatically delete files after 7 days

4. **Monitor your costs** - Set up billing alerts in AWS Console

See [AWS-DEPLOYMENT.md](AWS-DEPLOYMENT.md) for more cost optimization strategies.

## Cleanup

### Remove AWS Resources
To delete all AWS resources and stop all charges:
```bash
./scripts/cleanup-aws.sh
```

## Architecture

- **Local/Docker**: Simple Node.js server using WebTorrent
- **AWS**: ECS Fargate Spot + ALB + S3 (optional) for cost-effective cloud torrenting

## License
MIT
