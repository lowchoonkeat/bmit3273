#!/usr/bin/env bash
# grade_bmit3273.sh
# BMIT3273 Cloud Computing — Auto-grader (final)
# Usage:
#   ./grade_bmit3273.sh            # student (concise)
#   ./grade_bmit3273.sh --teacher  # verbose teacher output
#
# Requirements:
#  - aws CLI configured to the student's AWS Academy Lab account
#  - jq, curl, nc (netcat) installed (CloudShell typically has these)
#  - Optional: mysql client for direct RDS SQL checks
#
# Naming convention (must match exam):
#  Launch Template: lt-<your-full-name-lowercase>
#  Auto Scaling Group: asg-<your-full-name-lowercase>
#  Application Load Balancer: alb-<your-full-name-lowercase>
#  Target Group: tg-<your-full-name-lowercase>
#  S3 Bucket: s3-<your-full-name-lowercase>
#  RDS Instance Identifier: rds-<your-full-name>
#
set -euo pipefail

MODE="student"
if [[ "${1-}" == "--teacher" ]]; then MODE="teacher"; fi

REGION="${AWS_REGION:-us-east-1}"
echo "BMIT3273 Auto-grader (Mode: $MODE) - Region: $REGION"
read -p "Enter your full name (lowercase, e.g. lowchoonkeat): " STUDENT_NAME
if [[ -z "$STUDENT_NAME" ]]; then echo "Student name required"; exit 1; fi

# normalize
lower_name=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
lt_name="lt-$lower_name"
asg_name="asg-$lower_name"
alb_name="alb-$lower_name"
tg_name="tg-$lower_name"
bucket_prefix="s3-$lower_name"
rds_identifier="rds-$STUDENT_NAME"   # follow exam pattern exactly
RDS_USER="admin"
RDS_PASS="admin12345"

# helpers
log() { [[ $MODE == "teacher" ]] && echo "$@"; }
safe_curl() { curl -s --max-time 6 "$@" || echo ""; }

# Score containers (each task totals to 25)
task1_score=0
task2_score=0
task3_score=0
task4_score=0

echo
log "=== Task 1: EC2 Dynamic Web Server via Launch Template (25) ==="

# Task 1.1: EC2 instance launched (10 marks)
ec2_instance_id=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=launch-template.launch-template-name,Values=$lt_name" \
            "Name=instance-state-name,Values=running,stopped,stopping,pending" \
  --query "Reservations[].Instances[0].InstanceId" --output text 2>/dev/null || true)

if [[ -n "$ec2_instance_id" && "$ec2_instance_id" != "None" ]]; then
  # check state
  state=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ec2_instance_id" \
    --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null || true)
  if [[ "$state" == "running" ]]; then
    log "✅ EC2 instance launched and running: $ec2_instance_id"
    task1_score=$((task1_score + 10))
  else
    log "⚠ EC2 instance exists but not running (state: $state) -> partial credit"
    # award mid-level per your earlier rubric: 4 marks for exists but not running/misconfigured
    task1_score=$((task1_score + 4))
  fi
else
  log "❌ No EC2 instance found launched from Launch Template '$lt_name'"
fi

# Task 1.2: Instance type (5 marks)
if [[ -n "$ec2_instance_id" && "$ec2_instance_id" != "None" ]]; then
  inst_type=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ec2_instance_id" \
    --query "Reservations[0].Instances[0].InstanceType" --output text 2>/dev/null || true)
  if [[ "$inst_type" == "t3.medium" ]]; then
    log "✅ Instance type is t3.medium"
    task1_score=$((task1_score + 5))
  elif [[ "$inst_type" =~ ^t3\.(small|large|xlarge|2.*)$|^t2\.(micro|small|medium)$ ]]; then
    log "⚠ Instance type is $inst_type (valid but not t3.medium) -> partial credit"
    task1_score=$((task1_score + 3))
  else
    log "❌ Instance type is $inst_type -> no marks"
  fi
else
  log "⚠ Cannot check instance type because no EC2 instance identified"
fi

