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
echo "=== AWS Practical Assessment Report ===" > $report
echo "Student: $STUDENT_NAME" >> $report
echo "" >> $report

#############################################
# Task 1: EC2 and Launch Template (30%)
#############################################
echo
echo "[Task 1: EC2 + Launch Template (30%)]"
echo "[Task 1: EC2 + Launch Template (30%)]" >> $report

lt_check=$(aws ec2 describe-launch-templates --region "$REGION" --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output text)

if [ -n "$lt_check" ]; then
  echo "✅ Launch Template '$lt_name' found (+10)"
  echo "Launch Template found: +10" >> $report
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
  user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')

  # Instance type check
  if [[ "$instance_type" == "t3.micro" ]]; then
    echo "✅ Launch Template uses t3.micro (+10)"
    echo "Instance type correct (t3.micro): +10" >> $report
    total_score=$((total_score + 10))
  elif [[ "$instance_type" == "t2.micro" || "$instance_type" == "t4g.micro" ]]; then
    echo "⚠️ Launch Template uses $instance_type (partial +5)"
    echo "Instance type other micro ($instance_type): +5" >> $report
    total_score=$((total_score + 5))
  elif [[ -n "$instance_type" ]]; then
    echo "⚠️ Launch Template uses $instance_type (wrong family +2)"
    echo "Instance type wrong family ($instance_type): +2" >> $report
    total_score=$((total_score + 2))
  else
    echo "❌ No instance type defined (+0)"
    echo "Instance type missing: +0" >> $report
  fi

  # User data check
  if [[ -n "$user_data" ]]; then
    decoded_user_data=$(echo "$user_data" | base64 --decode 2>/dev/null)
    if echo "$decoded_user_data" | grep -iq "$STUDENT_NAME"; then
      echo "✅ User data includes student name (+10)"
      echo "User data correct with name: +10" >> $report
      total_score=$((total_score + 10))
    elif [[ -n "$decoded_user_data" ]]; then
      echo "⚠️ User data present but missing student name (+7)"
      echo "User data present, missing name: +7" >> $report
      total_score=$((total_score + 7))
    else
      echo "⚠️ User data script exists but invalid/empty (+4)"
      echo "User data invalid/empty: +4" >> $report
      total_score=$((total_score + 4))
    fi
  else
    echo "❌ No user data (+0)"
    echo "User data missing: +0" >> $report
  fi
else
  echo "❌ Launch Template '$lt_name' NOT found"
  echo "Launch Template not found: +0" >> $report
fi

#############################################
# Task 2: ALB + ASG + TG (35%)
#############################################
echo
echo "[Task 2: ALB + ASG + TG (35%)]"
echo "[Task 2: ALB + ASG + TG (35%)]" >> $report

alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text)
if [ -n "$alb_arn" ]; then
  echo "✅ ALB '$alb_name' exists (+7)"
  echo "ALB exists: +7" >> $report
  total_score=$((total_score + 7))

  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text)
  page_content=$(curl -s "http://$alb_dns")
  if echo "$page_content" | grep -iq "$STUDENT_NAME"; then
    echo "✅ ALB DNS shows student name (+7)"
    echo "ALB DNS shows name: +7" >> $report
    total_score=$((total_score + 7))
  elif [ -n "$page_content" ]; then
    echo "⚠️ ALB DNS reachable but no student name (+4)"
    echo "ALB DNS reachable, missing name: +4" >> $report
    total_score=$((total_score + 4))
  elif nslookup "$alb_dns" >/dev/null 2>&1; then
    echo "⚠️ ALB DNS resolves but page error (+2)"
    echo "ALB DNS error/default: +2" >> $report
    total_score=$((total_score + 2))
  else
    echo "❌ ALB DNS not resolving (+0)"
    echo "ALB DNS not resolving: +0" >> $report
  fi
else
  echo "❌ ALB '$alb_name' not found (+0)"
  echo "ALB missing: +0" >> $report
fi

tg_check=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?TargetGroupName=='$tg_name']" --output text)
if [ -n "$tg_check" ]; then
  echo "✅ Target Group '$tg_name' exists (+7)"
  echo "Target Group exists: +7" >> $report
  total_score=$((total_score + 7))
else
  echo "❌ Target Group '$tg_name' not found (+0)"
  echo "Target Group missing: +0" >> $report
fi

