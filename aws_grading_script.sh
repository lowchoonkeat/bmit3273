#!/bin/bash

# AWS Grading Script (Weighted: 70% total)
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
lt_check=$(aws ec2 describe-launch-templates --query "LaunchTemplates[?contains(LaunchTemplateName, 'LT_$fullname')]" --output text)
if [ -n "$lt_check" ]; then
  echo "✅ Launch Template found" | tee -a grading_report.txt
  ((score+=8))
else
  echo "❌ Launch Template NOT found" | tee -a grading_report.txt
fi

instance_id=$(aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$instance_id" ]; then
  echo "✅ Running EC2 instance found: $instance_id" | tee -a grading_report.txt
  ((score+=8))

  public_ip=$(aws ec2 describe-instances --instance-ids $instance_id --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
  if curl -s "http://$public_ip" | grep -iq "$fullname"; then
    echo "✅ Web page served with student name" | tee -a grading_report.txt
    ((score+=9))
  else
    echo "❌ Web page not showing student name" | tee -a grading_report.txt
  fi
else
  echo "❌ No running EC2 instance found" | tee -a grading_report.txt
fi

# Task 2: ALB and ASG (25%)
echo "[Task 2: ALB + ASG (25%)]" | tee -a grading_report.txt
alb_dns=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'alb')].DNSName" --output text)
if [ -n "$alb_dns" ]; then
  echo "✅ ALB DNS: $alb_dns" | tee -a grading_report.txt
  ((score+=8))
  if curl -s "http://$alb_dns" | grep -iq "$fullname"; then
    echo "✅ ALB serves content with student name" | tee -a grading_report.txt
    ((score+=9))
  else
    echo "❌ ALB DNS not showing student name in content" | tee -a grading_report.txt
  fi
else
  echo "❌ ALB not found" | tee -a grading_report.txt
fi

asg_check=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'ASG_$fullname')].[MinSize,MaxSize,DesiredCapacity]" --output text)
if [ -n "$asg_check" ]; then
  echo "✅ ASG with correct naming exists" | tee -a grading_report.txt
  ((score+=8))
else
  echo "❌ ASG not found or not named properly" | tee -a grading_report.txt
fi

# Task 3: S3 Website Hosting (20%)
echo "[Task 3: S3 Static Website (20%)]" | tee -a grading_report.txt
bucket_name="s3-$lowername"
s3_check=$(aws s3api head-bucket --bucket $bucket_name 2>&1)
if [[ $s3_check == *"Not Found"* || $s3_check == *"Forbidden"* ]]; then
  echo "❌ S3 bucket $bucket_name not found or inaccessible" | tee -a grading_report.txt
else
  echo "✅ S3 bucket $bucket_name found" | tee -a grading_report.txt
  ((score+=8))

  s3_url="http://$bucket_name.s3-website-$region.amazonaws.com"
  if curl -s "$s3_url" | grep -iq "$fullname"; then
    echo "✅ S3 site displays student name" | tee -a grading_report.txt
    ((score+=6))
  else
    echo "❌ S3 site does not display student name" | tee -a grading_report.txt
  fi
fi

# Final score
echo "=============================" | tee -a grading_report.txt
echo "Final Score: $score / $max_score" | tee -a grading_report.txt
echo "Report saved as: grading_report.txt"
