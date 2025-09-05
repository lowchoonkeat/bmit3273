#!/bin/bash

echo "=== AWS Practical Assessment Grading Script (Student Version) ==="
read -p "Enter your full name (e.g., LowChoonKeat): " STUDENT_NAME

REGION="us-east-1"
lower_name=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]')
lt_name="lt-$lower_name"
asg_name="asg-$lower_name"
alb_name="alb-$lower_name"
tg_name="tg-$lower_name"
bucket_name_prefix="s3-$lower_name"

total_score=0

# --- Task 1: Launch Template ---
lt_check=$(aws ec2 describe-launch-templates --region "$REGION" \
    --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output text 2>/dev/null)
if [ -n "$lt_check" ]; then
  total_score=$((total_score + 10))
  latest_version=$(aws ec2 describe-launch-templates --region "$REGION" \
      --launch-template-names "$lt_name" --query 'LaunchTemplates[0].LatestVersionNumber' --output text 2>/dev/null)
  version_data=$(aws ec2 describe-launch-template-versions \
      --launch-template-name "$lt_name" --versions "$latest_version" --region "$REGION" 2>/dev/null)
  instance_type=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType // empty')
  ami_id=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.ImageId // empty')
  user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')
  [[ "$instance_type" == "t3.micro" ]] && total_score=$((total_score + 10))
  [[ -n "$ami_id" ]] && total_score=$((total_score + 5))
  [[ -n "$user_data" ]] && total_score=$((total_score + 5))
fi

# --- Task 2: ALB + ASG + TG ---
alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text 2>/dev/null)
if [ -n "$alb_arn" ]; then
  total_score=$((total_score + 7))
  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" \
      --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text 2>/dev/null)
  if curl -s "http://$alb_dns" | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    total_score=$((total_score + 7))
  fi
fi
tg_check=$(aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[?TargetGroupName=='$tg_name']" --output text 2>/dev/null)
[[ -n "$tg_check" ]] && total_score=$((total_score + 7))
asg_check=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --query "AutoScalingGroups[?AutoScalingGroupName=='$asg_name']" --output text 2>/dev/null)
if [ -n "$asg_check" ]; then
  total_score=$((total_score + 7))
  config=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
      --auto-scaling-group-names "$asg_name" --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]" --output text 2>/dev/null)
  echo "$config" | grep -q -E "^1\s+3\s+1" && total_score=$((total_score + 7))
fi

# --- Task 3: S3 ---
bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text 2>/dev/null | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)
if [ -n "$bucket_name" ]; then
  total_score=$((total_score + 5))
  website_config=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  [[ -n "$website_config" ]] && total_score=$((total_score + 8))
  index_found=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" \
      --query "Contents[].Key" --output text 2>/dev/null | grep -i index)
  [[ -n "$index_found" ]] && total_score=$((total_score + 7))
  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  if curl -s "$website_url" | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    total_score=$((total_score + 5))
  fi
  bp_check=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  [[ -n "$bp_check" ]] && total_score=$((total_score + 5))
  pab_status=$(aws s3api get-bucket-policy-status --bucket "$bucket_name" --region "$REGION" 2>/dev/null | jq -r '.PolicyStatus.IsPublic')
  [[ "$pab_status" == "true" ]] && total_score=$((total_score + 5))
fi

# --- Final Output ---
echo
echo "============================="
echo "Final Score: $total_score / 100"
echo "============================="
echo "Final Score: $total_score / 100" > grading_report.txt