# Task 1.3: User Data script (10 marks)
# Read latest launch template version user data if LT exists
lt_exists=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-names "$lt_name" --query "LaunchTemplates[0].LaunchTemplateName" --output text 2>/dev/null || true)
if [[ -n "$lt_exists" && "$lt_exists" != "None" ]]; then
  latest_ver=$(aws ec2 describe-launch-templates --region "$REGION" --launch-template-names "$lt_name" --query 'LaunchTemplates[0].LatestVersionNumber' --output text 2>/dev/null || true)
  lt_ver_json=$(aws ec2 describe-launch-template-versions --region "$REGION" --launch-template-name "$lt_name" --versions "$latest_ver" 2>/dev/null || true)
  user_data_b64=$(echo "$lt_ver_json" | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData // empty')
  if [[ -n "$user_data_b64" ]]; then
    user_data=$(echo "$user_data_b64" | base64 --decode 2>/dev/null || true)
    # check for webserver install/start
    if echo "$user_data" | grep -qiE "httpd|apache|yum install -y httpd|apt-get install -y apache2|systemctl start httpd"; then
      # check for student name presence in script (optional)
      if echo "$user_data" | grep -qi "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
        log "✅ User Data installs Apache and references student name."
        task1_score=$((task1_score + 10))
      else
        log "✅ User Data installs Apache but does not explicitly include student name -> partial (7/10)."
        task1_score=$((task1_score + 7))
      fi
    else
      log "⚠ User Data present but no clear Apache/httpd commands -> small credit (4/10)"
      task1_score=$((task1_score + 4))
    fi
  else
    log "❌ No User Data found in Launch Template"
  fi
else
  log "❌ Launch Template '$lt_name' not present; cannot evaluate User Data"
fi

log "Task 1 total: $task1_score / 25"
echo

####################################################
# Task 2: Auto Scaling with Application Load Balancer
# ALB exists (5), TG exists & healthy (5), ASG exists & linked (5),
# ASG scaling config (5), Web page via ALB DNS (5)
####################################################
log "=== Task 2: ALB + ASG + Target Group (25) ==="

# ALB
alb_arn=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].LoadBalancerArn" --output text 2>/dev/null || true)
if [[ -n "$alb_arn" && "$alb_arn" != "None" ]]; then
  log "✅ ALB '$alb_name' found"
  task2_score=$((task2_score + 5))
  alb_dns=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?LoadBalancerName=='$alb_name'].DNSName" --output text)
else
  log "❌ ALB '$alb_name' not found"
fi

# Target Group
tg_arn=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?TargetGroupName=='$tg_name'].TargetGroupArn" --output text 2>/dev/null || true)
if [[ -n "$tg_arn" && "$tg_arn" != "None" ]]; then
  log "✅ Target Group '$tg_name' found"
  # check health states
  health_states=$(aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$tg_arn" --query "TargetHealthDescriptions[].TargetHealth.State" --output text 2>/dev/null || true)
  if echo "$health_states" | grep -qi "healthy"; then
    log "✅ At least one target is HEALTHY"
    task2_score=$((task2_score + 5))
  else
    log "⚠ Target Group exists but no healthy targets (or none registered) -> partial (3/5)"
    task2_score=$((task2_score + 3))
  fi
else
  log "❌ Target Group '$tg_name' not found"
fi

# Auto Scaling Group
asg_json=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$asg_name" --output json 2>/dev/null || true)
if [[ -n "$asg_json" && "$asg_json" != "null" ]]; then
  if echo "$asg_json" | jq -e '.AutoScalingGroups | length > 0' >/dev/null 2>&1; then
    log "✅ ASG '$asg_name' found"
    # check linkage to launch template and target groups
    asg_lt_name=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].LaunchTemplate.LaunchTemplateName // empty')
    asg_tgarns=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].TargetGroupARNs[]? // empty' 2>/dev/null || true)
    if [[ "$asg_lt_name" == "$lt_name" && ( -n "$asg_tgarns" && echo "$asg_tgarns" | grep -q "$(echo $tg_arn | cut -d: -f6)" || true ) ]]; then
      log "✅ ASG linked to correct Launch Template and Target Group (best-effort detection)"
      task2_score=$((task2_score + 5))
    else
      log "⚠ ASG exists but appears misconfigured or not linked exactly -> partial (3/5)"
      task2_score=$((task2_score + 3))
    fi
    # scaling config check
    min_size=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].MinSize')
    desired_size=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].DesiredCapacity')
    max_size=$(echo "$asg_json" | jq -r '.AutoScalingGroups[0].MaxSize')
    if [[ "$min_size" -eq 1 && "$desired_size" -eq 2 && "$max_size" -eq 4 ]]; then
      log "✅ ASG scaling config Min=1 Desired=2 Max=4"
      task2_score=$((task2_score + 5))
    else
      log "⚠ ASG scaling config is Min=$min_size Desired=$desired_size Max=$max_size -> partial (3/5)"
      task2_score=$((task2_score + 3))
    fi
  fi
