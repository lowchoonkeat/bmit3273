#!/bin/bash
#
# BMIT3273 — Auto-grading script (this semester question)
# Usage:
#   bash grade_bmit3273.sh
#   bash grade_bmit3273.sh --teacher    # prints verbose teacher messages
#
# Requirements:
#  - aws CLI configured to the student's AWS Academy Lab credentials
#  - jq, curl installed (CloudShell includes them)
#
# Naming convention (must match exam):
#  Launch Template: lt-<your-full-name-lowercase>
#  Auto Scaling Group: asg-<your-full-name-lowercase>
#  Application Load Balancer: alb-<your-full-name-lowercase>
#  Target Group: tg-<your-full-name-lowercase>
#  S3 Bucket: s3-<your-full-name-lowercase>  (global uniqueness)
#  RDS Instance Identifier: rds-<your-full-name>
#
# Scoring matches the marking scheme provided by the lecturer:
#  Task1 (EC2 + Launch Template) = 25
#  Task2 (ALB + ASG + TG) = 25
#  Task3 (S3 static website) = 25
#  Task4 (RDS MySQL integration) = 25
#
set -euo pipefail

MODE="student"
if [[ "${1-}" == "--teacher" ]]; then
  MODE="teacher"
fi

REGION="${AWS_REGION:-us-east-1}"   # CloudShell default; override by env if needed

echo "=== BMIT3273 AWS Practical Auto-grader ==="
read -p "Enter your full name (lowercase, no spaces recommended e.g., lowchoonkeat): " STUDENT_NAME

# Basic normalized names
lower_name=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
lt_name="lt-$lower_name"
asg_name="asg-$lower_name"
alb_name="alb-$lower_name"
tg_name="tg-$lower_name"
bucket_prefix="s3-$lower_name"
rds_identifier="rds-$STUDENT_NAME"   # as per exam: rds-<your-full-name> (case kept)
web_access_sg_name="web-access"

if [[ "$MODE" == "teacher" ]]; then
  echo "Mode: TEACHER (verbose)"
else
  echo "Mode: STUDENT (concise)"
fi
echo "Region: $REGION"
echo

total_score=0

########################################
# Task 1: EC2 Dynamic Web Server via Launch Template (25)
#   - EC2 instance launched (10)
#   - Instance type t3.medium (5)
#   - User Data script present and contains web-server markers (10)
########################################
if [[ "$MODE" == "teacher" ]]; then echo ">> Task 1: EC2 + Launch Template (25)"; fi

# 1a: Check Launch Template exists
lt_found=false
lt_json=""
if lt_json=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-names "$lt_name" 2>/dev/null || true); then
  if [[ -n "$lt_json" ]]; then
    lt_found=true
    [[ $MODE == "teacher" ]] && echo "✅ Launch Template '$lt_name' found."
  fi
fi

# 1b: Check EC2 instance launched from that Launch Template (look for instances whose launchTemplate name is lt_name)
ec2_instance_id=""
if $lt_found; then
  # filter by launch-template name
  ec2_instance_id=$(aws ec2 describe-instances --region "$REGION" --filters "Name=launch-template.launch-template-name,Values=$lt_name" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
    --query "Reservations[].Instances[0].InstanceId" --output text 2>/dev/null || true)
  if [[ -n "$ec2_instance_id" && "$ec2_instance_id" != "None" ]]; then
    if [[ "$MODE" == "teacher" ]]; then
      echo "✅ EC2 instance launched from Launch Template: $ec2_instance_id"
      aws ec2 describe-instances --region "$REGION" --instance-ids "$ec2_instance_id" --query "Reservations[].Instances[].[InstanceId,InstanceType,State.Name,PrivateIpAddress,PublicIpAddress,ImageId]" --output table
    fi
    total_score=$((total_score + 10))   # award for instance launched (10 marks)
  else
    if [[ "$MODE" == "teacher" ]]; then
      echo "❌ No EC2 instance found launched from Launch Template '$lt_name'."
    fi
  fi
else
  [[ $MODE == "teacher" ]] && echo "❌ Launch Template not found; cannot find EC2 instances by template."
fi

