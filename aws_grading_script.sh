#!/bin/bash

# === AWS Practical Assessment Grading Script ===

echo "=== AWS Practical Assessment Grading Script ==="
read -p "Enter your full name (e.g., LowChoonKeat): " student_name
REGION="ap-southeast-1"  # Change if needed

total_score=0
report="grading_report.txt"
echo "Grading Report for $student_name" > $report
echo "===============================" >> $report

# -------------------------------
# Task 1: EC2 + Launch Template (30%)
# -------------------------------
echo -e "\n[Task 1: EC2 + Launch Template (30%)]" | tee -a $report

lt_name="lt-$(echo $student_name | tr -d ' ')"
lt_check=$(aws ec2 describe-launch-templates --query "LaunchTemplates[?LaunchTemplateName=='$lt_name'].LaunchTemplateName" --region "$REGION" --output text)

if [[ "$lt_check" == "$lt_name" ]]; then
  echo "✅ Launch Template '$lt_name' found (+10)" | tee -a $report
  total_score=$((total_score + 10))

  # Check instance type
  inst_type=$(aws ec2 describe-launch-template-versions --launch-template-name "$lt_name" --versions 1 --region "$REGION" --query "LaunchTemplateVersions[0].LaunchTemplateData.InstanceType" --output text)
  if [[ "$inst_type" == "t3.micro" ]]; then
    echo "✅ Launch Template uses t3.micro (+10)" | tee -a $report
    total_score=$((total_score + 10))
  else
    echo "❌ Launch Template uses $inst_type (expected t3.micro)" | tee -a $report
  fi

  # Check user data includes student name
  user_data=$(aws ec2 describe-launch-template-versions --launch-template-name "$lt_name" --versions 1 --region "$REGION" --query "LaunchTemplateVersions[0].LaunchTemplateData.UserData" --output text | base64 --decode 2>/dev/null)
  if echo "$user_data" | grep -qi "$student_name"; then
    echo "✅ User data includes student name (+10)" | tee -a $report
    total_score=$((total_score + 10))
  else
    echo "❌ User data missing student name" | tee -a $report
  fi
else
  echo "❌ Launch Template '$lt_name' not found" | tee -a $report
fi

# -------------------------------
# Task 2: ALB + ASG + TG (35%)
# -------------------------------
echo -e "\n[Task 2: ALB + ASG + TG (35%)]" | tee -a $report

alb_name="alb-$(echo $student_name | tr -d ' ')"
tg_name="tg-$(echo $student_name | tr -d ' ')"
asg_name="asg-$(echo $student_name | tr -d ' ')"

# ALB check
alb_arn=$(aws elbv2 describe-load-balancers --names "$alb_name" --region "$REGION" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)
if [[ "$alb_arn" != "None" ]]; then
  echo "✅ ALB '$alb_name' exists (+7)" | tee -a $report
  total_score=$((total_score + 7))

  alb_dns=$(aws elbv2 describe-load-balancers --names "$alb_name" --region "$REGION" --query "LoadBalancers[0].DNSName" --output text)
  if curl -s "http://$alb_dns" | grep -qi "$student_name"; then
    echo "✅ ALB DNS shows student name (+7)" | tee -a $report
    total_score=$((total_score + 7))
  else
    echo "❌ ALB DNS missing student name" | tee -a $report
  fi
else
  echo "❌ ALB '$alb_name' not found" | tee -a $report
fi

# Target Group check
tg_check=$(aws elbv2 describe-target-groups --names "$tg_name" --region "$REGION" --query "TargetGroups[0].TargetGroupName" --output text 2>/dev/null)
if [[ "$tg_check" == "$tg_name" ]]; then
  echo "✅ Target Group '$tg_name' exists (+7)" | tee -a $report
  total_score=$((total_score + 7))
else
  echo "❌ Target Group '$tg_name' not found" | tee -a $report
fi

