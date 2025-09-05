#!/bin/bash

echo "=== AWS Practical Assessment Grading Script ==="
read -p "Enter your full name (e.g., LowChoonKeat): " STUDENT_NAME

REGION="us-east-1"
lower_name=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]')
lt_name="lt-$lower_name"
asg_name="asg-$lower_name"
alb_name="alb-$lower_name"
tg_name="tg-$lower_name"
bucket_name_prefix="s3-$lower_name"

total_score=0

#############################################
# Task 1: EC2 and Launch Template (30%)
#############################################
echo
echo "[Task 1: EC2 + Launch Template (30%)]"

lt_check=$(aws ec2 describe-launch-templates --region "$REGION" \
  --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output text 2>/dev/null)

if [ -n "$lt_check" ]; then
  echo "✅ Launch Template '$lt_name' found"
  total_score=$((total_score + 10))

  latest_version=$(aws ec2 describe-launch-templates \
      --region "$REGION" \
      --launch-template-names "$lt_name" \
      --query 'LaunchTemplates[0].LatestVersionNumber' \
      --output text)

  version_data=$(aws ec2 describe-launch-template-versions \
      --launch-template-name "$lt_name" \
      --versions "$latest_version" \
      --region "$REGION")

  instance_type=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType // empty')
  image_id=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.ImageId // empty')
  user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')

  # Check instance type
  if [[ "$instance_type" == "t3.micro" ]]; then
    echo "✅ Launch Template uses t3.micro"
    total_score=$((total_score + 10))
  else
    echo "❌ Launch Template is not t3.micro (found: $instance_type)"
  fi

  # Check AMI
  if [[ -n "$image_id" && "$image_id" != "null" ]]; then
    echo "✅ AMI ImageId set ($image_id)"
    total_score=$((total_score + 5))
  else
    echo "❌ No AMI ImageId specified"
  fi

  # Check user data
  if [[ -n "$user_data" && "$user_data" != "null" ]]; then
    echo "✅ Launch Template includes user data"
    total_score=$((total_score + 5))
  else
    echo "❌ Launch Template missing user data"
  fi
else
  echo "❌ Launch Template '$lt_name' NOT found"
fi

#############################################
# Task 2: ALB + ASG + TG (35%)
#############################################
echo
echo "[Task 2: ALB + ASG + TG (35%)]"

alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text 2>/dev/null)

if [ -n "$alb_arn" ]; then
  echo "✅ ALB '$alb_name' exists"
  total_score=$((total_score + 7))

  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text 2>/dev/null)

  if curl -s "http://$alb_dns" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    echo "✅ ALB DNS shows student name"
    total_score=$((total_score + 7))
  else
    echo "❌ ALB DNS does not show student name"
  fi
else
  echo "❌ ALB '$alb_name' not found"
fi

tg_check=$(aws elbv2 describe-target-groups --region "$REGION" \
  --query "TargetGroups[?TargetGroupName=='$tg_name']" --output text 2>/dev/null)
if [ -n "$tg_check" ]; then
  echo "✅ Target Group '$tg_name' exists"
  total_score=$((total_score + 7))
else
  echo "❌ Target Group '$tg_name' not found"
fi

asg_check=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
  --query "AutoScalingGroups[?AutoScalingGroupName=='$asg_name']" --output text 2>/dev/null)
if [ -n "$asg_check" ]; then
  echo "✅ ASG '$asg_name' exists"
  total_score=$((total_score + 7))

  config=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --auto-scaling-group-names "$asg_name" \
    --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]" --output text)

  if echo "$config" | grep -q -E "^1\s+3\s+1"; then
    echo "✅ ASG scaling config is correct (1/3/1)"
    total_score=$((total_score + 7))
  else
    echo "❌ ASG scaling config not correct"
  fi
else
  echo "❌ ASG '$asg_name' not found"
fi

#############################################
# Task 3: S3 Static Website (35%)
#############################################
echo
echo "[Task 3: S3 Static Website (35%)]"

bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text \
  | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)

if [ -n "$bucket_name" ]; then
  echo "✅ S3 bucket '$bucket_name' found"
  total_score=$((total_score + 5))

  website_config=$(aws s3api get-bucket-website --bucket "$bucket_name" \
    --region "$REGION" 2>/dev/null)
  if [ -n "$website_config" ]; then
    echo "✅ Static website hosting enabled"
    total_score=$((total_score + 8))
  else
    echo "❌ Static website hosting not enabled"
  fi

  index_found=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" \
    --query "Contents[].Key" --output text | grep -i index)
  if [ -n "$index_found" ]; then
    echo "✅ index.html uploaded"
    total_score=$((total_score + 7))
  else
    echo "❌ index.html not found"
  fi

  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  if curl -s "$website_url" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    echo "✅ S3 page shows student name"
    total_score=$((total_score + 5))
  elif curl -s "$website_url" > /dev/null; then
    echo "✅ S3 site accessible"
    total_score=$((total_score + 5))
  else
    echo "❌ S3 site not accessible"
  fi

  # Bucket policy check
  bp_check=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null | jq -r '.Policy')
  if [ -n "$bp_check" ] && echo "$bp_check" | grep -q '"Effect":"Allow"'; then
    echo "✅ Bucket policy allows public read"
    total_score=$((total_score + 5))
  elif [ -n "$bp_check" ]; then
    echo "⚠️ Bucket policy exists but may be restrictive (+3)"
    total_score=$((total_score + 3))
  else
    echo "❌ No bucket policy found"
  fi

  # Public access block check
  pab_check=$(aws s3api get-bucket-public-access-block --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$pab_check" ]; then
    block_all=$(echo "$pab_check" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls')
    ignore_acl=$(echo "$pab_check" | jq -r '.PublicAccessBlockConfiguration.IgnorePublicAcls')
    block_policy=$(echo "$pab_check" | jq -r '.PublicAccessBlockConfiguration.BlockPublicPolicy')
    restrict_bucket=$(echo "$pab_check" | jq -r '.PublicAccessBlockConfiguration.RestrictPublicBuckets')

    if [ "$block_all" = "false" ] && [ "$ignore_acl" = "false" ] && [ "$block_policy" = "false" ] && [ "$restrict_bucket" = "false" ]; then
      echo "✅ Public access block disabled"
      total_score=$((total_score + 5))
    else
      echo "❌ Some Public Access Block settings still enabled"
    fi
  else
    echo "⚠️ Could not retrieve Public Access Block configuration"
  fi
else
  echo "❌ S3 bucket not found"
fi

#############################################
# Final Score
#############################################
echo
echo "============================="
echo "Final Score: $total_score / 100"
echo "============================="
echo "Final Score: $total_score / 100" > grading_report.txt
echo "Report saved as: grading_report.txt"