else
  log "❌ ASG '$asg_name' not found"
fi

# ALB DNS page verification
if [[ -n "${alb_dns-}" ]]; then
  html=$(safe_curl "http://$alb_dns")
  if [[ -n "$html" ]]; then
    if echo "$html" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
      log "✅ ALB DNS page accessible and contains student name"
      task2_score=$((task2_score + 5))
    else
      log "⚠ ALB DNS page accessible but student name not found -> partial (3/5)"
      task2_score=$((task2_score + 3))
    fi
  else
    log "❌ ALB DNS not reachable ($alb_dns) -> 0/5 for ALB page"
  fi
else
  log "⚠ No ALB DNS available (ALB likely not present) -> cannot check ALB page"
fi

# Cap task2_score to 25
if (( task2_score > 25 )); then task2_score=25; fi
log "Task 2 total: $task2_score / 25"
echo

####################################################
# Task 3: S3 Static Website Hosting (25)
# - Bucket exists (5)
# - Static website hosting enabled (5)
# - index.html uploaded with student name (5)
# - Public read / bucket policy (5)
# - Website verified in browser (5)
####################################################
log "=== Task 3: S3 Static Website (25) ==="

bucket_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text 2>/dev/null | tr '\t' '\n' | grep -i "^${bucket_prefix}" | head -n1 || true)
if [[ -n "$bucket_name" ]]; then
  log "✅ S3 bucket found: $bucket_name"
  task3_score=$((task3_score + 5))
  # website config
  website_cfg=$(aws s3api get-bucket-website --bucket "$bucket_name" --region "$REGION" 2>/dev/null || true)
  if [[ -n "$website_cfg" ]]; then
    log "✅ Static website hosting enabled"
    task3_score=$((task3_score + 5))
  else
    log "⚠ Static website hosting not enabled -> 0/5 for hosting"
  fi
  # index.html presence and content check
  index_keys=$(aws s3api list-objects-v2 --bucket "$bucket_name" --region "$REGION" --query "Contents[].Key" --output text 2>/dev/null || true)
  if echo "$index_keys" | grep -iq "index"; then
    log "✅ index.html (or similarly named index) exists"
    # try GET object via website endpoint (public)
    task3_score=$((task3_score + 5))
  else
    log "❌ index.html not found in bucket"
  fi
  # bucket policy check
  bp=$(aws s3api get-bucket-policy --bucket "$bucket_name" --region "$REGION" 2>/dev/null || true)
  if [[ -n "$bp" ]]; then
    log "✅ Bucket policy present (likely public GET configured)"
    task3_score=$((task3_score + 5))
  else
    log "⚠ Bucket policy not found; student may have used ACLs instead -> partial/no award"
  fi
  # public access block check
  pab=$(aws s3api get-public-access-block --bucket "$bucket_name" --region "$REGION" 2>/dev/null || true)
  if [[ -n "$pab" ]]; then
    blocked=$(echo "$pab" | jq -r '.PublicAccessBlockConfiguration.BlockPublicPolicy // true' 2>/dev/null || echo "true")
    if [[ "$blocked" == "false" ]]; then
      log "✅ Public access block not fully blocking (OK)"
      task3_score=$((task3_score + 5))
    else
      log "⚠ Public access block likely still blocking public access -> no award for public-read"
    fi
  else
    log "⚠ Could not get public-access-block; instructor should verify public access manually"
  fi
  # website endpoint check for student name
  website_url="http://$bucket_name.s3-website-$REGION.amazonaws.com"
  html=$(safe_curl "$website_url")
  if [[ -n "$html" ]]; then
    if echo "$html" | tr -d '[:space:]' | grep -iq "$(echo $STUDENT_NAME | tr -d '[:space:]')"; then
      log "✅ S3 website page accessible and contains student name"
      # we have already awarded many marks above; this is confirmation
    else
      log "⚠ S3 website reachable but student name not found in HTML"
    fi
  else
    log "❌ S3 website endpoint not reachable: $website_url"
  fi
