#!/bin/bash

# BMIT3273 Cloud Computing Auto-Grading Script
# Purpose: Automatically grade student AWS practical assessment
# Based on Official Marking Scheme (202509)
# Usage: Run this script in AWS CloudShell after student completes the assessment

echo "=========================================="
echo "BMIT3273 Cloud Computing Auto-Grader"
echo "Based on Official Marking Scheme 202509"
echo "=========================================="
echo ""

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize scoring
TOTAL_SCORE=0
MAX_SCORE=100

# Detailed task scoring
TASK1_SCORE=0
TASK1_EC2_SCORE=0      # 10 marks
TASK1_TYPE_SCORE=0     # 5 marks
TASK1_USERDATA_SCORE=0 # 10 marks

TASK2_SCORE=0
TASK2_ALB_SCORE=0      # 5 marks
TASK2_TG_SCORE=0       # 5 marks
TASK2_ASG_SCORE=0      # 5 marks
TASK2_CONFIG_SCORE=0   # 5 marks
TASK2_ACCESS_SCORE=0   # 5 marks

TASK3_SCORE=0
TASK3_BUCKET_SCORE=0   # 5 marks
TASK3_HOSTING_SCORE=0  # 5 marks
TASK3_INDEX_SCORE=0    # 5 marks
TASK3_POLICY_SCORE=0   # 5 marks
TASK3_VERIFY_SCORE=0   # 5 marks

TASK4_SCORE=0
TASK4_RDS_SCORE=0      # 5 marks
TASK4_SG_SCORE=0       # 5 marks
TASK4_CONNECT_SCORE=0  # 10 marks
TASK4_SQL_SCORE=0      # 5 marks

# Request student name
echo "Enter student's full name (lowercase with hyphens, e.g., 'low-choon-keat'):"
read STUDENT_NAME

if [ -z "$STUDENT_NAME" ]; then
    echo -e "${RED}Error: Student name is required${NC}"
    exit 1
fi

echo ""
echo "Grading for student: $STUDENT_NAME"
echo "Start time: $(date)"
echo "=========================================="
echo ""

# ============================================
# TASK 1: EC2 Dynamic Web Server via Launch Template (25 marks)
# ============================================
echo -e "${BLUE}### TASK 1: EC2 Dynamic Web Server via Launch Template (25 marks) ###${NC}"
echo ""

# Criteria 1: EC2 instance launched (10 marks)
echo "Criteria 1: EC2 Instance Launched (10 marks)"
echo "--------------------------------------------"

LT_NAME="lt-${STUDENT_NAME}"
echo "Checking for Launch Template: $LT_NAME"

LT_CHECK=$(aws ec2 describe-launch-templates --filters "Name=launch-template-name,Values=$LT_NAME" --query 'LaunchTemplates[0].LaunchTemplateName' --output text 2>/dev/null)

if [ "$LT_CHECK" == "$LT_NAME" ]; then
    LT_ID=$(aws ec2 describe-launch-templates --filters "Name=launch-template-name,Values=$LT_NAME" --query 'LaunchTemplates[0].LaunchTemplateId' --output text)
    echo -e "${GREEN}✓ Launch Template found: $LT_NAME${NC}"
    
    # Check for EC2 instances from Launch Template
    INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:ec2launchtemplate:id,Values=$LT_ID" \
                  "Name=instance-state-name,Values=running,pending,stopped" \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
    
    if [ -n "$INSTANCES" ]; then
        INSTANCE_COUNT=$(echo "$INSTANCES" | wc -w)
        FIRST_INSTANCE=$(echo "$INSTANCES" | awk '{print $1}')
        
        # Check instance state
        INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$FIRST_INSTANCE" --query 'Reservations[0].Instances[0].State.Name' --output text)
        
        # Check AMI (Amazon Linux 2 or AL2023)
        AMI_DESC=$(aws ec2 describe-instances --instance-ids "$FIRST_INSTANCE" --query 'Reservations[0].Instances[0].ImageId' --output text)
        AMI_NAME=$(aws ec2 describe-images --image-ids "$AMI_DESC" --query 'Images[0].Description' --output text 2>/dev/null)
        
        if [ "$INSTANCE_STATE" == "running" ]; then
            if echo "$AMI_NAME" | grep -iq "amazon linux"; then
                echo -e "${GREEN}✓ EC2 instance running with Amazon Linux${NC}"
                echo -e "${GREEN}✓ Instance ID: $FIRST_INSTANCE${NC}"
                TASK1_EC2_SCORE=10
            else
                echo -e "${YELLOW}⚠ Instance running but AMI verification unclear${NC}"
                TASK1_EC2_SCORE=7
            fi
        elif [ "$INSTANCE_STATE" == "stopped" ]; then
            echo -e "${YELLOW}⚠ Instance exists but is stopped${NC}"
            TASK1_EC2_SCORE=4
        else
            echo -e "${YELLOW}⚠ Instance exists but state: $INSTANCE_STATE${NC}"
            TASK1_EC2_SCORE=4
        fi
    else
        echo -e "${RED}✗ No EC2 instance launched from Launch Template${NC}"
        TASK1_EC2_SCORE=0
    fi
else
    echo -e "${RED}✗ Launch Template not found${NC}"
    TASK1_EC2_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK1_EC2_SCORE / 10${NC}"
echo ""

# Criteria 2: Instance type (5 marks)
echo "Criteria 2: Instance Type (5 marks)"
echo "------------------------------------"

