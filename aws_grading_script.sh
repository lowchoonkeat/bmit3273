#!/bin/bash

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

# Task 1: EC2 + Launch Template (25%)
echo "[Task 1: EC2 + Launch Template (25%)]" | tee -a grading_report.txt
lt_name="lt-$lowername"
lt_data=$(aws ec2 describe-launch-templates --query "LaunchTemplates[?LaunchTemplateName=='$lt_name']" --output json)

if [ "$lt_data" != "[]" ]; then
  echo "✅ Launch Template '$lt_name' found" | tee -a grading_report.txt
  ((score+=4))

  lt_id=$(echo "$lt_data" | jq -r '.[0].LaunchTemplateId')
  all_versions=$(aws ec2 describe-launch-template-versions --launch-template-id "$lt_id")
  latest_version=$(echo "$all_versions" | jq '.LaunchTemplateVersions | sort_by(.VersionNumber) | last')

  instance_type=$(echo "$latest_version" | jq -r '.LaunchTemplateData.InstanceType')
  user_data=$(echo "$latest_version" | jq -r '.LaunchTemplateData.UserData')

  if [[ "$instance_type" == "t3.micro" ]]; then
    echo "✅ Launch Template uses t3.micro" | tee -a grading_report.txt
    ((score+=4))
  else
    echo "❌ Launch Template does not use t3.micro" | tee -a grading_report.txt
  fi

  if [[ "$user_data" != "null" ]]; then
    echo "✅ Launch Template includes user data" | tee -a grading_report.txt
    ((score+=4))
  else
    echo "❌ Launch Template missing user data" | tee -a grading_report.txt
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
    ((score+=5))
  else
    echo "❌ Web page not showing student name" | tee -a grading_report.txt
  fi
else
  echo "❌ No running EC2 instance found" | tee -a grading_report.txt
fi

# Task 2: ALB + ASG + TG (25%)
echo "[Task 2: ALB + ASG + TG (25%)]" | tee -a grading_report.txt
alb_name="alb-$lowername"
tg_name="tg-$lowername"
asg_name="asg-$lowername"

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

tg_arn=$(aws elbv2 describe-target-groups --names "$tg_name" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
if [ "$tg_arn" != "None" ] && [ -n "$tg_arn" ]; then
  echo "✅ Target Group '$tg_name' exists" | tee -a grading_report.txt
  ((score+=5))
else
  echo "❌ Target Group '$tg_name' not found" | tee -a grading_report.txt
fi

asg_data=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg_name" --output json)
if echo "$asg_data" | jq -e '.AutoScalingGroups | length > 0' > /dev/null; then
  echo "✅ ASG '$asg_name' exists" | tee -a grading_report.txt
  ((score+=2))
  desired=$(echo "$asg_data" | jq -r '.AutoScalingGroups[0].DesiredCapacity')
  min=$(echo "$asg_data" | jq -r '.AutoScalingGroups[0].MinSize')
  max=$(echo "$asg_data" | jq -r '.AutoScalingGroups[0].MaxSize')
  if [[ "$desired" -eq 1 && "$min" -eq 1 && "$max" -eq 3 ]]; then
    echo "✅ ASG scaling config correct (1/1/3)" | tee -a grading_report.txt
    ((score+=2))
  else
    echo "❌ ASG scaling config incorrect" | tee -a grading_report.txt
  fi
else
  echo "❌ ASG '$asg_name' not found" | tee -a grading_report.txt
fi

# Task 3: S3 Static Website (20%)
echo "[Task 3: S3 Static Website (20%)]" | tee -a grading_report.txt
task3_score=0
bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep "^s3-$lowername" | head -n1)

if [ -z "$bucket_name" ]; then
  echo "❌ No S3 bucket found with prefix 's3-$lowername'" | tee -a grading_report.txt
else
  echo "✅ S3 bucket '$bucket_name' found" | tee -a grading_report.txt
  ((task3_score+=3))

  # Check website hosting
  if aws s3api get-bucket-website --bucket "$bucket_name" 2>/dev/null; then
    echo "✅ Static website hosting enabled" | tee -a grading_report.txt
    ((task3_score+=4))
  else
    echo "❌ Static website hosting not enabled" | tee -a grading_report.txt
  fi

  # Check index.html
  has_index=$(aws s3api list-objects --bucket "$bucket_name" --query "Contents[].Key" --output text | grep -i "index.html")
  if [ -n "$has_index" ]; then
    echo "✅ index.html is uploaded" | tee -a grading_report.txt
    ((task3_score+=3))
  else
    echo "❌ index.html not found" | tee -a grading_report.txt
  fi

  # Check public access config
  public_block=$(aws s3api get-bucket-public-access-block --bucket "$bucket_name" 2>/dev/null)
  if echo "$public_block" | grep -q false; then
    echo "✅ Block Public Access is disabled" | tee -a grading_report.txt
    ((task3_score+=2))
  else
    echo "❌ Block Public Access still enabled" | tee -a grading_report.txt
  fi

  # Check bucket policy
  bucket_policy=$(aws s3api get-bucket-policy --bucket "$bucket_name" 2>/dev/null)
  if [ -n "$bucket_policy" ]; then
    echo "✅ Bucket policy is configured" | tee -a grading_report.txt
    ((task3_score+=1))
  else
    echo "❌ No bucket policy configured" | tee -a grading_report.txt
  fi

  # Check website content
  s3_url="http://$bucket_name.s3-website-$region.amazonaws.com"
  s3_content=$(curl -s "$s3_url")
  if [ -n "$s3_content" ]; then
    echo "✅ S3 site is accessible" | tee -a grading_report.txt
    ((task3_score+=3))
    if echo "$s3_content" | grep -iq "$fullname"; then
      echo "✅ S3 site displays student name" | tee -a grading_report.txt
      ((task3_score+=4))
    else
      echo "❌ S3 page does not contain student name" | tee -a grading_report.txt
    fi
  else
    echo "❌ S3 site not accessible" | tee -a grading_report.txt
  fi
fi

# Cap Task 3 score at 20
if [ $task3_score -gt 20 ]; then
  task3_score=20
fi
score=$((score + task3_score))

# Final Score
echo "=============================" | tee -a grading_report.txt
echo "Final Score: $score / $max_score" | tee -a grading_report.txt
echo "Report saved as: grading_report.txt"