asg_check=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --query "AutoScalingGroups[?AutoScalingGroupName=='$asg_name']" --output text)
if [ -n "$asg_check" ]; then
  echo "✅ ASG '$asg_name' exists (+7)"
  echo "ASG exists: +7" >> $report
  total_score=$((total_score + 7))

  config=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$asg_name" --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]" --output text)
  if echo "$config" | grep -q -E "^1\s+3\s+1"; then
    echo "✅ ASG scaling config is correct (1/3/1) (+7)"
    echo "ASG scaling correct: +7" >> $report
    total_score=$((total_score + 7))
  elif [[ -n "$config" ]]; then
    echo "⚠️ ASG scaling config incorrect (+4)"
    echo "ASG scaling wrong values: +4" >> $report
    total_score=$((total_score + 4))
  else
    echo "⚠️ ASG scaling default only (+2)"
    echo "ASG scaling default: +2" >> $report
    total_score=$((total_score + 2))
  fi
else
  echo "❌ ASG '$asg_name' not found (+0)"
  echo "ASG missing: +0" >> $report
fi

#############################################
# Task 3: S3 Static Website (35%)
#############################################
echo
echo "[Task 3: S3 Static Website (35%)]"
echo "[Task 3: S3 Static Website (35%)]" >> $report

bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)

if [ -n "$bucket_name" ]; then
  echo "✅ S3 bucket '$bucket_name' found (+5)"
  echo "Bucket found: +5" >> $report
  total_score=$((total_score + 5))

  website_config=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$website_config" ]; then
    echo "✅ Static website hosting enabled (+8)"
    echo "Static hosting enabled: +8" >> $report
    total_score=$((total_score + 8))
  else
    echo "❌ Static website hosting not enabled (+0)"
    echo "Static hosting missing: +0" >> $report
  fi

  index_found=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" --query "Contents[].Key" --output text | grep -i index.html)
  if [ -n "$index_found" ]; then
    page_content=$(aws s3 cp "s3://$bucket_name/index.html" - 2>/dev/null)
    if echo "$page_content" | grep -iq "$STUDENT_NAME"; then
      echo "✅ index.html uploaded with student name (+7)"
      echo "index.html correct with name: +7" >> $report
      total_score=$((total_score + 7))
    else
      echo "⚠️ index.html uploaded but missing student name (+5)"
      echo "index.html missing name: +5" >> $report
      total_score=$((total_score + 5))
    fi
  else
    other_file=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" --query "Contents[].Key" --output text | head -n 1)
    if [ -n "$other_file" ]; then
      echo "⚠️ Other file found instead of index.html (+2)"
      echo "Other file ($other_file) found: +2" >> $report
      total_score=$((total_score + 2))
    else
      echo "❌ index.html not found (+0)"
      echo "index.html missing: +0" >> $report
    fi
  fi

  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  site_content=$(curl -s "$website_url")
  if echo "$site_content" | grep -iq "$STUDENT_NAME"; then
    echo "✅ S3 page shows student name (+5)"
    echo "S3 page shows name: +5" >> $report
    total_score=$((total_score + 5))
  elif [ -n "$site_content" ]; then
    echo "⚠️ S3 page accessible but no student name (+3)"
    echo "S3 page accessible, no name: +3" >> $report
    total_score=$((total_score + 3))
  elif curl -s "$website_url" > /dev/null; then
    echo "⚠️ S3 page default/error shown (+2)"
    echo "S3 page error/default: +2" >> $report
    total_score=$((total_score + 2))
  else
    echo "❌ S3 site not accessible (+0)"
    echo "S3 page inaccessible: +0" >> $report
  fi

  bp_check=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$bp_check" ]; then
    if echo "$bp_check" | grep -q '"Effect": "Allow"'; then
      echo "✅ Bucket policy configured correctly (+5)"
      echo "Bucket policy correct: +5" >> $report
      total_score=$((total_score + 5))
    else
      echo "⚠️ Bucket policy exists but misconfigured (+3)"
      echo "Bucket policy misconfigured: +3" >> $report
      total_score=$((total_score + 3))
    fi
  else
    echo "❌ No bucket policy found (+0)"
    echo "Bucket policy missing: +0" >> $report
  fi

  pab_status=$(aws s3api get-bucket-policy-status --bucket "$bucket_name" --region "$REGION" 2>/dev/null | jq -r '.PolicyStatus.IsPublic')
  if [ "$pab_status" = "true" ]; then
    echo "✅ Public access block disabled (+5)"
    echo "Public access disabled: +5" >> $report
    total_score=$((total_score + 5))
  elif [ -n "$pab_status" ]; then
    echo "⚠️ Public access block partially disabled (+3)"
    echo "Public access partial: +3" >> $report
    total_score=$((total_score + 3))
  else
    echo "❌ Public access block still enabled (+0)"
    echo "Public access enabled: +0" >> $report
  fi
else
  echo "❌ S3 bucket not found (+0)"
  echo "Bucket not found: +0" >> $report
fi

#############################################
# Final Score
#############################################
echo
echo "============================="
echo "Final Score: $total_score / 100"
echo "============================="

echo "" >> $report
echo "Final Score: $total_score / 100" >> $report
echo "Report saved as: $report"