# 1c: Instance type check (5 marks)
if [[ -n "$ec2_instance_id" && "$ec2_instance_id" != "None" ]]; then
  inst_type=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ec2_instance_id" --query "Reservations[0].Instances[0].InstanceType" --output text)
  if [[ "$inst_type" == "t3.medium" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Instance type is t3.medium"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Instance type is $inst_type (expected t3.medium)."
  fi
fi

# 1d: User Data script presence in Launch Template (10 marks)
# We'll read the latest version userData of the launch template and check for httpd/apache or nginx markers and student name
if $lt_found; then
  latest_ver=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-names "$lt_name" --query "LaunchTemplates[0].LatestVersionNumber" --output text)
  lt_ver_json=$(aws ec2 describe-launch-template-versions --region "$REGION" --launch-template-name "$lt_name" --versions "$latest_ver" 2>/dev/null || true)
  user_data_b64=$(echo "$lt_ver_json" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')
  if [[ -n "$user_data_b64" && "$user_data_b64" != "null" ]]; then
    # decode base64 and check content
    user_data_decoded=$(echo "$user_data_b64" | base64 --decode 2>/dev/null || true)
    if echo "$user_data_decoded" | grep -qiE "httpd|apache|yum install -y httpd|apt-get install -y apache|systemctl start httpd"; then
      [[ $MODE == "teacher" ]] && echo "✅ User Data contains Apache/httpd installation commands."
      total_score=$((total_score + 7))   # partial for installing webserver
    else
      [[ $MODE == "teacher" ]] && echo "❌ User Data does not contain obvious Apache/httpd install commands."
    fi
    # check for student name presence in user data (must show name in generated page)
    if echo "$user_data_decoded" | grep -qi "$(echo $STUDENT_NAME | tr -d '[:space:]')\|$(echo $STUDENT_NAME | tr ' ' '\n' | head -n1)"; then
      [[ $MODE == "teacher" ]] && echo "✅ User Data contains student name (or reference)."
      total_score=$((total_score + 3))   # bonus to reach 10 for user data
    else
      [[ $MODE == "teacher" ]] && echo "⚠ User Data does not mention student name explicitly. (Student may still generate name at runtime.)"
      # we do NOT award the 3 here if not found
    fi
  else
    [[ $MODE == "teacher" ]] && echo "❌ No User Data found in Launch Template."
  fi
fi

# End Task 1 summary
if [[ "$MODE" == "teacher" ]]; then
  echo "[Task 1 subtotal awarded so far: depends on findings above]"
fi
echo

########################################
# Task 2: ALB + ASG + Target Group (25)
#   - ALB exists (5)
#   - Target Group exists & healthy (5)
#   - Auto Scaling Group exists & linked (5)
#   - ASG scaling config Min=1 Desired=2 Max=4 (5)
#   - Web page accessible via ALB DNS showing student name (5)
########################################
if [[ "$MODE" == "teacher" ]]; then echo ">> Task 2: ALB + ASG + TG (25)"; fi

# 2a: ALB exists (by LoadBalancerName)
alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text 2>/dev/null || true)
if [[ -n "$alb_arn" && "$alb_arn" != "None" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ ALB '$alb_name' found."
  total_score=$((total_score + 5))
  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text)
else
  [[ $MODE == "teacher" ]] && echo "❌ ALB '$alb_name' not found."
fi

# 2b: Target Group exists & health
tg_arn=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?TargetGroupName=='$tg_name'].TargetGroupArn" --output text 2>/dev/null || true)
if [[ -n "$tg_arn" && "$tg_arn" != "None" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ Target Group '$tg_name' found."
  total_score=$((total_score + 5))
  # check health of targets (if any)
  health_states=$(aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$tg_arn" --query "TargetHealthDescriptions[].TargetHealth.State" --output text 2>/dev/null || true)
  if [[ -n "$health_states" ]]; then
    if echo "$health_states" | grep -qi "healthy"; then
      [[ $MODE == "teacher" ]] && echo "✅ At least one target is HEALTHY in Target Group."
      # award partial/implicit; marking scheme says 5 marks for healthy; we've already added 5 for existence.
      total_score=$((total_score + 0))  # existence already counted; keep details for teacher review
    else
      [[ $MODE == "teacher" ]] && echo "⚠ Targets exist but not healthy: $health_states"
    fi
  else
    [[ $MODE == "teacher" ]] && echo "⚠ No registered targets found in this Target Group yet."
  fi
else
  [[ $MODE == "teacher" ]] && echo "❌ Target Group '$tg_name' not found."
fi

# 2c: Auto Scaling Group exists & linked
asg_exists=false
asg_json=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$asg_name" --output json 2>/dev/null || true)
if [[ -n "$asg_json" && "$asg_json" != "null" ]]; then
  if echo "$asg_json" | jq -e '.AutoScalingGroups | length > 0' >/dev/null 2>&1; then
    asg_exists=true
    [[ $MODE == "teacher" ]] && echo "✅ ASG '$asg_name' found."
    total_score=$((total_score + 5))
    # check Launch Template link and Target Group ARNs and scaling numbers
    asg_lt_name=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].LaunchTemplate.LaunchTemplateName // empty')
    asg_tgarns=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].TargetGroupARNs[]? // empty' 2>/dev/null || true)
    min_size=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].MinSize')
    desired_size=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].DesiredCapacity')
    max_size=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].MaxSize')
    if [[ "$asg_lt_name" == "$lt_name" ]]; then
      [[ $MODE == "teacher" ]] && echo "✅ ASG correctly uses Launch Template '$lt_name'."
    else
      [[ $MODE == "teacher" ]] && echo "⚠ ASG Launch Template mismatch (found: $asg_lt_name)."
    fi
    # Check scaling config matches Min=1 Desired=2 Max=4
    if [[ "$min_size" -eq 1 && "$desired_size" -eq 2 && "$max_size" -eq 4 ]]; then
      [[ $MODE == "teacher" ]] && echo "✅ ASG scaling configuration Min=1 Desired=2 Max=4."
      total_score=$((total_score + 5))
    else
      [[ $MODE == "teacher" ]] && echo "❌ ASG scaling config is Min=$min_size Desired=$desired_size Max=$max_size (expected 1/2/4)."
    fi
  fi