if [ -n "$LT_ID" ]; then
    LT_DATA=$(aws ec2 describe-launch-template-versions --launch-template-id "$LT_ID" --versions '$Latest' --query 'LaunchTemplateVersions[0].LaunchTemplateData' 2>/dev/null)
    
    INSTANCE_TYPE=$(echo "$LT_DATA" | jq -r '.InstanceType // empty')
    
    if [ "$INSTANCE_TYPE" == "t3.medium" ]; then
        echo -e "${GREEN}✓ Correct instance type: t3.medium${NC}"
        TASK1_TYPE_SCORE=5
    elif [[ "$INSTANCE_TYPE" =~ ^t3\. ]] || [[ "$INSTANCE_TYPE" =~ ^t2\. ]]; then
        echo -e "${YELLOW}⚠ Instance type is $INSTANCE_TYPE (general-purpose but not t3.medium)${NC}"
        TASK1_TYPE_SCORE=3
    elif [ -n "$INSTANCE_TYPE" ]; then
        echo -e "${YELLOW}⚠ Instance type is $INSTANCE_TYPE (not general-purpose)${NC}"
        TASK1_TYPE_SCORE=1
    else
        echo -e "${RED}✗ Instance type not found${NC}"
        TASK1_TYPE_SCORE=0
    fi
else
    echo -e "${RED}✗ Cannot check instance type (no Launch Template)${NC}"
    TASK1_TYPE_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK1_TYPE_SCORE / 5${NC}"
echo ""

# Criteria 3: User Data script (10 marks)
echo "Criteria 3: User Data Script (10 marks)"
echo "----------------------------------------"

if [ -n "$LT_DATA" ]; then
    USER_DATA=$(echo "$LT_DATA" | jq -r '.UserData // empty')
    
    if [ -n "$USER_DATA" ]; then
        DECODED_DATA=$(echo "$USER_DATA" | base64 -d 2>/dev/null)
        
        # Check components
        HAS_HTTPD=false
        HAS_HTML=false
        HAS_NAME=false
        HAS_IP=false
        HAS_TIME=false
        HAS_START=false
        
        if echo "$DECODED_DATA" | grep -iq "httpd"; then
            HAS_HTTPD=true
        fi
        
        if echo "$DECODED_DATA" | grep -iq "index.html"; then
            HAS_HTML=true
        fi
        
        if echo "$DECODED_DATA" | grep -iq "systemctl.*start.*httpd\|service httpd start"; then
            HAS_START=true
        fi
        
        # Check for IP capture (hostname -I or similar)
        if echo "$DECODED_DATA" | grep -iq "hostname\|ip\|private"; then
            HAS_IP=true
        fi
        
        # Check for time/date
        if echo "$DECODED_DATA" | grep -iq "date\|time"; then
            HAS_TIME=true
        fi
        
        # Check for student name pattern (any capitalized words)
        if echo "$DECODED_DATA" | grep -E "[A-Z][a-z]+ [A-Z][a-z]+|Welcome" > /dev/null; then
            HAS_NAME=true
        fi
        
        # Calculate score
        if [ "$HAS_HTTPD" = true ] && [ "$HAS_HTML" = true ] && [ "$HAS_START" = true ] && [ "$HAS_IP" = true ]; then
            if [ "$HAS_NAME" = true ]; then
                echo -e "${GREEN}✓ User Data script complete (httpd, HTML, student name, IP)${NC}"
                if [ "$HAS_TIME" = true ]; then
                    echo -e "${GREEN}✓ Bonus: Server time included${NC}"
                fi
                TASK1_USERDATA_SCORE=10
            else
                echo -e "${YELLOW}⚠ Script functional but student name missing${NC}"
                TASK1_USERDATA_SCORE=7
            fi
        elif [ "$HAS_HTTPD" = true ] || [ "$HAS_HTML" = true ]; then
            echo -e "${YELLOW}⚠ User Data exists but incomplete/not fully functional${NC}"
            TASK1_USERDATA_SCORE=4
        else
            echo -e "${RED}✗ User Data does not execute properly${NC}"
            TASK1_USERDATA_SCORE=0
        fi
        
        # Show what was detected
        echo "  Components detected:"
        echo "  - Apache/httpd installation: $HAS_HTTPD"
        echo "  - HTML file creation: $HAS_HTML"
        echo "  - Service start: $HAS_START"
        echo "  - Student name: $HAS_NAME"
        echo "  - Private IP: $HAS_IP"
        echo "  - Server time: $HAS_TIME"
        
    else
        echo -e "${RED}✗ No User Data configured${NC}"
        TASK1_USERDATA_SCORE=0
    fi
else
    echo -e "${RED}✗ Cannot check User Data (no Launch Template)${NC}"
    TASK1_USERDATA_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK1_USERDATA_SCORE / 10${NC}"
echo ""

TASK1_SCORE=$((TASK1_EC2_SCORE + TASK1_TYPE_SCORE + TASK1_USERDATA_SCORE))
echo -e "${BLUE}>>> TASK 1 TOTAL: $TASK1_SCORE / 25${NC}"
echo ""
echo ""

# ============================================
# TASK 2: Auto Scaling with Application Load Balancer (25 marks)
# ============================================
echo -e "${BLUE}### TASK 2: Auto Scaling with Application Load Balancer (25 marks) ###${NC}"
echo ""

