#!/bin/bash

# AWS Cost Calculator for Torrents to IDM
# Helps estimate monthly costs based on usage patterns

# Check if bc is installed
if ! command -v bc &> /dev/null; then
    echo "Error: 'bc' command not found. Please install it first."
    echo "  Ubuntu/Debian: sudo apt-get install bc"
    echo "  macOS: brew install bc"
    echo "  RHEL/CentOS: sudo yum install bc"
    exit 1
fi

echo "💰 AWS Cost Calculator for Torrents to IDM"
echo "==========================================="
echo ""

# Pricing (as of 2024, US East 1 region)
FARGATE_SPOT_VCPU_HOUR=0.01334053  # per vCPU-hour
FARGATE_SPOT_MEMORY_HOUR=0.00146489  # per GB-hour
ALB_HOUR=0.0225  # per hour
ALB_LCU=0.008  # per LCU-hour (minimal usage: 1 LCU)
S3_STORAGE_GB=0.023  # per GB-month
S3_REQUESTS_1000=0.0004  # per 1000 PUT requests

# Configuration
VCPU=0.5
MEMORY_GB=1

echo "Fargate Spot Configuration:"
echo "  - vCPU: $VCPU"
echo "  - Memory: ${MEMORY_GB}GB"
echo ""

# Function to calculate costs
calculate_cost() {
    local hours_per_day=$1
    local days_per_month=$2
    local total_hours=$(echo "$hours_per_day * $days_per_month" | bc)
    
    local fargate_vcpu=$(echo "$FARGATE_SPOT_VCPU_HOUR * $VCPU * $total_hours" | bc)
    local fargate_memory=$(echo "$FARGATE_SPOT_MEMORY_HOUR * $MEMORY_GB * $total_hours" | bc)
    local fargate_total=$(echo "$fargate_vcpu + $fargate_memory" | bc)
    
    local alb_cost=$(echo "$ALB_HOUR * $total_hours + $ALB_LCU * $total_hours" | bc)
    
    local total=$(echo "$fargate_total + $alb_cost" | bc)
    
    echo "$total"
}

echo "Usage Scenarios:"
echo "----------------"
echo ""

# Scenario 1: Heavy user (24/7)
echo "1. Always Running (24/7):"
COST_247=$(calculate_cost 24 30)
printf "   Hours/month: 720\n"
printf "   Cost: \$%.2f/month\n" $COST_247
echo "   + S3 Storage (100GB): \$2.30/month"
printf "   Total: \$%.2f/month\n" $(echo "$COST_247 + 2.30" | bc)
echo ""

# Scenario 2: Moderate user (8 hours/day)
echo "2. Daily Use (8 hours/day):"
COST_8H=$(calculate_cost 8 30)
printf "   Hours/month: 240\n"
printf "   Cost: \$%.2f/month\n" $COST_8H
echo "   + S3 Storage (50GB): \$1.15/month"
printf "   Total: \$%.2f/month\n" $(echo "$COST_8H + 1.15" | bc)
echo ""

# Scenario 3: Light user (4 hours/day)
echo "3. Light Use (4 hours/day):"
COST_4H=$(calculate_cost 4 30)
printf "   Hours/month: 120\n"
printf "   Cost: \$%.2f/month\n" $COST_4H
echo "   + S3 Storage (20GB): \$0.46/month"
printf "   Total: \$%.2f/month\n" $(echo "$COST_4H + 0.46" | bc)
echo ""

# Scenario 4: Occasional user
echo "4. Occasional Use (10 hours/month):"
COST_OCC=$(calculate_cost 10 1)
printf "   Hours/month: 10\n"
printf "   Cost: \$%.2f/month\n" $COST_OCC
echo "   + S3 Storage (10GB): \$0.23/month"
printf "   Total: \$%.2f/month\n" $(echo "$COST_OCC + 0.23" | bc)
echo ""

# Scenario 5: Ultra-low cost (EC2 Spot)
echo "5. EC2 t3.micro Spot (24/7):"
EC2_SPOT=0.003  # per hour
EC2_COST=$(echo "$EC2_SPOT * 720" | bc)
printf "   Hours/month: 720\n"
printf "   Cost: \$%.2f/month\n" $EC2_COST
echo "   + S3 Storage (100GB): \$2.30/month"
printf "   Total: \$%.2f/month\n" $(echo "$EC2_COST + 2.30" | bc)
echo "   (No ALB needed with EC2)"
echo ""

echo "💡 Cost Saving Tips:"
echo "-------------------"
echo "1. ALWAYS stop the service when not downloading"
echo "2. Use the on-demand approach (start/stop as needed)"
echo "3. Enable S3 lifecycle policies to auto-delete old files"
echo "4. Consider EC2 Spot for ultra-low cost (~\$4.50/month)"
echo "5. Set up billing alerts to avoid surprises"
echo ""

echo "📊 Cost Breakdown:"
echo "Fargate Spot: \$$(echo "$FARGATE_SPOT_VCPU_HOUR * $VCPU + $FARGATE_SPOT_MEMORY_HOUR * $MEMORY_GB" | bc)/hour"
echo "ALB: \$$(echo "$ALB_HOUR + $ALB_LCU" | bc)/hour"
echo "S3: \$0.023/GB/month"
echo ""

echo "🎯 Recommended: Use Scenario 2 or 4 for best cost/convenience balance"