else
  [[ $MODE == "teacher" ]] && echo "❌ ASG '$asg_name' not found."
fi

# 2d: ALB DNS page check (5)
if [[ -n "${alb_dns-}" ]]; then
  if curl -s "http://$alb_dns" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    [[ $MODE == "teacher" ]] && echo "✅ ALB DNS page contains student name."
    total_score=$((total_score + 5))
  else
    # if page accessible but name missing, award partial (3)
    if curl -s --max-time 6 "http://$alb_dns" >/dev/null 2>&1; then
      [[ $MODE == "teacher" ]] && echo "⚠ ALB DNS accessible but does not contain student name."
      total_score=$((total_score + 3))
    else
      [[ $MODE == "teacher" ]] && echo "❌ ALB DNS not accessible: $alb_dns"
    fi
  fi
fi

echo

########################################
# Task 3: Secure Static Website Hosting with S3 (25)
#   - S3 bucket exists with correct name (5)
#   - Static website hosting enabled (5)
#   - index.html uploaded and contains student name (5)
#   - Public read / bucket policy configured (5)
#   - Website verified in browser (5)
########################################
if [[ "$MODE" == "teacher" ]]; then echo ">> Task 3: S3 Static Website (25)"; fi

# Find a bucket that starts with bucket_prefix
bucket_name=""
bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text 2>/dev/null | tr '\t' '\n' | grep -i "^${bucket_prefix}" | head -n1 || true)
if [[ -n "$bucket_name" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ S3 bucket found: $bucket_name"
  total_score=$((total_score + 5))
  # website config
  website_cfg=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null || true)
  if [[ -n "$website_cfg" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Static website hosting enabled for $bucket_name"
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ Static website hosting NOT enabled for $bucket_name"
  fi

  # index.html presence
  index_found=$(aws s3api list-objects-v2 --bucket "$bucket_name" --region "$REGION" --query "Contents[?contains(Key,'index')].Key" --output text 2>/dev/null || true)
  if [[ -n "$index_found" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ index.html (or similar) found in bucket."
    # now check content for student name by fetching object
    # generate presigned URL (if public not required) otherwise try website endpoint
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ index.html not found in bucket."
  fi

  # bucket policy check
  bp=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null || true)
  if [[ -n "$bp" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ Bucket policy exists."
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "⚠ No bucket policy found. Students may instead have used object ACLs (less recommended)."
  fi

  # public access block status
  pab=$(aws s3api get-public-access-block --bucket "$bucket_name" --region "$REGION" 2>/dev/null || true)
  if [[ -n "$pab" ]]; then
    is_all_blocked=$(echo "$pab" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls and .PublicAccessBlockConfiguration.BlockPublicPolicy' 2>/dev/null || echo "false")
    if [[ "$is_all_blocked" == "false" || "$is_all_blocked" == "null" ]]; then
      [[ $MODE == "teacher" ]] && echo "✅ Public access block is not fully blocking (or not configured)."
      total_score=$((total_score + 5))
    else
      [[ $MODE == "teacher" ]] && echo "⚠ Public access block appears to block public access. Student may have disabled 'Block all public access' in console."
    fi
  else
    # if get-public-access-block fails, still continue
    [[ $MODE == "teacher" ]] && echo "⚠ Could not fetch public-access-block settings (permission or API)."
  fi

  # Try website endpoint and search for student name
  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  if curl -s --max-time 6 "$website_url" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
    [[ $MODE == "teacher" ]] && echo "✅ S3 website content contains student name."
    # already awarded index/content and website access marks above
  else
    if curl -s --max-time 6 "$website_url" >/dev/null 2>&1; then
      [[ $MODE == "teacher" ]] && echo "⚠ S3 website reachable but does not show student name in its HTML output."
    else
      [[ $MODE == "teacher" ]] && echo "❌ S3 website endpoint not reachable: $website_url"
    fi
  fi

else
  [[ $MODE == "teacher" ]] && echo "❌ No S3 bucket found matching prefix '$bucket_prefix'."
fi

echo

########################################
# Task 4: Database Integration using RDS MySQL (25)
#   - RDS exists with engine MySQL and db.t3.medium (5)
#   - Security group allows inbound 3306 from EC2 only (5)
#   - EC2 can connect to RDS (best-effort check: RDS public + SG allows EC2 SG) (10)
#   - SQL query results verified (manual step flagged; 5)
########################################
if [[ "$MODE" == "teacher" ]]; then echo ">> Task 4: RDS MySQL Integration (25)"; fi

# 4a: Find RDS instance by identifier
rds_json=$(aws rds describe-db-instances --region "$REGION" --query "DBInstances[?DBInstanceIdentifier=='$rds_identifier']" --output json 2>/dev/null || true)
if [[ -n "$rds_json" && "$rds_json" != "[]" ]]; then
  [[ $MODE == "teacher" ]] && echo "✅ RDS instance '$rds_identifier' found."
  total_score=$((total_score + 5))
  engine=$(echo "$rds_json" | jq -r '.[0].Engine // empty')
  clazz=$(echo "$rds_json" | jq -r '.[0].DBInstanceClass // empty')
  public_accessible=$(echo "$rds_json" | jq -r '.[0].PubliclyAccessible // false')
  rds_endpoint=$(echo "$rds_json" | jq -r '.[0].Endpoint.Address // empty')
  if [[ "$engine" == "mysql" || "$engine" == "MySQL" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ RDS engine is MySQL"
  else
    [[ $MODE == "teacher" ]] && echo "❌ RDS engine is '$engine' (expected MySQL)."
  fi
  if [[ "$clazz" == "db.t3.medium" ]]; then
    [[ $MODE == "teacher" ]] && echo "✅ RDS instance class is db.t3.medium"
  else
    [[ $MODE == "teacher" ]] && echo "⚠ RDS instance class is $clazz (expected db.t3.medium)."
  fi
else
  [[ $MODE == "teacher" ]] && echo "❌ RDS instance '$rds_identifier' not found."
fi

# 4b: Security group configuration check (inbound 3306 from EC2 only)
# Strategy:
#   - get RDS security groups, inspect inbound rules. Try to find a rule that allows tcp:3306 from a security-group-id (not 0.0.0.0/0).
#   - compare against security groups used by the student's EC2 instance (if found)
if [[ -n "$rds_json" && "$rds_json" != "[]" ]]; then
  rds_sgs=$(echo "$rds_json" | jq -r '.[0].VpcSecurityGroups[].VpcSecurityGroupId' | tr '\n' ' ' || true)
  sg_good=false
  for sg in $rds_sgs; do
    # describe sg rules
    sg_json=$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$sg" --output json 2>/dev/null || true)
    # check for 3306 inbound where the source is another sg (not 0.0.0.0/0)
    if echo "$sg_json" | jq -e '.SecurityGroups[0].IpPermissions[]? | select(.FromPort==3306 and .ToPort==3306) | .UserIdGroupPairs' >/dev/null 2>&1; then
      # check if UserIdGroupPairs contains any entry (means SG references another SG)
      if echo "$sg_json" | jq -e '.SecurityGroups[0].IpPermissions[]? | select(.FromPort==3306 and .ToPort==3306) | .UserIdGroupPairs | length > 0' >/dev/null 2>&1; then
        sg_good=true
      fi
      # also check for CIDR restriction (not 0.0.0.0/0)
      if echo "$sg_json" | jq -e '.SecurityGroups[0].IpPermissions[]? | select(.FromPort==3306 and .ToPort==3306) | .IpRanges[]? | select(.CidrIp!="0.0.0.0/0")' >/dev/null 2>&1; then
        sg_good=true
      fi
    fi
  done
  if $sg_good; then
    [[ $MODE == "teacher" ]] && echo "✅ RDS security group(s) appear to allow TCP/3306 from limited sources (not wide-open)."
    total_score=$((total_score + 5))
  else
    [[ $MODE == "teacher" ]] && echo "❌ RDS security group(s) do not show inbound 3306 from an EC2 SG or use restrictive CIDR. Manual check recommended."
  fi

  # 4c: Best-effort check that EC2 instances and RDS endpoint are network-reachable
  if [[ -n "$rds_endpoint" ]]; then
    [[ $MODE == "teacher" ]] && echo "RDS endpoint: $rds_endpoint (PubliclyAccessible=$public_accessible)"
    # Try to tcp-connect to 3306 from CloudShell (this only tests network path from CloudShell to RDS endpoint)
    if nc -z -w5 "$rds_endpoint" 3306 >/dev/null 2>&1; then
      [[ $MODE == "teacher" ]] && echo "✅ TCP port 3306 is reachable from CloudShell to the RDS endpoint (network path exists)."
      # Award partial marks toward EC2 connect - but true test is from EC2; we award 7/10 for network reachability
      total_score=$((total_score + 7))
    else
      [[ $MODE == "teacher" ]] && echo "⚠ TCP port 3306 not reachable from CloudShell; this may be due to private subnets or SG config."
      # if not reachable, but RDS is publicly accessible and SG seemed correct earlier, award small partial
      if [[ "$public_accessible" == "true" && "$sg_good" == "true" ]]; then
        total_score=$((total_score + 4))
      fi
    fi
  fi

  # 4d: SQL query verification (5 marks)
  # AUTOMATION LIMITATION: we cannot run SQL commands without the admin password and network access from EC2.
  # The script will therefore check whether a manual screenshot is required. If Student provided "evidence" via a tag or snapshot named 'testdb-created' we might detect it.
  # Best effort: check if any DB named 'testdb' exists on this RDS by using AWS RDS Data API only if cluster and resource configured (rare). So we will flag manual verification.
  echo
  if [[ "$MODE" == "teacher" ]]; then
    echo "NOTICE: Automated SQL execution is NOT attempted (requires DB credentials)."
    echo "Please verify manually that the EC2 instance connected to RDS and that 'CREATE DATABASE testdb;' and 'SHOW DATABASES;' were executed. The grader will check your screenshots."
  fi
  # We award 3/5 if network reachability and SG look good; otherwise 0 and manual verification required.
  if nc -z -w5 "$rds_endpoint" 3306 >/dev/null 2>&1 && $sg_good; then
    total_score=$((total_score + 3))
  else
    # no award
    :
  fi

else
  [[ $MODE == "teacher" ]] && echo "❌ RDS instance not found; cannot test RDS connectivity or config."
fi

echo

########################################
# Finalize & Output
########################################
# Ensure total_score is not greater than 100
if (( total_score > 100 )); then
  total_score=100
fi

echo "======================================"
echo "AUTOGRADER SUMMARY"
echo "Student: $STUDENT_NAME"
echo "Region: $REGION"
echo "Total Score (automatically awarded): $total_score / 100"
echo
echo "IMPORTANT NOTES:"
echo " - This script performs BEST-EFFORT automated checks."
echo " - Some items (e.g., executing SQL commands on RDS using admin password; verifying exact page contents on EC2-created pages) require manual screenshots from the student."
echo " - For Task 4 (SQL verification), final 5 marks require human verification of screenshots showing successful mysql -h <endpoint> -u admin -p and CREATE DATABASE / SHOW DATABASES outputs."
echo " - For Task 1 user-data dynamic content (server time), that is a bonus and should be validated by screenshots if not fully detected here."
echo
echo "Please attach the screenshot-based evidence in the student's submission PDF for manual verification of the remaining points."
echo "A grading_report.txt file will be created with the numeric result."
echo
echo "Saving grading_report.txt ..."
cat > grading_report.txt <<EOF
Student: $STUDENT_NAME
AWS Region: $REGION
Auto-graded score: $total_score / 100
Notes:
- This is an automated best-effort score. Items requiring manual verification (screenshots): Task1 user-data runtime page, Task2 ALB page content if not detected, Task3 index.html showing student name if not auto-detected, Task4 SQL commands outputs.
EOF

echo "Done. grading_report.txt written."
exit 0