# Criteria 1: ALB exists (5 marks)
echo "Criteria 1: ALB Exists (5 marks)"
echo "---------------------------------"

ALB_NAME="alb-${STUDENT_NAME}"
echo "Checking for Application Load Balancer: $ALB_NAME"

ALB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName=='$ALB_NAME'].LoadBalancerArn" --output text 2>/dev/null)

if [ -n "$ALB_ARN" ]; then
    ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text)
    ALB_SCHEME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].Scheme' --output text)
    
    if [ "$ALB_SCHEME" == "internet-facing" ]; then
        echo -e "${GREEN}✓ ALB created (internet-facing)${NC}"
        echo -e "${GREEN}✓ DNS: $ALB_DNS${NC}"
        TASK2_ALB_SCORE=5
    else
        echo -e "${YELLOW}⚠ ALB exists but is internal (not internet-facing)${NC}"
        TASK2_ALB_SCORE=3
    fi
else
    echo -e "${RED}✗ No ALB found${NC}"
    TASK2_ALB_SCORE=0
    ALB_DNS=""
fi

echo -e "${YELLOW}Score: $TASK2_ALB_SCORE / 5${NC}"
echo ""

# Criteria 2: Target Group exists & healthy (5 marks)
echo "Criteria 2: Target Group Exists & Healthy (5 marks)"
echo "----------------------------------------------------"

TG_NAME="tg-${STUDENT_NAME}"
echo "Checking for Target Group: $TG_NAME"

TG_ARN=$(aws elbv2 describe-target-groups --query "TargetGroups[?TargetGroupName=='$TG_NAME'].TargetGroupArn" --output text 2>/dev/null)

