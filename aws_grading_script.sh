#!/bin/bash

echo "=== AWS Practical Assessment Grading Script (BMIT3273) ==="
read -p "Enter your full name (e.g., LowChoonKeat): " STUDENT_NAME

REGION="us-east-1"
lower_name=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]')
norm_name=$(echo "$STUDENT_NAME" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

lt_name="lt-$lower_name"
asg_name="asg-$lower_name"
alb_name="alb-$lower_name"
tg_name="tg-$lower_name"
bucket_name_prefix="s3-$lower_name"

report="grading_report.txt"
total_score=0
echo "BMIT3273 AWS Practical Assessment Report" > $report
echo "Student: $STUDENT_NAME" >> $report
echo "Region: $REGION" >> $report
echo "----------------------------------------" >> $report

#############################################
# Task 1: EC2 + Launch Template (30%)
#############################################
echo
echo "[Task 1: EC2 + Launch Template (30%)]" | tee -a $report

lt_check=$(aws ec2 describe-launch-templates --region "$REGION" --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output text)

if [ -n "$lt_check" ]; then
  echo "✅ Launch Template '$lt_name' found (+10)" | tee -a $report
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
  user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty' | base64 --decode 2>/dev/null)

  # Instance type check
  if [[ "$instance_type" == "t3.micro" ]]; then
    echo "✅ Launch Template uses t3.micro (+10)" | tee -a $report
    total_score=$((total_score + 10))
  elif [[ "$instance_type" == "t2.micro" || "$instance_type" == "t4g.micro" ]]; then
    echo "⚠️ Launch Template uses $instance_type (partial +5)" | tee -a $report
    total_score=$((total_score + 5))
  elif [[ -n "$instance_type" ]]; then
    echo "⚠️ Launch Template uses $instance_type (wrong family +2)" | tee -a $report
    total_score=$((total_score + 2))
  else
    echo "❌ No instance type defined (+0)" | tee -a $report
  fi

  # User data check
  if [[ -n "$user_data" ]]; then
    if echo "$user_data" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | grep -q "$norm_name"; then
      echo "✅ User data includes student name (+10)" | tee -a $report
      total_score=$((total_score + 10))
    else
      echo "⚠️ User data present but no student name (+7)" | tee -a $report
      total_score=$((total_score + 7))
    fi
  else
    echo "❌ No user data (+0)" | tee -a $report
  fi
else
  echo "❌ Launch Template '$lt_name' NOT found (+0)" | tee -a $report
fi

#############################################
# Task 2: ALB + ASG + TG (35%)
#############################################
echo
echo "[Task 2: ALB + ASG + TG (35%)]" | tee -a $report

alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text)
if [ -n "$alb_arn" ]; then
  echo "✅ ALB '$alb_name' exists (+7)" | tee -a $report
  total_score=$((total_score + 7))

  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text)
  page=$(curl -s "http://$alb_dns")
  if echo "$page" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | grep -q "$norm_name"; then
    echo "✅ ALB DNS shows student name (+7)" | tee -a $report
    total_score=$((total_score + 7))
  elif [[ -n "$page" ]]; then
    echo "⚠️ ALB page works but no student name (+4)" | tee -a $report
    total_score=$((total_score + 4))
  else
    echo "⚠️ ALB DNS resolves but error page shown (+2)" | tee -a $report
    total_score=$((total_score + 2))
  fi
else
  echo "❌ ALB '$alb_name' not found (+0)" | tee -a $report
fi

tg_check=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?TargetGroupName=='$tg_name']" --output text)
if [ -n "$tg_check" ]; then
  echo "✅ Target Group '$tg_name' exists (+7)" | tee -a $report
  total_score=$((total_score + 7))
else
  echo "❌ Target Group '$tg_name' not found (+0)" | tee -a $report
fi

