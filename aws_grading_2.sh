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

total_score=0

#############################################
# Task 1: EC2 and Launch Template (25%)
#############################################
[[ $MODE == "teacher" ]] && echo -e "\n[Task 1: EC2 + Launch Template (25%)]"

# Check Launch Template existence
lt_check=$(aws ec2 describe-launch-templates --region "$REGION" --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output text)
if [ -n "$lt_check" ]; then
  [[ $MODE == "teacher" ]] && echo "✅ Launch Template '$lt_name' found"
  total_score=$((total_score + 7))

  # Get User Data and instance type for verification
  latest_version=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-names "$lt_name" --query 'LaunchTemplates[0].LatestVersionNumber' --output text)
  version_data=$(aws ec2 describe-launch-template-versions --launch-template-name "$lt_name" --versions "$latest_version" --region "$REGION")
  instance_type=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType // empty')
  user_data=$(echo "$version_data" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')

  if [[ "$instance_type" == "t3.medium" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Launch Template uses t3.medium"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Launch Template instance type not t3.medium (found: $instance_type)"
  fi

  if [[ -n "$user_data" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Launch Template includes User Data"
    total_score=$((total_score + 10))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Launch Template missing User Data"
  fi

  # Detect any EC2 instance launched from this template (any version)
  instance_check=$(aws ec2 describe-instances \
    --filters "Name=launch-template.launch-template-name,Values=$lt_name" \
    --query "Reservations[].Instances[?State.Name=='running'].InstanceId" \
    --output text)

  if [ -n "$instance_check" ]; then
    [[ $MODE == "teacher" ]] && echo "✅ EC2 instance launched from Launch Template found: $instance_check"
    total_score=$((total_score + 3))
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

alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text)
if [ -n "$alb_arn" ]; then
  [[ $MODE == "teacher" ]] && echo "✅ ALB '$alb_name' exists"
  total_score=$((total_score + 5))

  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text)
  if curl -s "http://$alb_dns" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    [[ $MODE == "teacher" ]] && echo "✅ ALB DNS shows student name"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ ALB DNS does not show student name"
  fi
else
  [[ $MODE == "teacher" ]] && echo "❌ ALB '$alb_name' not found"
fi

tg_check=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?TargetGroupName=='$tg_name']" --output text)
if [ -n "$tg_check" ]; then
  [[ $MODE == "teacher" ]] && echo "✅ Target Group '$tg_name' exists"
  total_score=$((total_score + 5))
else
  [[ $MODE == "teacher" ]] && echo "❌ Target Group '$tg_name' not found"
fi

asg_check=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --query "AutoScalingGroups[?AutoScalingGroupName=='$asg_name']" --output text)
if [ -n "$asg_check" ]; then
  [[ $MODE == "teacher" ]] && echo "✅ ASG '$asg_name' exists"
  total_score=$((total_score + 5))

  config=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$asg_name" --query "AutoScalingGroups[0].[MinSize,MaxSize,DesiredCapacity]" --output text)
  if echo "$config" | grep -q -E "^1\s+4\s+2"; then
    [[ $MODE == "teacher" ]] && echo "✅ ASG scaling config is correct (Min=1, Max=4, Desired=2)"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ ASG scaling config not correct"
  fi
else
  [[ $MODE == "teacher" ]] && echo "❌ ASG '$asg_name' not found"
fi

#############################################
# Task 3: S3 Static Website (25%)
#############################################
[[ $MODE == "teacher" ]] && echo -e "\n[Task 3: S3 Static Website (25%)]"

bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep "$bucket_name_prefix" | head -n 1)
if [ -n "$bucket_name" ]; then
  [[ $MODE == "teacher" ]] && echo "✅ S3 bucket '$bucket_name' found"
  total_score=$((total_score + 5))

  website_config=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$website_config" ]; then
    [[ $MODE == "teacher" ]] && echo "✅ Static website hosting enabled"
    total_score=$((total_score + 8))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Static website hosting not enabled"
  fi

  index_found=$(aws s3api list-objects --bucket "$bucket_name" --region "$REGION" --query "Contents[].Key" --output text | grep -i index)
  if [ -n "$index_found" ]; then
    [[ $MODE == "teacher" ]] && echo "✅ index.html uploaded"
    total_score=$((total_score + 7))
  else
    [[ $MODE == "teacher" ]] && echo "❌ index.html not found"
  fi

  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  if curl -s "$website_url" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    [[ $MODE == "teacher" ]] && echo "✅ S3 page shows student name"
    total_score=$((total_score + 5))
  elif curl -s "$website_url" > /dev/null; then
    [[ $MODE == "teacher" ]] && echo "✅ S3 site accessible"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ S3 site not accessible"
  fi

  bp_check=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null)
  if [ -n "$bp_check" ]; then
    [[ $MODE == "teacher" ]] && echo "✅ Bucket policy configured"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ No bucket policy found"
  fi

  pab_status=$(aws s3api get-bucket-policy-status --bucket "$bucket_name" --region "$REGION" 2>/dev/null | jq -r '.PolicyStatus.IsPublic')
  if [ "$pab_status" = "true" ]; then
    [[ $MODE == "teacher" ]] && echo "✅ Public access block disabled"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Public access block still enabled"
  fi
else
  [[ $MODE == "teacher" ]] && echo "❌ S3 bucket not found"
fi

#############################################
# Task 4: RDS MySQL Integration (25%)
#############################################
[[ $MODE == "teacher" ]] && echo -e "\n[Task 4: RDS MySQL Integration (25%)]"

rds_check=$(aws rds describe-db-instances --region "$REGION" --query "DBInstances[?DBInstanceIdentifier=='rds-$STUDENT_NAME']" --output text)
if [ -n "$rds_check" ]; then
  [[ $MODE == "teacher" ]] && echo "✅ RDS instance 'rds-$STUDENT_NAME' found"
  total_score=$((total_score + 10))
else
  [[ $MODE == "teacher" ]] && echo "❌ RDS instance 'rds-$STUDENT_NAME' not found"
fi

#############################################
# Final Score
#############################################
echo "Final Score: $total_score / 100"
echo "Final Score: $total_score / 100" > grading_report.txt
echo "grading_report.txt written."
