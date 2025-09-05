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
details=""

# --- Task 1: Launch Template ---
lt_check=$(aws ec2 describe-launch-templates --region "$REGION" \
    --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output text 2>/dev/null)

if [ -n "$lt_check" ]; then
  total_score=$((total_score + 10))
  details+="✅ Launch Template '$lt_name' found (+10)\n"
  latest_version=$(aws ec2 describe-launch-templates --region "$REGION" \
      --launch-template-names "$lt_name" --query 'LaunchTemplates[0].LatestVersionNumber' --output text 2>/dev/null)
  version_data=$(aws ec2 describe-launch-template-versions \
      --launch-template-name "$lt_name" --versions "$latest_version" --region "$REGION" 2>/dev/null)

  instance_type=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType // empty')
  ami_id=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.ImageId // empty')
  user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')

  if [[ "$instance_type" == "t3.micro" ]]; then
    total_score=$((total_score + 10))
    details+="✅ Launch Template uses t3.micro (+10)\n"
  else
    details+="❌ Wrong instance type\n"
  fi

  if [[ -n "$ami_id" ]]; then
    total_score=$((total_score + 5))
    details+="✅ AMI ImageId set ($ami_id) (+5)\n"
  else
    details+="❌ No AMI configured\n"
  fi

  if [[ -n "$user_data" ]]; then
    total_score=$((total_score + 5))
    details+="✅ Launch Template includes user data (+5)\n"
  else
    details+="❌ No user data in Launch Template\n"
  fi
else
  details+="❌ Launch Template '$lt_name' not found\n"
fi

# --- Task 2: ALB + ASG + TG ---
alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text 2>/dev/null)

if [ -n "$alb_arn" ]; then
  total_score=$((total_score + 7))
  details+="✅ ALB '$alb_name' exists (+7)\n"
  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" \
      --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text 2>/dev/null)
  if curl -s "http://$alb_dns" | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    total_score=$((total_score + 7))
    details+="✅ ALB DNS shows student name (+7)\n"
  else
    details+="❌ ALB DNS does not show student name\n"
  fi
else
  details+="❌ ALB '$alb_name' not found\n"
fi

tg_check=$(aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[?TargetGroupName=='$tg_name']" --output text 2>/dev/null)
if [ -n "$tg_check" ]; then
  total_score=$((total_score + 7))
  details+="✅ Target Group '$tg_name' exists (+7)\n"
else
  details+="❌ Target Group '$tg_name' not found\n"
fi

asg_check=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
    --query "AutoScalingGroups[?AutoScalingGroupName=='$asg_name']" --output text 2>/dev/null)
if [ -n "$asg_check" ]; then
  total_score=$((total_score + 7))
  details+="✅ ASG '$asg_name' exists (+7)\n"
  config=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
      --auto-scaling-group-names "$asg_name" --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]" --output text 2>/dev/null)
  if echo "$config" | grep -q -E "^1\s+3\s+1"; then
    total_score=$((total_score + 7))
    details+="✅ ASG scaling config is correct (1/3/1) (+7)\n"
  else
    details+="❌ ASG scaling config incorrect\n"
  fi
else
  details+="❌ ASG '$asg_name' not found\n"
fi

# --- Task 3: S3 ---
bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text 2>/dev/null | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)
if [ -n "$bucket_name" ]; then
  total_score=$((total_score + 5))
  details+="✅ S3 bucket '$bucket_name' found (+5)\n"
  website_config=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$website_config" ]; then
    total_score=$((total_score + 8))
    details+="✅ Static website hosting enabled (+8)\n"
  else
    details+="❌ Static website hosting not enabled\n"
  fi
  index_found=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" \
      --query "Contents[].Key" --output text 2>/dev/null | grep -i index)
  if [ -n "$index_found" ]; then
    total_score=$((total_score + 7))
    details+="✅ index.html uploaded (+7)\n"
  else
    details+="❌ index.html missing\n"
  fi
  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  if curl -s "$website_url" | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    total_score=$((total_score + 5))
    details+="✅ S3 page shows student name (+5)\n"
  else
    details+="❌ S3 page does not show student name\n"
  fi
  bp_check=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$bp_check" ]; then
    total_score=$((total_score + 5))
    details+="✅ Bucket policy configured (+5)\n"
  else
    details+="❌ No bucket policy found\n"
  fi
  pab_status=$(aws s3api get-bucket-policy-status --bucket "$bucket_name" --region "$REGION" 2>/dev/null | jq -r '.PolicyStatus.IsPublic')
  if [ "$pab_status" == "true" ]; then
    total_score=$((total_score + 5))
    details+="✅ Public access block disabled (+5)\n"
  else
    details+="❌ Public access block not disabled\n"
  fi
else
  details+="❌ S3 bucket '$bucket_name_prefix' not found\n"
fi

# --- Final Output ---
echo
echo "============================="
echo "Final Score: $total_score / 100"
echo "============================="

if [[ "$1" == "--teacher" ]]; then
  echo -e "\nDetailed Breakdown:"
  echo -e "$details"
fi

echo "Final Score: $total_score / 100" > grading_report.txt
[[ "$1" == "--teacher" ]] && echo -e "$details" >> grading_report.txt
