#!/bin/bash

# =========================================
# AWS Practical Assessment Grading Script
# =========================================

echo "=== AWS Practical Assessment Grading Script ==="

REPORT_FILE="grading_report.txt"
DETAILS=false

# Check if teacher mode
if [[ "$1" == "--teacher" ]]; then
    DETAILS=true
fi

read -p "Enter your full name (e.g., LowChoonKeat): " name
score=0

echo "" > "$REPORT_FILE"

# ================================
# Task 1: EC2 + Launch Template (30%)
# ================================
lt_name="lt-$name"
lt=$(aws ec2 describe-launch-templates \
  --query "LaunchTemplates[?LaunchTemplateName=='$lt_name'].LaunchTemplateName" \
  --output text 2>/dev/null)

if [[ "$lt" == "$lt_name" ]]; then
    $DETAILS && echo "✅ Launch Template '$lt_name' found (+10)" | tee -a "$REPORT_FILE"
    score=$((score+10))

    lt_details=$(aws ec2 describe-launch-template-versions \
      --launch-template-name "$lt_name" \
      --versions "\$Latest" \
      --query "LaunchTemplateVersions[0]" \
      --output json 2>/dev/null)

    inst_type=$(echo "$lt_details" | jq -r '.LaunchTemplateData.InstanceType')
    ami_id=$(echo "$lt_details" | jq -r '.LaunchTemplateData.ImageId')
    user_data=$(echo "$lt_details" | jq -r '.LaunchTemplateData.UserData')

    if [[ "$inst_type" == "t3.micro" ]]; then
        $DETAILS && echo "✅ Launch Template uses t3.micro (+10)" | tee -a "$REPORT_FILE"
        score=$((score+10))
    else
        $DETAILS && echo "❌ Wrong instance type ($inst_type)" | tee -a "$REPORT_FILE"
    fi

    if [[ "$ami_id" != "null" && -n "$ami_id" ]]; then
        $DETAILS && echo "✅ AMI ImageId set ($ami_id) (+5)" | tee -a "$REPORT_FILE"
        score=$((score+5))
    else
        $DETAILS && echo "❌ AMI ImageId not set" | tee -a "$REPORT_FILE"
    fi

    if [[ "$user_data" != "null" && -n "$user_data" ]]; then
        $DETAILS && echo "✅ Launch Template includes user data (+5)" | tee -a "$REPORT_FILE"
        score=$((score+5))
    else
        $DETAILS && echo "❌ Launch Template missing user data" | tee -a "$REPORT_FILE"
    fi
else
    $DETAILS && echo "❌ Launch Template '$lt_name' not found" | tee -a "$REPORT_FILE"
fi

# ================================
# Task 2: ALB + ASG + TG (35%)
# ================================
alb_name="alb-$name"
tg_name="tg-$name"
asg_name="asg-$name"

# ALB Check
alb=$(aws elbv2 describe-load-balancers \
  --names "$alb_name" \
  --query "LoadBalancers[0].LoadBalancerName" \
  --output text 2>/dev/null)

if [[ "$alb" == "$alb_name" ]]; then
    $DETAILS && echo "✅ ALB '$alb_name' exists (+7)" | tee -a "$REPORT_FILE"
    score=$((score+7))

    alb_dns=$(aws elbv2 describe-load-balancers \
      --names "$alb_name" \
      --query "LoadBalancers[0].DNSName" \
      --output text 2>/dev/null)

    if [[ -n "$alb_dns" ]]; then
        if echo "$alb_dns" | grep -iq "$name"; then
            $DETAILS && echo "✅ ALB DNS shows student name (+7)" | tee -a "$REPORT_FILE"
            score=$((score+7))
        else
            $DETAILS && echo "❌ ALB DNS does not show student name" | tee -a "$REPORT_FILE"
        fi
    fi
else
    $DETAILS && echo "❌ ALB '$alb_name' not found" | tee -a "$REPORT_FILE"
fi

# Target Group
tg=$(aws elbv2 describe-target-groups \
  --names "$tg_name" \
  --query "TargetGroups[0].TargetGroupName" \
  --output text 2>/dev/null)

if [[ "$tg" == "$tg_name" ]]; then
    $DETAILS && echo "✅ Target Group '$tg_name' exists (+7)" | tee -a "$REPORT_FILE"
    score=$((score+7))
