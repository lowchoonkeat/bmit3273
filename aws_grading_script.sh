#!/bin/bash

# AWS Grading Script (No health check, 70% total)
echo "=== AWS Practical Assessment Grading Script ==="
read -p "Enter your full name (e.g., LowChoonKeat): " fullname
lowername=$(echo "$fullname" | tr '[:upper:]' '[:lower:]')
region=$(aws configure get region)
echo "Region: $region"

score=0
max_score=70

echo "" > grading_report.txt
echo "Grading Report for $fullname" >> grading_report.txt
echo "=============================" >> grading_report.txt

# Task 1: EC2 and Launch Template (25%)
echo "[Task 1: EC2 + Launch Template (25%)]" | tee -a grading_report.txt
lt_name="LT_$fullname"
lt_data=$(aws ec2 describe-launch-templates --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output json)
if [ "$lt_data" != "[]" ]; then
  echo "✅ Launch Template '$lt_name' found" | tee -a grading_report.txt
  ((score+=4))

  lt_id=$(echo "$lt_data" | jq -r '.[0].LaunchTemplateId')
  latest_version=$(aws ec2 describe-launch-template-versions --launch-template-id "$lt_id" --versions latest --query 'LaunchTemplateVersions[0]')
  ami_id=$(echo "$latest_version" | jq -r '.LaunchTemplateData.ImageId')
  instance_type=$(echo "$latest_version" | jq -r '.LaunchTemplateData.InstanceType')
  user_data=$(echo "$latest_version" | jq -r '.LaunchTemplateData.UserData')

  if [[ "$ami_id" == *"ami"* && "$instance_type" != "null" && "$user_data" != "null" ]]; then
    echo "✅ Launch Template has AMI, instance type, and user data configured" | tee -a grading_report.txt
    ((score+=4))
  else
    echo "❌ Launch Template missing config (AMI, type, or user data)" | tee -a grading_report.txt
  fi
else
  echo "❌ Launch Template '$lt_name' NOT found" | tee -a grading_report.txt
fi

instance_id=$(aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$instance_id" ]; then
  echo "✅ Running EC2 instance found: $instance_id" | tee -a grading_report.txt
  ((score+=8))
  public_ip=$(aws ec2 describe-instances --instance-ids $instance_id --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
  if curl -s "http://$public_ip" | grep -iq "$fullname"; then
    echo "✅ Web server running and displaying student name" | tee -a grading_report.txt
    ((score+=9))
  else
    echo "❌ Web page not showing student name" | tee -a grading_report.txt
  fi
else
  echo "❌ No running EC2 instance found" | tee -a grading_report.txt
fi

# Task 2: ALB + ASG + TG (25%)
echo "[Task 2: ALB + ASG + TG (25%)]" | tee -a grading_report.txt
alb_name="ALB_$fullname"
tg_name="TG_$fullname"
asg_name="ASG_$fullname"

alb_dns=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text)
if [ -n "$alb_dns" ]; then
  echo "✅ ALB '$alb_name' DNS: $alb_dns" | tee -a grading_report.txt
  ((score+=6))
  if curl -s "http://$alb_dns" | grep -iq "$fullname"; then
    echo "✅ ALB DNS shows page with student name" | tee -a grading_report.txt
    ((score+=5))
  else
    echo "❌ ALB DNS does not show student name" | tee -a grading_report.txt
  fi
else
  echo "❌ ALB '$alb_name' not found" | tee -a grading_report.txt
fi

# Only check if target group exists (no health check)
tg_arn=$(aws elbv2 describe-target-groups --names "$tg_name" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
if [ "$tg_arn" != "None" ] && [ -n "$tg_arn" ]; then
  echo "✅ Target Group '$tg_name' exists" | tee -a grading_report.txt
  ((score+=5))
else
  echo "❌ Target Group '$tg_name' not found" | tee -a grading_report.txt
fi

asg_check=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?AutoScalingGroupName=='$asg_name']" --output json)
if [ "$asg_check" != "[]" ]; then
  echo "✅ ASG '$asg_name' exists" | tee -a grading_report.txt
  ((score+=4))
else
  echo "❌ ASG '$asg_name' not found" | tee -a grading_report.txt
fi

# Task 3: S3 Static Website Hosting (20%)
echo "[Task 3: S3 Static Website (20%)]" | tee -a grading_report.txt
bucket_name="s3-$lowername"
website_status=$(aws s3api get-bucket-website --bucket "$bucket_name" 2>/dev/null)
if [ $? -eq 0 ]; then
  echo "✅ Static website hosting is enabled for $bucket_name" | tee -a grading_report.txt
  ((score+=4))
else
  echo "❌ Static website hosting not enabled for $bucket_name" | tee -a grading_report.txt
fi

s3_url="http://$bucket_name.s3-website-$region.amazonaws.com"
if curl -s "$s3_url" | grep -iq "$fullname"; then
  echo "✅ S3 site displays student name" | tee -a grading_report.txt
  ((score+=6))
else
  echo "❌ S3 site does not show student name or inaccessible" | tee -a grading_report.txt
fi

# Final Score
echo "=============================" | tee -a grading_report.txt
echo "Final Score: $score / $max_score" | tee -a grading_report.txt
echo "Report saved as: grading_report.txt"