if [ -n "$TG_ARN" ]; then
    echo -e "${GREEN}✓ Target Group found${NC}"
    
    # Check if targets are registered and healthy
    TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" 2>/dev/null)
    HEALTHY_COUNT=$(echo "$TARGET_HEALTH" | jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length' 2>/dev/null || echo "0")
    TOTAL_TARGETS=$(echo "$TARGET_HEALTH" | jq '.TargetHealthDescriptions | length' 2>/dev/null || echo "0")
    
    if [ "$HEALTHY_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Target Group has $HEALTHY_COUNT healthy target(s) out of $TOTAL_TARGETS${NC}"
        TASK2_TG_SCORE=5
    elif [ "$TOTAL_TARGETS" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Target Group has targets but none are healthy${NC}"
        TASK2_TG_SCORE=3
    else
        echo -e "${YELLOW}⚠ Target Group exists but no targets registered${NC}"
        TASK2_TG_SCORE=3
    fi
else
    echo -e "${RED}✗ No Target Group found${NC}"
    TASK2_TG_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK2_TG_SCORE / 5${NC}"
echo ""

# Criteria 3: Auto Scaling Group exists & linked (5 marks)
echo "Criteria 3: Auto Scaling Group Exists & Linked (5 marks)"
echo "---------------------------------------------------------"

ASG_NAME="asg-${STUDENT_NAME}"
echo "Checking for Auto Scaling Group: $ASG_NAME"

ASG_DATA=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0]' 2>/dev/null)

if [ "$(echo "$ASG_DATA" | jq -r '.AutoScalingGroupName // empty')" == "$ASG_NAME" ]; then
    echo -e "${GREEN}✓ Auto Scaling Group found${NC}"
    
    # Check if linked to Launch Template
    ASG_LT=$(echo "$ASG_DATA" | jq -r '.LaunchTemplate.LaunchTemplateName // .MixedInstancesPolicy.LaunchTemplate.LaunchTemplateSpecification.LaunchTemplateName // empty')
    
    # Check if linked to Target Group
    ASG_TG=$(echo "$ASG_DATA" | jq -r '.TargetGroupARNs[]? // empty' | head -n 1)
    
    # Check AZ count
    AZ_COUNT=$(echo "$ASG_DATA" | jq -r '.AvailabilityZones | length')
    
    if [ "$ASG_LT" == "$LT_NAME" ] && [ -n "$ASG_TG" ] && [ "$AZ_COUNT" -ge 2 ]; then
        echo -e "${GREEN}✓ ASG correctly linked to Launch Template and Target Group${NC}"
        echo -e "${GREEN}✓ Spans $AZ_COUNT Availability Zones${NC}"
        TASK2_ASG_SCORE=5
    elif [ "$ASG_LT" == "$LT_NAME" ] || [ -n "$ASG_TG" ]; then
        echo -e "${YELLOW}⚠ ASG partially configured (missing LT or TG link, or wrong AZ)${NC}"
        TASK2_ASG_SCORE=3
    else
        echo -e "${YELLOW}⚠ ASG exists but misconfigured${NC}"
        TASK2_ASG_SCORE=3
    fi
else
    echo -e "${RED}✗ No Auto Scaling Group found${NC}"
    TASK2_ASG_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK2_ASG_SCORE / 5${NC}"
echo ""

# Criteria 4: ASG scaling configuration (5 marks)
echo "Criteria 4: ASG Scaling Configuration (5 marks)"
echo "------------------------------------------------"

if [ "$(echo "$ASG_DATA" | jq -r '.AutoScalingGroupName // empty')" == "$ASG_NAME" ]; then
    MIN=$(echo "$ASG_DATA" | jq -r '.MinSize')
    DESIRED=$(echo "$ASG_DATA" | jq -r '.DesiredCapacity')
    MAX=$(echo "$ASG_DATA" | jq -r '.MaxSize')
    
    echo "  Min: $MIN, Desired: $DESIRED, Max: $MAX"
    
    if [ "$MIN" == "1" ] && [ "$DESIRED" == "2" ] && [ "$MAX" == "4" ]; then
        echo -e "${GREEN}✓ Correct scaling configuration (Min=1, Desired=2, Max=4)${NC}"
        TASK2_CONFIG_SCORE=5
    elif [ -n "$MIN" ] && [ -n "$DESIRED" ] && [ -n "$MAX" ]; then
        echo -e "${YELLOW}⚠ Scaling configuration exists but numbers incorrect${NC}"
        echo -e "${YELLOW}  Expected: Min=1, Desired=2, Max=4${NC}"
        TASK2_CONFIG_SCORE=3
    else
        echo -e "${RED}✗ No scaling configuration${NC}"
        TASK2_CONFIG_SCORE=0
    fi
else
    echo -e "${RED}✗ Cannot check configuration (no ASG)${NC}"
    TASK2_CONFIG_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK2_CONFIG_SCORE / 5${NC}"
echo ""

# Criteria 5: Web page accessible via ALB DNS (5 marks)
echo "Criteria 5: Web Page Accessible via ALB DNS (5 marks)"
echo "------------------------------------------------------"

if [ -n "$ALB_DNS" ]; then
    echo "Testing ALB DNS: $ALB_DNS"
    
    # Try to fetch the page
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://$ALB_DNS" 2>/dev/null || echo "000")
    
    if [ "$HTTP_RESPONSE" == "200" ]; then
        echo -e "${GREEN}✓ ALB DNS is accessible (HTTP 200)${NC}"
        
        # Try to get page content
        PAGE_CONTENT=$(curl -s --connect-timeout 10 "http://$ALB_DNS" 2>/dev/null || echo "")
        
        # Check for student name pattern
        if echo "$PAGE_CONTENT" | grep -E "[A-Z][a-z]+ [A-Z][a-z]+|Welcome|${STUDENT_NAME}" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Website shows correct webpage with student name${NC}"
            TASK3_VERIFY_SCORE=5
        elif [ -n "$PAGE_CONTENT" ]; then
            echo -e "${YELLOW}⚠ Website accessible but student name or content missing${NC}"
            TASK3_VERIFY_SCORE=3
        else
            echo -e "${RED}✗ Website accessible but no content${NC}"
            TASK3_VERIFY_SCORE=0
        fi
    else
        echo -e "${RED}✗ Website not accessible (HTTP $HTTP_RESPONSE)${NC}"
        TASK3_VERIFY_SCORE=0
    fi
else
    echo -e "${RED}✗ Cannot verify website (no bucket or endpoint)${NC}"
    TASK3_VERIFY_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK3_VERIFY_SCORE / 5${NC}"
echo ""

TASK3_SCORE=$((TASK3_BUCKET_SCORE + TASK3_HOSTING_SCORE + TASK3_INDEX_SCORE + TASK3_POLICY_SCORE + TASK3_VERIFY_SCORE))
echo -e "${BLUE}>>> TASK 3 TOTAL: $TASK3_SCORE / 25${NC}"
echo ""
echo ""

# ============================================
# TASK 4: Database Integration using RDS MySQL (25 marks)
# ============================================
echo -e "${BLUE}### TASK 4: Database Integration using RDS MySQL (25 marks) ###${NC}"
echo ""

# Criteria 1: RDS instance created (5 marks)
echo "Criteria 1: RDS Instance Created (5 marks)"
echo "-------------------------------------------"

RDS_NAME="rds-${STUDENT_NAME}"
echo "Checking for RDS instance: $RDS_NAME"

RDS_DATA=$(aws rds describe-db-instances --db-instance-identifier "$RDS_NAME" 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ RDS instance found${NC}"
    
    ENGINE=$(echo "$RDS_DATA" | jq -r '.DBInstances[0].Engine')
    INSTANCE_CLASS=$(echo "$RDS_DATA" | jq -r '.DBInstances[0].DBInstanceClass')
    RDS_STATUS=$(echo "$RDS_DATA" | jq -r '.DBInstances[0].DBInstanceStatus')
    RDS_ENDPOINT=$(echo "$RDS_DATA" | jq -r '.DBInstances[0].Endpoint.Address // empty')
    
    echo "  Engine: $ENGINE"
    echo "  Instance Class: $INSTANCE_CLASS"
    echo "  Status: $RDS_STATUS"
    
    if [ "$ENGINE" == "mysql" ] && [ "$INSTANCE_CLASS" == "db.t3.medium" ]; then
        echo -e "${GREEN}✓ Correct configuration (MySQL, db.t3.medium)${NC}"
        TASK4_RDS_SCORE=5
    elif [ "$ENGINE" == "mysql" ] || [ "$INSTANCE_CLASS" == "db.t3.medium" ]; then
        echo -e "${YELLOW}⚠ Minor configuration issue (engine or instance class incorrect)${NC}"
        TASK4_RDS_SCORE=3
    else
        echo -e "${YELLOW}⚠ RDS exists but configuration issues${NC}"
        TASK4_RDS_SCORE=3
    fi
else
    echo -e "${RED}✗ No RDS instance found${NC}"
    TASK4_RDS_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK4_RDS_SCORE / 5${NC}"
echo ""

# Criteria 2: Security group configured (5 marks)
echo "Criteria 2: Security Group Configured (5 marks)"
echo "------------------------------------------------"

if [ $? -eq 0 ] && [ -n "$RDS_DATA" ]; then
    VPC_SG=$(echo "$RDS_DATA" | jq -r '.DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId // empty')
    
    if [ -n "$VPC_SG" ]; then
        echo -e "${GREEN}✓ Security group attached: $VPC_SG${NC}"
        
        # Check for MySQL port 3306 inbound rule
        SG_RULES=$(aws ec2 describe-security-groups --group-ids "$VPC_SG" --query 'SecurityGroups[0].IpPermissions' 2>/dev/null)
        
        HAS_3306=false
        PROPER_SOURCE=false
        
        # Check if port 3306 is allowed
        if echo "$SG_RULES" | jq -e '.[] | select(.FromPort == 3306 and .ToPort == 3306)' > /dev/null 2>&1; then
            HAS_3306=true
            echo -e "${GREEN}✓ Inbound rule allows MySQL port 3306${NC}"
            
            # Check source (should be from EC2 security group or limited CIDR, not 0.0.0.0/0)
            SOURCES=$(echo "$SG_RULES" | jq -r '.[] | select(.FromPort == 3306) | .IpRanges[]?.CidrIp // .UserIdGroupPairs[]?.GroupId // empty')
            
            if echo "$SOURCES" | grep -q "sg-"; then
                echo -e "${GREEN}✓ Source restricted to security group (EC2)${NC}"
                PROPER_SOURCE=true
                TASK4_SG_SCORE=5
            elif echo "$SOURCES" | grep -v "0.0.0.0/0" > /dev/null; then
                echo -e "${GREEN}✓ Source restricted to specific CIDR${NC}"
                PROPER_SOURCE=true
                TASK4_SG_SCORE=5
            else
                echo -e "${YELLOW}⚠ Port 3306 open but source not properly restricted (may be 0.0.0.0/0)${NC}"
                TASK4_SG_SCORE=3
            fi
        else
            echo -e "${RED}✗ No inbound rule for MySQL port 3306${NC}"
            TASK4_SG_SCORE=0
        fi
    else
        echo -e "${RED}✗ No security group configured${NC}"
        TASK4_SG_SCORE=0
    fi
else
    echo -e "${RED}✗ Cannot check security group (no RDS)${NC}"
    TASK4_SG_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK4_SG_SCORE / 5${NC}"
echo ""

# Criteria 3: EC2 successfully connects to RDS (10 marks)
echo "Criteria 3: EC2 Successfully Connects to RDS (10 marks)"
echo "--------------------------------------------------------"
echo -e "${YELLOW}NOTE: This criterion requires manual verification or student screenshot${NC}"
echo -e "${YELLOW}      Automated testing requires SSH access to EC2 instance${NC}"
echo ""
echo "  To manually verify:"
echo "  1. SSH into EC2 instance"
echo "  2. Run: mysql -h <RDS-endpoint> -u admin -p"
echo "  3. Enter password: admin12345"
echo "  4. Create test database and verify"
echo ""

if [ -n "$RDS_ENDPOINT" ]; then
    echo -e "${GREEN}✓ RDS endpoint available: $RDS_ENDPOINT${NC}"
    echo -e "${YELLOW}⚠ Auto-grade: Assuming connection needs manual verification${NC}"
    echo -e "${YELLOW}  Award 10 marks if screenshot shows successful connection${NC}"
    echo -e "${YELLOW}  Award 7 marks if connection works but minor errors${NC}"
    echo -e "${YELLOW}  Award 4 marks if connection attempted but failed${NC}"
    echo -e "${YELLOW}  Award 0 marks if no connection attempted${NC}"
    TASK4_CONNECT_SCORE=0  # Set to 0, instructor must verify manually
else
    echo -e "${RED}✗ No RDS endpoint available${NC}"
    TASK4_CONNECT_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK4_CONNECT_SCORE / 10 (MANUAL VERIFICATION REQUIRED)${NC}"
echo ""

# Criteria 4: SQL query results verified (5 marks)
echo "Criteria 4: SQL Query Results Verified (5 marks)"
echo "-------------------------------------------------"
echo -e "${YELLOW}NOTE: This criterion requires manual verification or student screenshot${NC}"
echo ""
echo "  To manually verify:"
echo "  1. Check if student created testdb"
echo "  2. Verify SHOW DATABASES output in screenshot"
echo ""
echo -e "${YELLOW}  Award 5 marks if SQL queries executed successfully${NC}"
echo -e "${YELLOW}  Award 3 marks if queries executed but incomplete/partial${NC}"
echo -e "${YELLOW}  Award 0 marks if queries not executed${NC}"

TASK4_SQL_SCORE=0  # Set to 0, instructor must verify manually

echo -e "${YELLOW}Score: $TASK4_SQL_SCORE / 5 (MANUAL VERIFICATION REQUIRED)${NC}"
echo ""

TASK4_SCORE=$((TASK4_RDS_SCORE + TASK4_SG_SCORE + TASK4_CONNECT_SCORE + TASK4_SQL_SCORE))
echo -e "${BLUE}>>> TASK 4 TOTAL: $TASK4_SCORE / 25 (15 marks auto, 10 marks manual)${NC}"
echo ""
echo ""

# ============================================
# FINAL REPORT
# ============================================
TOTAL_SCORE=$((TASK1_SCORE + TASK2_SCORE + TASK3_SCORE + TASK4_SCORE))

echo "=========================================="
echo "        FINAL GRADING SUMMARY"
echo "=========================================="
echo ""
echo "Student: $STUDENT_NAME"
echo "Grading completed: $(date)"
echo ""
echo "=========================================="
echo "DETAILED BREAKDOWN"
echo "=========================================="
echo ""
echo "TASK 1: EC2 Dynamic Web Server (25 marks)"
echo "  - EC2 Instance Launched:      $TASK1_EC2_SCORE / 10"
echo "  - Instance Type:              $TASK1_TYPE_SCORE / 5"
echo "  - User Data Script:           $TASK1_USERDATA_SCORE / 10"
echo "  TASK 1 SUBTOTAL:              $TASK1_SCORE / 25"
echo ""
echo "TASK 2: Auto Scaling & ALB (25 marks)"
echo "  - ALB Exists:                 $TASK2_ALB_SCORE / 5"
echo "  - Target Group & Healthy:     $TASK2_TG_SCORE / 5"
echo "  - ASG Exists & Linked:        $TASK2_ASG_SCORE / 5"
echo "  - ASG Scaling Config:         $TASK2_CONFIG_SCORE / 5"
echo "  - Web Page via ALB DNS:       $TASK2_ACCESS_SCORE / 5"
echo "  TASK 2 SUBTOTAL:              $TASK2_SCORE / 25"
echo ""
echo "TASK 3: S3 Static Website (25 marks)"
echo "  - S3 Bucket Exists:           $TASK3_BUCKET_SCORE / 5"
echo "  - Static Hosting Enabled:     $TASK3_HOSTING_SCORE / 5"
echo "  - index.html with Name:       $TASK3_INDEX_SCORE / 5"
echo "  - Public Read Permission:     $TASK3_POLICY_SCORE / 5"
echo "  - Website Verified:           $TASK3_VERIFY_SCORE / 5"
echo "  TASK 3 SUBTOTAL:              $TASK3_SCORE / 25"
echo ""
echo "TASK 4: RDS MySQL Database (25 marks)"
echo "  - RDS Instance Created:       $TASK4_RDS_SCORE / 5"
echo "  - Security Group Config:      $TASK4_SG_SCORE / 5"
echo "  - EC2 Connects to RDS:        $TASK4_CONNECT_SCORE / 10 *MANUAL*"
echo "  - SQL Query Results:          $TASK4_SQL_SCORE / 5 *MANUAL*"
echo "  TASK 4 SUBTOTAL:              $TASK4_SCORE / 25"
echo ""
echo "=========================================="
echo -e "${BLUE}TOTAL SCORE: $TOTAL_SCORE / 100${NC}"
echo "=========================================="
echo ""

# Calculate percentage and grade
PERCENTAGE=$((TOTAL_SCORE * 100 / MAX_SCORE))
echo "Percentage: $PERCENTAGE%"

if [ $PERCENTAGE -ge 85 ]; then
    GRADE="A"
elif [ $PERCENTAGE -ge 75 ]; then
    GRADE="B+"
elif [ $PERCENTAGE -ge 70 ]; then
    GRADE="B"
elif [ $PERCENTAGE -ge 65 ]; then
    GRADE="C+"
elif [ $PERCENTAGE -ge 60 ]; then
    GRADE="C"
elif [ $PERCENTAGE -ge 50 ]; then
    GRADE="D"
else
    GRADE="F"
fi

echo "Estimated Grade: $GRADE"
echo ""
echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
echo "• Task 4 requires manual verification (15 marks auto-graded, 10 manual)"
echo "• Please review screenshots for EC2-RDS connection and SQL queries"
echo "• Add manual scores to this total for final grade"
echo ""
echo "=========================================="

# Save detailed report
REPORT_FILE="BMIT3273_grade_${STUDENT_NAME}_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "=========================================="
    echo "BMIT3273 CLOUD COMPUTING - GRADING REPORT"
    echo "Based on Official Marking Scheme 202509"
    echo "=========================================="
    echo ""
    echo "Student Name: $STUDENT_NAME"
    echo "Grading Date: $(date)"
    echo ""
    echo "=========================================="
    echo "DETAILED BREAKDOWN"
    echo "=========================================="
    echo ""
    echo "TASK 1: EC2 Dynamic Web Server (25 marks)"
    echo "  - EC2 Instance Launched:      $TASK1_EC2_SCORE / 10"
    echo "  - Instance Type:              $TASK1_TYPE_SCORE / 5"
    echo "  - User Data Script:           $TASK1_USERDATA_SCORE / 10"
    echo "  TASK 1 SUBTOTAL:              $TASK1_SCORE / 25"
    echo ""
    echo "TASK 2: Auto Scaling & ALB (25 marks)"
    echo "  - ALB Exists:                 $TASK2_ALB_SCORE / 5"
    echo "  - Target Group & Healthy:     $TASK2_TG_SCORE / 5"
    echo "  - ASG Exists & Linked:        $TASK2_ASG_SCORE / 5"
    echo "  - ASG Scaling Config:         $TASK2_CONFIG_SCORE / 5"
    echo "  - Web Page via ALB DNS:       $TASK2_ACCESS_SCORE / 5"
    echo "  TASK 2 SUBTOTAL:              $TASK2_SCORE / 25"
    echo ""
    echo "TASK 3: S3 Static Website (25 marks)"
    echo "  - S3 Bucket Exists:           $TASK3_BUCKET_SCORE / 5"
    echo "  - Static Hosting Enabled:     $TASK3_HOSTING_SCORE / 5"
    echo "  - index.html with Name:       $TASK3_INDEX_SCORE / 5"
    echo "  - Public Read Permission:     $TASK3_POLICY_SCORE / 5"
    echo "  - Website Verified:           $TASK3_VERIFY_SCORE / 5"
    echo "  TASK 3 SUBTOTAL:              $TASK3_SCORE / 25"
    echo ""
    echo "TASK 4: RDS MySQL Database (25 marks)"
    echo "  - RDS Instance Created:       $TASK4_RDS_SCORE / 5"
    echo "  - Security Group Config:      $TASK4_SG_SCORE / 5"
    echo "  - EC2 Connects to RDS:        $TASK4_CONNECT_SCORE / 10 *MANUAL*"
    echo "  - SQL Query Results:          $TASK4_SQL_SCORE / 5 *MANUAL*"
    echo "  TASK 4 SUBTOTAL:              $TASK4_SCORE / 25"
    echo ""
    echo "=========================================="
    echo "AUTOMATED SCORE:  $TOTAL_SCORE / 100"
    echo "Percentage: $PERCENTAGE%"
    echo "Estimated Grade: $GRADE"
    echo ""
    echo "MANUAL VERIFICATION PENDING:"
    echo "  - Task 4: EC2-RDS Connection (10 marks)"
    echo "  - Task 4: SQL Query Results (5 marks)"
    echo ""
    echo "Final score after manual review: ____ / 100"
    echo "=========================================="
} > "$REPORT_FILE"

echo ""
echo "Report saved to: $REPORT_FILE"
echo ""
echo "To view the report:"
echo "  cat $REPORT_FILE"
echo ""
echo "To download the report from CloudShell:"
echo "  1. Click 'Actions' → 'Download file'"
echo "  2. Enter path: $REPORT_FILE"
echo ""
echo "=========================================="|Welcome" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Web page shows student name${NC}"
            TASK2_ACCESS_SCORE=5
        else
            echo -e "${YELLOW}⚠ Web page accessible but student name not detected${NC}"
            TASK2_ACCESS_SCORE=3
        fi
    else
        echo -e "${RED}✗ ALB DNS not accessible (HTTP $HTTP_RESPONSE)${NC}"
        TASK2_ACCESS_SCORE=0
    fi
else
    echo -e "${RED}✗ No ALB DNS to test${NC}"
    TASK2_ACCESS_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK2_ACCESS_SCORE / 5${NC}"
echo ""

TASK2_SCORE=$((TASK2_ALB_SCORE + TASK2_TG_SCORE + TASK2_ASG_SCORE + TASK2_CONFIG_SCORE + TASK2_ACCESS_SCORE))
echo -e "${BLUE}>>> TASK 2 TOTAL: $TASK2_SCORE / 25${NC}"
echo ""
echo ""

# ============================================
# TASK 3: Secure Static Website Hosting with S3 (25 marks)
# ============================================
echo -e "${BLUE}### TASK 3: Secure Static Website Hosting with S3 (25 marks) ###${NC}"
echo ""

# Criteria 1: S3 bucket exists (5 marks)
echo "Criteria 1: S3 Bucket Exists (5 marks)"
echo "---------------------------------------"

SEARCH_NAME=$(echo "s3-${STUDENT_NAME}" | tr '[:upper:]' '[:lower:]')
echo "Searching for S3 bucket with pattern: $SEARCH_NAME"

BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?contains(Name, '$SEARCH_NAME')].Name" --output text 2>/dev/null | head -n 1)

if [ -n "$BUCKET_NAME" ]; then
    echo -e "${GREEN}✓ S3 bucket found: $BUCKET_NAME${NC}"
    TASK3_BUCKET_SCORE=5
else
    # Try broader search
    BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?contains(to_lower(Name), '$(echo $STUDENT_NAME | tr '-' ' ' | awk '{print tolower($1)}')') || contains(to_lower(Name), '$(echo $STUDENT_NAME | awk -F'-' '{print tolower($2)}' 2>/dev/null)')].Name" --output text 2>/dev/null | head -n 1)
    
    if [ -n "$BUCKET_NAME" ]; then
        echo -e "${YELLOW}⚠ S3 bucket found but unclear naming: $BUCKET_NAME${NC}"
        TASK3_BUCKET_SCORE=3
    else
        echo -e "${RED}✗ No S3 bucket found${NC}"
        TASK3_BUCKET_SCORE=0
    fi
