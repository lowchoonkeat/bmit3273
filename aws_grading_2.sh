#!/bin/bash

echo "=== BMIT3273 AWS Practical Assessment Grading Script ==="

read -p "Enter your full name (lowercase, no spaces recommended e.g., lowchoonkeat): " STUDENT_NAME

MODE="student"
if [[ "$1" == "--teacher" ]]; then
  MODE="teacher"
fi

REGION="us-east-1"
lower_name=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]')
lt_name="lt-$lower_name"
asg_name="asg-$lower_name"
alb_name="alb-$lower_name"
tg_name="tg-$lower_name"
bucket_name_prefix="s3-$lower_name"
rds_name="rds-$STUDENT_NAME"

total_score=0

#############################################
# Task 1: EC2 and Launch Template (25%)
#############################################
[[ $MODE == "teacher" ]] && echo -e "\n[Task 1: EC2 + Launch Template (25%)]"

lt_info=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-names "$lt_name" --query "LaunchTemplates[0]" --output json 2>/dev/null)

if [[ -n "$lt_info" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ Launch Template '$lt_name' found"
  total_score=$((total_score + 7))

  # Fetch Launch Template ID
  lt_id=$(echo "$lt_info" | jq -r '.LaunchTemplateId')

  # Check instance type
  latest_version=$(echo "$lt_info" | jq -r '.LatestVersionNumber')
  version_data=$(aws ec2 describe-launch-template-versions --launch-template-id "$lt_id" --versions "$latest_version" --region "$REGION")
  instance_type=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType')
  user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData')

  if [[ "$instance_type" == "t3.medium" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Launch Template uses t3.medium"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Launch Template instance type is '$instance_type', expected t3.medium"
  fi

  if [[ -n "$user_data" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Launch Template includes User Data"
    total_score=$((total_score + 10))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Launch Template missing User Data"
  fi

  # Check running EC2 instances launched from this template
  instance_check=$(aws ec2 describe-instances \
    --filters "Name=launch-template.id,Values=$lt_id" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" --output text)

  if [[ -n "$instance_check" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Running EC2 instance(s) found from Launch Template"
    total_score=$((total_score + 7))
  else
    [[ $MODE == "teacher" ]] && echo "❌ No running EC2 instance found launched from Launch Template '$lt_name'"
  fi

else
  [[ $MODE == "teacher" ]] && echo "❌ Launch Template '$lt_name' NOT found"
fi

#############################################
# Task 2: ALB + ASG + TG (25%)
#############################################
[[ $MODE == "teacher" ]] && echo -e "\n[Task 2: ALB + ASG + TG (25%)]"

alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" --names "$alb_name" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)
if [[ -n "$alb_arn" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ ALB '$alb_name' exists"
  total_score=$((total_score + 5))
else
  [[ $MODE == "teacher" ]] && echo "❌ ALB '$alb_name' not found"
fi

tg_arn=$(aws elbv2 describe-target-groups --region "$REGION" --names "$tg_name" --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null)
if [[ -n "$tg_arn" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ Target Group '$tg_name' exists"
  total_score=$((total_score + 5))
else
  [[ $MODE == "teacher" ]] && echo "❌ Target Group '$tg_name' not found"
fi

asg_info=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$asg_name" --query "AutoScalingGroups[0]" --output json 2>/dev/null)
if [[ -n "$asg_info" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ ASG '$asg_name' exists"
  total_score=$((total_score + 5))
else
  [[ $MODE == "teacher" ]] && echo "❌ ASG '$asg_name' not found"
fi

# Optional: check scaling config if ASG exists
if [[ -n "$asg_info" ]]; then
  min_size=$(echo "$asg_info" | jq -r '.MinSize')
  desired_size=$(echo "$asg_info" | jq -r '.DesiredCapacity')
  max_size=$(echo "$asg_info" | jq -r '.MaxSize')

  if [[ "$min_size" == 1 && "$desired_size" == 2 && "$max_size" == 4 ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ ASG scaling configuration correct (Min=1, Desired=2, Max=4)"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ ASG scaling config incorrect (found Min=$min_size, Desired=$desired_size, Max=$max_size)"
  fi
fi

#############################################
# Task 3: S3 Static Website (25%)
#############################################
[[ $MODE == "teacher" ]] && echo -e "\n[Task 3: S3 Static Website (25%)]"

bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)
if [[ -n "$bucket_name" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ S3 bucket '$bucket_name' found"
  total_score=$((total_score + 5))

  website_config=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [[ -n "$website_config" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Static website hosting enabled"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Static website hosting not enabled"
  fi

  index_file=$(aws s3api list-objects --bucket "$bucket_name" --query "Contents[].Key" --output text | grep -i "index.html")
  if [[ -n "$index_file" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ index.html uploaded"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ index.html not found"
  fi

else
  [[ $MODE == "teacher" ]] && echo "❌ S3 bucket not found"
fi

#############################################
# Task 4: RDS MySQL Integration (25%)
#############################################
[[ $MODE == "teacher" ]] && echo -e "\n[Task 4: RDS MySQL Integration (25%)]"

rds_info=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$rds_name" --query "DBInstances[0]" --output json 2>/dev/null)
if [[ -n "$rds_info" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ RDS instance '$rds_name' found"
  total_score=$((total_score + 5))
else
  [[ $MODE == "teacher" ]] && echo "❌ RDS instance '$rds_name' not found"
fi

#############################################
# Final Score
#############################################
echo "Final Score: $total_score / 100"
echo "Final Score: $total_score / 100" > grading_report.txt
echo "grading_report.txt written."