# ASG check
asg_check=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg_name" --region "$REGION" --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null)
if [[ "$asg_check" == "$asg_name" ]]; then
  echo "✅ ASG '$asg_name' exists (+7)" | tee -a $report
  total_score=$((total_score + 7))

  desired=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg_name" --region "$REGION" --query "AutoScalingGroups[0].DesiredCapacity" --output text)
  min_size=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg_name" --region "$REGION" --query "AutoScalingGroups[0].MinSize" --output text)
  max_size=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg_name" --region "$REGION" --query "AutoScalingGroups[0].MaxSize" --output text)
  if [[ "$desired" == "1" && "$min_size" == "1" && "$max_size" == "3" ]]; then
    echo "✅ ASG scaling config is correct (1/3/1) (+7)" | tee -a $report
    total_score=$((total_score + 7))
  else
    echo "❌ ASG scaling config incorrect (got min=$min_size, max=$max_size, desired=$desired)" | tee -a $report
  fi
else
  echo "❌ ASG '$asg_name' not found" | tee -a $report
fi

# -------------------------------
# Task 3: S3 Static Website (35%)
# -------------------------------
echo -e "\n[Task 3: S3 Static Website (35%)]" | tee -a $report

bucket_name="s3-$(echo $student_name | tr -d ' ')"

# Bucket exists
bucket_check=$(aws s3api head-bucket --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
if [[ $? -eq 0 ]]; then
  echo "✅ S3 bucket '$bucket_name' found (+5)" | tee -a $report
  total_score=$((total_score + 5))

  # Static website hosting
  hosting=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    echo "✅ Static website hosting enabled (+8)" | tee -a $report
    total_score=$((total_score + 8))
  else
    echo "❌ Static website hosting not enabled" | tee -a $report
  fi

  # index.html with student name
  tmpfile=$(mktemp)
  aws s3 cp "s3://$bucket_name/index.html" "$tmpfile" --region "$REGION" --quiet
  if grep -qi "$student_name" "$tmpfile"; then
    echo "✅ index.html uploaded with student name (+7)" | tee -a $report
    total_score=$((total_score + 7))
  else
    echo "❌ index.html missing student name" | tee -a $report
  fi
  rm -f "$tmpfile"

  # Check accessibility
  website_url="http://$bucket_name.s3-website.$REGION.amazonaws.com"
  if curl -s "$website_url" | grep -qi "$student_name"; then
    echo "✅ S3 page shows student name (+5)" | tee -a $report
    total_score=$((total_score + 5))
  else
    echo "❌ S3 page inaccessible or missing student name" | tee -a $report
  fi

  # Bucket policy check (improved version)
  bp_check=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$bp_check" ]; then
    allow_check=$(echo "$bp_check" | jq -r '
      .Statement[] 
      | select(.Effect=="Allow") 
      | select((.Action|tostring|test("s3:GetObject")) or (.Action|tostring|test("s3:\\*"))) 
      | select((.Principal=="*") or (.Principal.AWS=="*")) 
      | .Effect' 2>/dev/null)

    if [[ "$allow_check" == "Allow" ]]; then
      echo "✅ Bucket policy configured correctly (+5)" | tee -a $report
      total_score=$((total_score + 5))
    else
      echo "⚠️ Bucket policy exists but misconfigured (+3)" | tee -a $report
      total_score=$((total_score + 3))
    fi
  else
    echo "❌ No bucket policy found" | tee -a $report
  fi

  # Public access block
  pab=$(aws s3api get-bucket-ownership-controls --bucket "$bucket_name" --region "$REGION" 2>/dev/null; aws s3api get-bucket-policy-status --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    echo "✅ Public access block disabled (+5)" | tee -a $report
    total_score=$((total_score + 5))
  else
    echo "❌ Public access block still enabled" | tee -a $report
  fi
else
  echo "❌ Bucket '$bucket_name' not found" | tee -a $report
fi

# -------------------------------
# Final Score
# -------------------------------
echo -e "\n===============================" | tee -a $report
echo "Final Score: $total_score / 100" | tee -a $report
echo "===============================" | tee -a $report
echo "Report saved as: $report"