fi

echo -e "${YELLOW}Score: $TASK3_BUCKET_SCORE / 5${NC}"
echo ""

# Criteria 2: Static website hosting enabled (5 marks)
echo "Criteria 2: Static Website Hosting Enabled (5 marks)"
echo "-----------------------------------------------------"

if [ -n "$BUCKET_NAME" ]; then
    WEBSITE_CONFIG=$(aws s3api get-bucket-website --bucket "$BUCKET_NAME" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        WEBSITE_ENDPOINT=$(aws s3api get-bucket-location --bucket "$BUCKET_NAME" --output text 2>/dev/null)
        REGION=$(aws s3api get-bucket-location --bucket "$BUCKET_NAME" --query 'LocationConstraint' --output text 2>/dev/null)
        
        if [ "$REGION" == "None" ] || [ -z "$REGION" ]; then
            REGION="us-east-1"
        fi
        
        ENDPOINT_URL="http://${BUCKET_NAME}.s3-website-${REGION}.amazonaws.com"
        
        echo -e "${GREEN}✓ Static website hosting enabled${NC}"
        echo -e "${GREEN}✓ Endpoint: $ENDPOINT_URL${NC}"
        
        # Test endpoint accessibility
        HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$ENDPOINT_URL" 2>/dev/null || echo "000")
        
        if [ "$HTTP_RESPONSE" == "200" ]; then
            echo -e "${GREEN}✓ Website endpoint is accessible${NC}"
            TASK3_HOSTING_SCORE=5
        else
            echo -e "${YELLOW}⚠ Hosting enabled but endpoint not accessible (HTTP $HTTP_RESPONSE)${NC}"
            TASK3_HOSTING_SCORE=3
        fi
    else
        echo -e "${RED}✗ Static website hosting not enabled${NC}"
        TASK3_HOSTING_SCORE=0
    fi
else
    echo -e "${RED}✗ Cannot check hosting (no bucket)${NC}"
    TASK3_HOSTING_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK3_HOSTING_SCORE / 5${NC}"
echo ""

# Criteria 3: index.html uploaded with student name (5 marks)
echo "Criteria 3: index.html Uploaded with Student Name (5 marks)"
echo "------------------------------------------------------------"

if [ -n "$BUCKET_NAME" ]; then
    INDEX_EXISTS=$(aws s3api head-object --bucket "$BUCKET_NAME" --key "index.html" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ index.html file exists${NC}"
        
        # Try to download and check content
        INDEX_CONTENT=$(aws s3 cp "s3://${BUCKET_NAME}/index.html" - 2>/dev/null || echo "")
        
        if echo "$INDEX_CONTENT" | grep -E "[A-Z][a-z]+ [A-Z][a-z]+|Welcome|${STUDENT_NAME}" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ index.html contains student name${NC}"
            TASK3_INDEX_SCORE=5
        elif [ -n "$INDEX_CONTENT" ]; then
            echo -e "${YELLOW}⚠ index.html exists but student name missing or generic content${NC}"
            TASK3_INDEX_SCORE=3
        else
            echo -e "${YELLOW}⚠ index.html exists but cannot verify content${NC}"
            TASK3_INDEX_SCORE=3
        fi
    else
        echo -e "${RED}✗ index.html file not found${NC}"
        TASK3_INDEX_SCORE=0
    fi
else
    echo -e "${RED}✗ Cannot check file (no bucket)${NC}"
    TASK3_INDEX_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK3_INDEX_SCORE / 5${NC}"
echo ""

# Criteria 4: Public Read permission / bucket policy (5 marks)
echo "Criteria 4: Public Read Permission / Bucket Policy (5 marks)"
echo "-------------------------------------------------------------"

if [ -n "$BUCKET_NAME" ]; then
    # Check bucket policy
    BUCKET_POLICY=$(aws s3api get-bucket-policy --bucket "$BUCKET_NAME" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Bucket policy configured${NC}"
        
        # Check if policy allows public GetObject
        if echo "$BUCKET_POLICY" | jq -r '.Policy' | jq -r '.Statement[].Action' | grep -q "GetObject"; then
            echo -e "${GREEN}✓ Policy allows GetObject action${NC}"
            TASK3_POLICY_SCORE=5
        else
            echo -e "${YELLOW}⚠ Policy exists but may not allow public read${NC}"
            TASK3_POLICY_SCORE=3
        fi
    else
        # Check public access block settings
        PUBLIC_BLOCK=$(aws s3api get-public-access-block --bucket "$BUCKET_NAME" 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo -e "${GREEN}✓ Public access block disabled (allows public access)${NC}"
            TASK3_POLICY_SCORE=3
        else
            BLOCK_ALL=$(echo "$PUBLIC_BLOCK" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls')
            if [ "$BLOCK_ALL" == "false" ]; then
                echo -e "${YELLOW}⚠ Public access partially configured${NC}"
                TASK3_POLICY_SCORE=3
            else
                echo -e "${RED}✗ Public access blocked or not configured${NC}"
                TASK3_POLICY_SCORE=0
            fi
        fi
    fi
else
    echo -e "${RED}✗ Cannot check policy (no bucket)${NC}"
    TASK3_POLICY_SCORE=0
fi

echo -e "${YELLOW}Score: $TASK3_POLICY_SCORE / 5${NC}"
echo ""

# Criteria 5: Website verified in browser (5 marks)
echo "Criteria 5: Website Verified in Browser (5 marks)"
echo "--------------------------------------------------"

if [ -n "$BUCKET_NAME" ] && [ -n "$ENDPOINT_URL" ]; then
    echo "Testing S3 website endpoint: $ENDPOINT_URL"
    
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$ENDPOINT_URL" 2>/dev/null || echo "000")
    
    if [ "$HTTP_RESPONSE" == "200" ]; then
        PAGE_CONTENT=$(curl -s --connect-timeout 10 "$ENDPOINT_URL" 2>/dev/null || echo "")
        
        if echo "$PAGE_CONTENT" | grep -E "[A-Z][a-z]+ [A-Z][a-z]+