else
    $DETAILS && echo "❌ Target Group '$tg_name' not found" | tee -a "$REPORT_FILE"
fi

# ASG
asg=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$asg_name" \
  --query "AutoScalingGroups[0].AutoScalingGroupName" \
  --output text 2>/dev/null)

if [[ "$asg" == "$asg_name" ]]; then
    $DETAILS && echo "✅ ASG '$asg_name' exists (+7)" | tee -a "$REPORT_FILE"
    score=$((score+7))

    min=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$asg_name" \
      --query "AutoScalingGroups[0].MinSize" \
      --output text)
    max=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$asg_name" \
      --query "AutoScalingGroups[0].MaxSize" \
      --output text)
    des=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$asg_name" \
      --query "AutoScalingGroups[0].DesiredCapacity" \
      --output text)

    if [[ "$min" -eq 1 && "$max" -eq 3 && "$des" -eq 1 ]]; then
        $DETAILS && echo "✅ ASG scaling config is correct (1/3/1) (+7)" | tee -a "$REPORT_FILE"
        score=$((score+7))
    else
        $DETAILS && echo "❌ ASG scaling config incorrect (min=$min, max=$max, desired=$des)" | tee -a "$REPORT_FILE"
    fi
else
    $DETAILS && echo "❌ ASG '$asg_name' not found" | tee -a "$REPORT_FILE"
fi

# ================================
# Task 3: S3 Static Website (35%)
# ================================
bucket_name="s3-$name-test"

bucket=$(aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null)
if [[ $? -eq 0 ]]; then
    $DETAILS && echo "✅ S3 bucket '$bucket_name' found (+5)" | tee -a "$REPORT_FILE"
    score=$((score+5))

    website=$(aws s3api get-bucket-website --bucket "$bucket_name" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        $DETAILS && echo "✅ Static website hosting enabled (+8)" | tee -a "$REPORT_FILE"
        score=$((score+8))
    else
        $DETAILS && echo "❌ Static website hosting not enabled" | tee -a "$REPORT_FILE"
    fi

    index_check=$(aws s3api list-objects --bucket "$bucket_name" \
      --query "Contents[].Key" --output text | grep -i "index.html")

    if [[ -n "$index_check" ]]; then
        $DETAILS && echo "✅ index.html uploaded (+7)" | tee -a "$REPORT_FILE"
        score=$((score+7))

        # Try accessing website
        endpoint="http://$bucket_name.s3-website-us-east-1.amazonaws.com"
        content=$(curl -s "$endpoint")
        if echo "$content" | grep -iq "$name"; then
            $DETAILS && echo "✅ S3 site accessible (+5)" | tee -a "$REPORT_FILE"
            score=$((score+5))
        else
            $DETAILS && echo "❌ S3 page does not show student name" | tee -a "$REPORT_FILE"
        fi
    else
        $DETAILS && echo "❌ index.html missing" | tee -a "$REPORT_FILE"
    fi

    policy=$(aws s3api get-bucket-policy --bucket "$bucket_name" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        $DETAILS && echo "✅ Bucket policy configured (+5)" | tee -a "$REPORT_FILE"
        score=$((score+5))
    else
        $DETAILS && echo "❌ No bucket policy found" | tee -a "$REPORT_FILE"
    fi

    pab=$(aws s3api get-bucket-policy-status --bucket "$bucket_name" \
      --query "PolicyStatus.IsPublic" --output text 2>/dev/null)

    if [[ "$pab" == "True" ]]; then
        $DETAILS && echo "✅ Public access block disabled (+5)" | tee -a "$REPORT_FILE"
        score=$((score+5))
    else
        $DETAILS && echo "❌ Public access block still enabled" | tee -a "$REPORT_FILE"
    fi
else
    $DETAILS && echo "❌ Bucket '$bucket_name' not found" | tee -a "$REPORT_FILE"
fi

# ================================
# Final Report
# ================================
echo ""
echo "============================="
echo "Final Score: $score / 100"
echo "============================="

if $DETAILS; then
    echo "" >> "$REPORT_FILE"
    echo "Detailed Breakdown:" >> "$REPORT_FILE"
    cat "$REPORT_FILE"
fi

