#!/bin/bash

echo "=== AWS Practical Assessment Grading Script ==="
read -p "Enter your full name (e.g., Low Choon Keat): " STUDENT_NAME

REGION="us-east-1"
lower_name=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
lt_name="lt-$lower_name"
asg_name="asg-$lower_name"
alb_name="alb-$lower_name"
tg_name="tg-$lower_name"
bucket_name_prefix="s3-$lower_name"

total_score=0
details=()

# Prepare name variations for checking
name_nospaces=$(echo "$STUDENT_NAME" | tr -d '[:space:]')
name_lower=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]')
name_lower_nospaces=$(echo "$name_nospaces" | tr '[:upper:]' '[:lower:]')

#############################################
# Task 1: EC2 + Launch Template (30%)
#############################################
lt_check=$(aws ec2 describe-launch-templates --region "$REGION" \
  --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output text 2>/dev/null)

if [ -n "$lt_check" ]; then
  details+=("✅ Launch Template '$lt_name' found (+10)")
  total_score=$((total_score + 10))

  latest_version=$(aws ec2 describe-launch-templates --region "$REGION" \
      --launch-template-names "$lt_name" \
      --query 'LaunchTemplates[0].LatestVersionNumber' --output text)

  version_data=$(aws ec2 describe-launch-template-versions \
      --launch-template-name "$lt_name" \
      --versions "$latest_version" \
      --region "$REGION")

  instance_type=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType // empty')
  ami_id=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.ImageId // empty')
  user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')

  if [[ "$instance_type" == "t3.micro" ]]; then
    details+=("✅ Launch Template uses t3.micro (+10)")
    total_score=$((total_score + 10))
  else
    details+=("❌ Launch Template is not t3.micro (found: $instance_type)")
  fi

  if [[ -n "$ami_id" ]]; then
    details+=("✅ AMI ImageId set ($ami_id) (+5)")
    total_score=$((total_score + 5))
  else
    details+=("❌ No AMI ImageId in template")
  fi

  if [[ -n "$user_data" ]]; then
    details+=("✅ Launch Template includes user data (+5)")
    total_score=$((total_score + 5))
  else
    details+=("❌ Launch Template missing user data")
  fi
else
  details+=("❌ Launch Template '$lt_name' NOT found")
fi

#############################################
# Task 2: ALB + ASG + TG (35%)
#############################################
alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text 2>/dev/null)

if [ -n "$alb_arn" ]; then
  details+=("✅ ALB '$alb_name' exists (+7)")
  total_score=$((total_score + 7))

  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text)

  page=$(curl -s "http://$alb_dns")
  if echo "$page" | grep -iqE "($name_nospaces|$STUDENT_NAME)"; then
    details+=("✅ ALB DNS shows student name (+7)")
    total_score=$((total_score + 7))
  else
    details+=("❌ ALB DNS does not show student name")
  fi
else
  details+=("❌ ALB '$alb_name' not found")
fi

tg_check=$(aws elbv2 describe-target-groups --region "$REGION" \
  --query "TargetGroups[?TargetGroupName=='$tg_name']" --output text 2>/dev/null)
if [ -n "$tg_check" ]; then
  details+=("✅ Target Group '$tg_name' exists (+7)")
  total_score=$((total_score + 7))
else
  details+=("❌ Target Group '$tg_name' not found")
fi

asg_check=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
  --query "AutoScalingGroups[?AutoScalingGroupName=='$asg_name']" --output text 2>/dev/null)
if [ -n "$asg_check" ]; then
  details+=("✅ ASG '$asg_name' exists (+7)")
  total_score=$((total_score + 7))

  config=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --auto-scaling-group-names "$asg_name" \
    --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]" --output text)

  if echo "$config" | grep -q -E "^1\s+3\s+1"; then
    details+=("✅ ASG scaling config is correct (1/3/1) (+7)")
    total_score=$((total_score + 7))
  else
    details+=("❌ ASG scaling config not correct")
  fi
else
  details+=("❌ ASG '$asg_name' not found")
fi

#############################################
# Task 3: S3 Static Website (35%)
#############################################
bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text \
  | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)

if [ -n "$bucket_name" ]; then
  details+=("✅ S3 bucket '$bucket_name' found (+5)")
  total_score=$((total_score + 5))

  website_config=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$website_config" ]; then
    details+=("✅ Static website hosting enabled (+8)")
    total_score=$((total_score + 8))
  else
    details+=("❌ Static website hosting not enabled")
  fi

  index_found=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" \
    --query "Contents[].Key" --output text | grep -i index)
  if [ -n "$index_found" ]; then
    details+=("✅ index.html uploaded (+7)")
    total_score=$((total_score + 7))
  else
    details+=("❌ index.html not found")
  fi

  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  page=$(curl -s "$website_url")
  if echo "$page" | grep -iqE "($name_nospaces|$STUDENT_NAME)"; then
    details+=("✅ S3 page shows student name (+5)")
    total_score=$((total_score + 5))
  elif [ -n "$page" ]; then
    details+=("✅ S3 site accessible (+5)")
    total_score=$((total_score + 5))
  else
    details+=("❌ S3 site not accessible")
  fi

  bp_check=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$bp_check" ]; then
    details+=("✅ Bucket policy configured (+5)")
    total_score=$((total_score + 5))
  else
    details+=("❌ No bucket policy found")
  fi

  pab_status=$(aws s3api get-bucket-policy-status --bucket "$bucket_name" \
    --region "$REGION" 2>/dev/null | jq -r '.PolicyStatus.IsPublic')
  if [ "$pab_status" = "true" ]; then
    details+=("✅ Public access block disabled (+5)")
    total_score=$((total_score + 5))
  else
    details+=("❌ Public access block still enabled")
  fi
else
  details+=("❌ S3 bucket not found")
fi

#############################################
# Final Score
#############################################
echo
echo "============================="
echo "Final Score: $total_score / 100"
echo "============================="

if [[ "$1" == "--teacher" ]]; then
  echo
  echo "Detailed Breakdown:"
  for d in "${details[@]}"; do
    echo "$d"
  done
fi

echo "Final Score: $total_score / 100" > grading_report.txt