else
  log "❌ No S3 bucket found matching prefix '$bucket_prefix'"
fi

# Cap task3_score to 25
if (( task3_score > 25 )); then task3_score=25; fi
log "Task 3 total: $task3_score / 25"
echo

####################################################
# Task 4: Database Integration using RDS MySQL (25)
# - RDS instance created (5)
# - Security group configured (5)
# - EC2 successfully connects to RDS (10)  [best-effort via mysql client or TCP test]
# - SQL query results verified (5)      [SHOW DATABASES shows testdb]
#
# NOTE: This script expects RDS master username admin and password admin12345 as per exam.
####################################################
log "=== Task 4: RDS MySQL Integration (25) ==="

rds_json=$(aws rds describe-db-instances --region "$REGION" --query "DBInstances[?DBInstanceIdentifier=='$rds_identifier']" --output json 2>/dev/null || true)
rds_exists=false
rds_endpoint=""
if [[ -n "$rds_json" && "$rds_json" != "[]" ]]; then
  rds_exists=true
  rds_endpoint=$(echo "$rds_json" | jq -r '.[0].Endpoint.Address // empty')
  engine=$(echo "$rds_json" | jq -r '.[0].Engine // empty')
  clazz=$(echo "$rds_json" | jq -r '.[0].DBInstanceClass // empty')
  log "✅ RDS instance '$rds_identifier' found (engine: $engine, class: $clazz, endpoint: $rds_endpoint)"
  task4_score=$((task4_score + 5))  # RDS created
else
  log "❌ RDS instance '$rds_identifier' not found"
fi

# Security group check (5)
sg_restrictive=false
if $rds_exists; then
  rds_sgs=$(echo "$rds_json" | jq -r '.[0].VpcSecurityGroups[].VpcSecurityGroupId' | tr '\n' ' ' || true)
  for sg in $rds_sgs; do
    sg_json=$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$sg" --output json 2>/dev/null || true)
    # look for inbound 3306 rules
    if echo "$sg_json" | jq -e '.SecurityGroups[0].IpPermissions[]? | select(.FromPort==3306 and .ToPort==3306)' >/dev/null 2>&1; then
      # if there is a UserIdGroupPairs entry (SG-to-SG) or IpRanges not 0.0.0.0/0 -> restrictive
      if echo "$sg_json" | jq -e '.SecurityGroups[0].IpPermissions[]? | select(.FromPort==3306 and .ToPort==3306) | (.UserIdGroupPairs|length>0) or (.IpRanges[]? | select(.CidrIp!="0.0.0.0/0"))' >/dev/null 2>&1; then
        sg_restrictive=true
      fi
    fi
  done
  if $sg_restrictive; then
    log "✅ RDS SG appears to restrict 3306 (likely allows EC2 SG only) -> award 5 marks"
    task4_score=$((task4_score + 5))
  else
    log "⚠ RDS SG does not appear to restrict 3306 (manual check recommended)"
  fi
fi

# EC2 -> RDS connectivity & SQL verification
ec2_connect_score=0
sql_verified_score=0