asg_check=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --query "AutoScalingGroups[?AutoScalingGroupName=='$asg_name']" --output text)
if [ -n "$asg_check" ]; then
  echo "✅ ASG '$asg_name' exists (+7)" | tee -a $report
  total_score=$((total_score + 7))

  config=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$asg_name" --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]" --output text)
  if echo "$config" | grep -q -E "^1\s+3\s+1"; then
    echo "✅ ASG scaling config correct (1/3/1) (+7)" | tee -a $report
    total_score=$((total_score + 7))
  elif [[ -n "$config" ]]; then
    echo "⚠️ ASG scaling config incorrect (+4)" | tee -a $report
    total_score=$((total_score + 4))
  else
    echo "⚠️ ASG only has defaults (+2)" | tee -a $report
    total_score=$((total_score + 2))
  fi
else
  echo "❌ ASG '$asg_name' not found (+0)" | tee -a $report
fi

#############################################
# Task 3: S3 Static Website (35%)
#############################################
echo
echo "[Task 3: S3 Static Website (35%)]" | tee -a $report

bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)

if [ -n "$bucket_name" ]; then
  echo "✅ S3 bucket '$bucket_name' found (+5)" | tee -a $report
  total_score=$((total_score + 5))

  website_config=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$website_config" ]; then
    echo "✅ Static website hosting enabled (+8)" | tee -a $report
    total_score=$((total_score + 8))
  else
    echo "❌ Static website hosting not enabled (+0)" | tee -a $report
  fi

  index_found=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" --query "Contents[].Key" --output text | grep -i index.html)
  if [ -n "$index_found" ]; then
    file_content=$(aws s3 cp "s3://$bucket_name/index.html" - --region "$REGION" 2>/dev/null)
    if echo "$file_content" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | grep -q "$norm_name"; then
      echo "✅ index.html uploaded with student name (+7)" | tee -a $report
      total_score=$((total_score + 7))
    else
      echo "⚠️ index.html exists but no student name (+5)" | tee -a $report
      total_score=$((total_score + 5))
    fi
  else
    echo "❌ index.html not found (+0)" | tee -a $report
  fi

  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  page=$(curl -s "$website_url")
  if echo "$page" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | grep -q "$norm_name"; then
    echo "✅ S3 page shows student name (+5)" | tee -a $report
    total_score=$((total_score + 5))
  elif [[ -n "$page" ]]; then
    echo "⚠️ S3 page accessible but no student name (+3)" | tee -a $report
    total_score=$((total_score + 3))
  else
    echo "⚠️ S3 error/default page (+2)" | tee -a $report
    total_score=$((total_score + 2))
  fi

  bp_check=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$bp_check" ]; then
    if echo "$bp_check" | grep -q '"Effect"[[:space:]]*:[[:space:]]*"Allow"' && \
       (echo "$bp_check" | grep -q '"Principal"[[:space:]]*:[[:space:]]*"[*]"' || \
        echo "$bp_check" | grep -q '"AWS"[[:space:]]*:[[:space:]]*"[*]"'); then
      echo "✅ Bucket policy configured correctly (+5)" | tee -a $report
      total_score=$((total_score + 5))
    else
      echo "⚠️ Bucket policy exists but may be restrictive (+3)" | tee -a $report
      total_score=$((total_score + 3))
    fi
  else
    if [[ -n "$page" ]]; then
      echo "⚠️ No bucket policy found, but site works (+3)" | tee -a $report
      total_score=$((total_score + 3))
    else
      echo "❌ No bucket policy and site not working (+0)" | tee -a $report
    fi
  fi

  pab_status=$(aws s3api get-bucket-policy-status --bucket "$bucket_name" --region "$REGION" 2>/dev/null | jq -r '.PolicyStatus.IsPublic')
  if [ "$pab_status" = "true" ]; then
    echo "✅ Public access block disabled (+5)" | tee -a $report
    total_score=$((total_score + 5))
  else
    echo "❌ Public access block still enabled (+0)" | tee -a $report
  fi
else
  echo "❌ S3 bucket not found (+0)" | tee -a $report
fi

#############################################
# Final Score
#############################################
echo
echo "=============================" | tee -a $report
echo "Final Score: $total_score / 100" | tee -a $report
echo "Report saved as: $report"
