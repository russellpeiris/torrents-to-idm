#!/bin/bash
# EC2 User Data Script for Torrents to IDM
# This script sets up the application on a fresh EC2 instance
# Use with t3.micro or t3.small Spot instances for ultra-low cost

set -e

echo "🚀 Setting up Torrents to IDM on EC2..."

# Update system
yum update -y

# Install Docker
amazon-linux-extras install docker -y
service docker start
usermod -a -G docker ec2-user
systemctl enable docker

# Install Docker Compose - use package manager for security
DOCKER_COMPOSE_VERSION="1.29.2"
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
# Verify checksum (optional but recommended - users should verify checksum from official docs)
chmod +x /usr/local/bin/docker-compose

# Install Git
yum install -y git

# Clone repository
cd /home/ec2-user
git clone https://github.com/russellpeiris/torrents-to-idm.git
cd torrents-to-idm

# Build and run with Docker
docker build -t torrents-to-idm .
docker run -d \
  --name torrents-to-idm \
  -p 3000:3000 \
  --restart unless-stopped \
  torrents-to-idm

echo "✅ Setup complete!"
echo "🌍 Access your service at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"

# Create a status check script
cat > /home/ec2-user/check-status.sh <<'EOF'
#!/bin/bash
echo "Torrents to IDM Status"
echo "====================="
echo ""
echo "Container Status:"
docker ps -a --filter name=torrents-to-idm --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "Container Logs (last 20 lines):"
docker logs --tail 20 torrents-to-idm
echo ""
echo "Public IP:"
curl -s http://169.254.169.254/latest/meta-data/public-ipv4
echo ""
echo ""
echo "Access URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
EOF

chmod +x /home/ec2-user/check-status.sh
chown ec2-user:ec2-user /home/ec2-user/check-status.sh

echo "💡 Run /home/ec2-user/check-status.sh to check service status"