if [[ -n "$rds_endpoint" ]]; then
  # 1) TCP reachability test from CloudShell (best-effort)
  if nc -z -w5 "$rds_endpoint" 3306 >/dev/null 2>&1; then
    log "✅ TCP 3306 reachable from CloudShell to RDS endpoint (network path exists)"
    # award partial toward EC2 connect (we still prefer real mysql test)
    ec2_connect_score=7
  else
    log "⚠ TCP 3306 NOT reachable from CloudShell; this may be due to private subnet or SG restricting CloudShell"
    ec2_connect_score=0
  fi

  # 2) If mysql client exists, try to connect with provided credentials and check for 'testdb'
  if command -v mysql >/dev/null 2>&1; then
    log "mysql client found; attempting to connect to RDS with $RDS_USER/$RDS_PASS ..."
    mysql_out=$(mysql -h "$rds_endpoint" -u "$RDS_USER" -p"$RDS_PASS" -e "SHOW DATABASES;" 2>&1 || true)
    if echo "$mysql_out" | grep -iq "testdb"; then
      log "✅ Connected to RDS and 'testdb' found in SHOW DATABASES"
      # full marks for EC2 connection + SQL verification
      ec2_connect_score=10
      sql_verified_score=5
    elif echo "$mysql_out" | grep -iq "Access denied"; then
      log "❌ MySQL Access denied with provided credentials (student may not have used required password)"
    elif [[ -n "$mysql_out" ]]; then
      log "⚠ Connected to RDS but 'testdb' not present. Output of SHOW DATABASES:"
      [[ $MODE == "teacher" ]] && echo "$mysql_out"
      # partial connection detected
      if (( ec2_connect_score < 7 )); then ec2_connect_score=7; fi
    else
      log "⚠ mysql client attempted but no useful output"
    fi
  else
    log "⚠ mysql client not found in CloudShell; cannot run SQL tests from CloudShell. Instructor should verify EC2->RDS via student screenshots."
    # keep ec2_connect_score as per TCP reachability
  fi
else
  log "⚠ No RDS endpoint discovered to test connectivity"
fi

# add ec2_connect_score and sql_verified_score but ensure Task4 totals to 25
task4_score=$((task4_score + ec2_connect_score + sql_verified_score))
if (( task4_score > 25 )); then task4_score=25; fi
log "Task 4 total: $task4_score / 25"
echo

########################################
# Final tally
########################################
total=$((task1_score + task2_score + task3_score + task4_score))
# clamp
if (( total < 0 )); then total=0; fi
if (( total > 100 )); then total=100; fi

echo "======================================"
echo "AUTOGRADER REPORT"
echo "Student: $STUDENT_NAME"
echo "Region:  $REGION"
echo
printf "Task 1 (EC2 Launch Template): %3d / 25\n" "$task1_score"
printf "Task 2 (ALB + ASG + TG):     %3d / 25\n" "$task2_score"
printf "Task 3 (S3 Website):         %3d / 25\n" "$task3_score"
printf "Task 4 (RDS MySQL):          %3d / 25\n" "$task4_score"
echo "--------------------------------------"
printf "TOTAL (auto-graded):         %3d /100\n" "$total"
echo
echo "NOTES:"
echo " - This script uses RDS credentials admin / admin12345 (exam must instruct students to use these)."
echo " - If CloudShell cannot reach the student's RDS (private subnet/SG), the student must provide screenshots:"
echo "     * EC2 terminal showing: mysql -h <RDS-endpoint> -u admin -padmin12345"
echo "     * Output: CREATE DATABASE testdb; SHOW DATABASES;"
echo " - Instructor should manually review screenshots for items the script could not verify."
echo
# write report
cat > grading_report.txt <<EOF
Student: $STUDENT_NAME
Region: $REGION
Task1: $task1_score / 25
Task2: $task2_score / 25
Task3: $task3_score / 25
Task4: $task4_score / 25
Total (auto-graded): $total / 100
Notes:
- RDS credentials assumed: admin / admin12345.
- Manual verification may be required when CloudShell cannot reach private resources.
EOF

echo "grading_report.txt written."
echo "Done."
exit 0
