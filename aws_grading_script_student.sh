#!/bin/bash
# AWS Practical Assessment Grading Script (Silent Version)
# Only shows final score

read -p "Enter your full name (e.g., LowChoonKeat): " STUDENT_NAME
NAME_LOWER=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]')

REGION=$(aws configure get region)
SCORE=0

LT_NAME="lt-$NAME_LOWER"
ALB_NAME="alb-$NAME_LOWER"
TG_NAME="tg-$NAME_LOWER"
ASG_NAME="asg-$NAME_LOWER"
BUCKET_NAME="s3-$NAME_LOWER"
WEBSITE_URL="http://$BUCKET_NAME.s3-website-$REGION.amazonaws.com"

########################################
# Task 1: EC2 + Launch Template (30%)
########################################
LT=$(aws ec2 describe-launch-templates --query "LaunchTemplates[?LaunchTemplateName=='$LT_NAME']" --output json 2>/dev/null)
if [[ "$LT" != "[]" && "$LT" != "" ]]; then
    SCORE=$((SCORE+10))

    INSTANCE_TYPE=$(aws ec2 describe-launch-template-versions --launch-template-name "$LT_NAME" --versions "\$Latest" \
        --query "LaunchTemplateVersions[0].LaunchTemplateData.InstanceType" --output text 2>/dev/null)
    [[ "$INSTANCE_TYPE" == "t3.micro" ]] && SCORE=$((SCORE+10))

    USER_DATA=$(aws ec2 describe-launch-template-versions --launch-template-name "$LT_NAME" --versions "\$Latest" \
        --query "LaunchTemplateVersions[0].LaunchTemplateData.UserData" --output text 2>/dev/null)
    [[ "$USER_DATA" != "None" && "$USER_DATA" != "" ]] && SCORE=$((SCORE+10))
fi

########################################
# Task 2: ALB + ASG + TG (35%)
########################################
ALB=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --query "LoadBalancers[0].DNSName" --output text 2>/dev/null)
if [[ "$ALB" != "None" && "$ALB" != "" ]]; then
    SCORE=$((SCORE+7))
    DNS=$(curl -s "http://$ALB")
    [[ "$DNS" == *"$STUDENT_NAME"* ]] && SCORE=$((SCORE+7))
fi

TG=$(aws elbv2 describe-target-groups --names "$TG_NAME" --query "TargetGroups[0].TargetGroupName" --output text 2>/dev/null)
[[ "$TG" != "None" && "$TG" != "" ]] && SCORE=$((SCORE+7))

ASG=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null)
if [[ "$ASG" != "None" && "$ASG" != "" ]]; then
    SCORE=$((SCORE+7))
    MIN=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query "AutoScalingGroups[0].MinSize" --output text 2>/dev/null)
    DESIRED=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query "AutoScalingGroups[0].DesiredCapacity" --output text 2>/dev/null)
    MAX=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query "AutoScalingGroups[0].MaxSize" --output text 2>/dev/null)
    [[ "$MIN" -eq 1 && "$DESIRED" -eq 1 && "$MAX" -eq 3 ]] && SCORE=$((SCORE+7))
fi

########################################
# Task 3: S3 Static Website (35%)
########################################
if aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
    SCORE=$((SCORE+5))

    aws s3api get-bucket-website --bucket "$BUCKET_NAME" >/dev/null 2>&1 && SCORE=$((SCORE+8))
    aws s3 ls "s3://$BUCKET_NAME/index.html" >/dev/null 2>&1 && SCORE=$((SCORE+7))

    CONTENT=$(curl -s "$WEBSITE_URL")
    [[ "$CONTENT" == *"$STUDENT_NAME"* ]] && SCORE=$((SCORE+5))

    POLICY=$(aws s3api get-bucket-policy --bucket "$BUCKET_NAME" --query Policy --output text 2>/dev/null)
    [[ "$POLICY" == *"Allow"* ]] && SCORE=$((SCORE+5))

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WEBSITE_URL")
    [[ "$HTTP_STATUS" == "200" ]] && SCORE=$((SCORE+5))
fi

########################################
# Final Score
########################################
echo "Final Score: $SCORE / 100"
