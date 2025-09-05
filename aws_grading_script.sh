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
report="grading_report.txt"
echo "" > $report

#############################################
# Helper function for error handling
#############################################
run_aws() {
  # Run AWS CLI, return 1 if AccessDenied/Unauthorized
  output=$(eval "$1" 2>&1)
  if echo "$output" | grep -q -E "AccessDenied|UnauthorizedOperation"; then
    echo "PERMISSION_DENIED"
  else
    echo "$output"
  fi
}

log() {
  echo "$1"
  echo "$1" >> $report
}

#############################################
# Task 1: EC2 + Launch Template (30%)
#############################################
echo
log "[Task 1: EC2 + Launch Template (30%)]"

lt_check=$(run_aws "aws ec2 describe-launch-templates --region $REGION --query \"LaunchTemplates[?LaunchTemplateName=='$lt_name']\" --output text")

if [[ "$lt_check" == "PERMISSION_DENIED" ]]; then
  log "⚠️ No permission to check Launch Template (0 marks)"
else
  if [ -n "$lt_check" ]; then
    log "✅ Launch Template '$lt_name' found (+10)"
    total_score=$((total_score + 10))

    latest_version=$(aws ec2 describe-launch-templates \
        --region "$REGION" \
        --launch-template-names "$lt_name" \
        --query 'LaunchTemplates[0].LatestVersionNumber' \
        --output text 2>/dev/null)

    version_data=$(aws ec2 describe-launch-template-versions \
        --launch-template-name "$lt_name" \
        --versions "$latest_version" \
        --region "$REGION" 2>/dev/null)

    instance_type=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType // empty')
    user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty' | base64 --decode 2>/dev/null)

    if [[ "$instance_type" == "t3.micro" ]]; then
      log "✅ Launch Template uses t3.micro (+10)"
      total_score=$((total_score + 10))
    else
      log "❌ Launch Template is not t3.micro (found: $instance_type)"
    fi

    if [[ -n "$user_data" ]]; then
      if echo "$user_data" | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
        log "✅ User data includes student name (+10)"
        total_score=$((total_score + 10))
      else
        log "⚠️ User data found but missing student name (+7)"
        total_score=$((total_score + 7))
      fi
    else
      log "❌ Launch Template missing user data"
    fi
  else
    log "❌ Launch Template '$lt_name' NOT found"
  fi
fi

#############################################
# Task 2: ALB + ASG + TG (35%)
#############################################
echo
log "[Task 2: ALB + ASG + TG (35%)]"

alb_arn=$(run_aws "aws elbv2 describe-load-balancers --region $REGION --query \"LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn\" --output text")
if [[ "$alb_arn" == "PERMISSION_DENIED" ]]; then
  log "⚠️ No permission to check ALB (0 marks)"
else
  if [ -n "$alb_arn" ]; then
    log "✅ ALB '$alb_name' exists (+7)"
    total_score=$((total_score + 7))

    alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text 2>/dev/null)
    if curl -s "http://$alb_dns" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
      log "✅ ALB DNS shows student name (+7)"
      total_score=$((total_score + 7))
    else
      log "❌ ALB DNS does not show student name"
    fi
  else
    log "❌ ALB '$alb_name' not found"
  fi
fi

tg_check=$(run_aws "aws elbv2 describe-target-groups --region $REGION --query \"TargetGroups[?TargetGroupName=='$tg_name']\" --output text")
if [[ "$tg_check" == "PERMISSION_DENIED" ]]; then
  log "⚠️ No permission to check Target Group (0 marks)"
else
  if [ -n "$tg_check" ]; then
    log "✅ Target Group '$tg_name' exists (+7)"
    total_score=$((total_score + 7))
  else
    log "❌ Target Group '$tg_name' not found"
  fi
fi

asg_check=$(run_aws "aws autoscaling describe-auto-scaling-groups --region $REGION --query \"AutoScalingGroups[?AutoScalingGroupName=='$asg_name']\" --output text")
if [[ "$asg_check" == "PERMISSION_DENIED" ]]; then
  log "⚠️ No permission to check ASG (0 marks)"
else
  if [ -n "$asg_check" ]; then
    log "✅ ASG '$asg_name' exists (+7)"
    total_score=$((total_score + 7))

    config=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$asg_name" --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]" --output text 2>/dev/null)
    if echo "$config" | grep -q -E "^1\s+3\s+1"; then
      log "✅ ASG scaling config is correct (1/3/1) (+7)"
      total_score=$((total_score + 7))
    else
      log "❌ ASG scaling config not correct"
    fi
  else
    log "❌ ASG '$asg_name' not found"
  fi
fi

#############################################
# Task 3: S3 Static Website (35%)
#############################################
echo
log "[Task 3: S3 Static Website (35%)]"

bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text 2>/dev/null | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)

if [ -n "$bucket_name" ]; then
  log "✅ S3 bucket '$bucket_name' found (+5)"
  total_score=$((total_score + 5))

  website_config=$(run_aws "aws s3api get-bucket-website --bucket $bucket_name --region $REGION")
  if [[ "$website_config" == "PERMISSION_DENIED" ]]; then
    log "⚠️ No permission to check static website hosting (0 marks)"
  elif [ -n "$website_config" ]; then
    log "✅ Static website hosting enabled (+8)"
    total_score=$((total_score + 8))
  else
    log "❌ Static website hosting not enabled"
  fi

  index_found=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" --query "Contents[].Key" --output text 2>/dev/null | grep -i index)
  if [ -n "$index_found" ]; then
    page_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
    if curl -s "$page_url" | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
      log "✅ index.html uploaded with student name (+7)"
      total_score=$((total_score + 7))
    else
      log "⚠️ index.html uploaded but missing student name (+5)"
      total_score=$((total_score + 5))
    fi
  else
    log "❌ index.html not found"
  fi

  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  if curl -s "$website_url" | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    log "✅ S3 page shows student name (+5)"
    total_score=$((total_score + 5))
  elif curl -s "$website_url" > /dev/null; then
    log "✅ S3 site accessible (+3)"
    total_score=$((total_score + 3))
  else
    log "❌ S3 site not accessible"
  fi

  bp_check=$(run_aws "aws s3api get-bucket-policy --bucket $bucket_name --region $REGION")
  if [[ "$bp_check" == "PERMISSION_DENIED" ]]; then
    log "⚠️ No permission to check bucket policy (0 marks)"
  elif [[ "$bp_check" == *"\"Effect\":\"Allow\""* ]]; then
    log "✅ Bucket policy allows public read (+5)"
    total_score=$((total_score + 5))
  elif [ -n "$bp_check" ]; then
    log "⚠️ Bucket policy exists but misconfigured (+3)"
    total_score=$((total_score + 3))
  else
    log "❌ No bucket policy found"
  fi

  pab_status=$(run_aws "aws s3api get-bucket-policy-status --bucket $bucket_name --region $REGION | jq -r '.PolicyStatus.IsPublic'")
  if [[ "$pab_status" == "PERMISSION_DENIED" ]]; then
    log "⚠️ No permission to check public access block (0 marks)"
  elif [ "$pab_status" = "true" ]; then
    log "✅ Public access block disabled (+5)"
    total_score=$((total_score + 5))
  else
    log "❌ Public access block still enabled"
  fi
else
  log "❌ S3 bucket not found"
fi

#############################################
# Final Score
#############################################
echo
log "==============================="
log "Final Score: $total_score / 100"
log "==============================="
echo "Report saved as: $report"
