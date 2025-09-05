#!/bin/bash
# AWS Practical Assessment Grading Script
# Updated with improved S3 Task 3 logic (bucket policy vs public access)

echo "=== AWS Practical Assessment Grading Script ==="
read -p "Enter your full name (e.g., LowChoonKeat): " STUDENT_NAME
NAME_LOWER=$(echo "$STUDENT_NAME" | tr '[:upper:]' '[:lower:]')

REPORT="grading_report.txt"
SCORE=0
echo "Grading report for $STUDENT_NAME" > $REPORT
echo "----------------------------------" >> $REPORT

########################################
# Task 1: EC2 + Launch Template (30%)
########################################
echo -e "\n[Task 1: EC2 + Launch Template (30%)]"

LT_NAME="lt-$NAME_LOWER"
LT=$(aws ec2 describe-launch-templates --query "LaunchTemplates[?LaunchTemplateName=='$LT_NAME']" --output json 2>/dev/null)

if [[ "$LT" != "[]" && "$LT" != "" ]]; then
    echo "✅ Launch Template '$LT_NAME' found"
    SCORE=$((SCORE+10))

    INSTANCE_TYPE=$(aws ec2 describe-launch-template-versions --launch-template-name "$LT_NAME" --versions "\$Latest" \
        --query "LaunchTemplateVersions[0].LaunchTemplateData.InstanceType" --output text 2>/dev/null)
    if [[ "$INSTANCE_TYPE" == "t3.micro" ]]; then
        echo "✅ Launch Template uses t3.micro"
        SCORE=$((SCORE+10))
    else
        echo "❌ Wrong instance type ($INSTANCE_TYPE)"
    fi

    IMAGE_ID=$(aws ec2 describe-launch-template-versions --launch-template-name "$LT_NAME" --versions "\$Latest" \
        --query "LaunchTemplateVersions[0].LaunchTemplateData.ImageId" --output text 2>/dev/null)
    if [[ "$IMAGE_ID" != "None" && "$IMAGE_ID" != "" ]]; then
        echo "✅ AMI ImageId set ($IMAGE_ID)"
    else
        echo "❌ AMI ImageId not set"
    fi

    USER_DATA=$(aws ec2 describe-launch-template-versions --launch-template-name "$LT_NAME" --versions "\$Latest" \
        --query "LaunchTemplateVersions[0].LaunchTemplateData.UserData" --output text 2>/dev/null)
    if [[ "$USER_DATA" != "None" && "$USER_DATA" != "" ]]; then
        echo "✅ Launch Template includes user data"
        SCORE=$((SCORE+10))
    else
        echo "❌ No user data in Launch Template"
    fi
else
    echo "❌ Launch Template '$LT_NAME' not found"
fi

########################################
# Task 2: ALB + ASG + TG (35%)
########################################
echo -e "\n[Task 2: ALB + ASG + TG (35%)]"

ALB_NAME="alb-$NAME_LOWER"
TG_NAME="tg-$NAME_LOWER"
ASG_NAME="asg-$NAME_LOWER"

ALB=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --query "LoadBalancers[0].DNSName" --output text 2>/dev/null)
if [[ "$ALB" != "None" && "$ALB" != "" ]]; then
    echo "✅ ALB '$ALB_NAME' exists"
    SCORE=$((SCORE+7))

    DNS=$(curl -s "http://$ALB")
    if echo "$DNS" | grep -q "$STUDENT_NAME"; then
        echo "✅ ALB DNS shows student name"
        SCORE=$((SCORE+7))
    else
        echo "❌ ALB DNS missing student name"
    fi
else
    echo "❌ ALB '$ALB_NAME' not found"
fi

TG=$(aws elbv2 describe-target-groups --names "$TG_NAME" --query "TargetGroups[0].TargetGroupName" --output text 2>/dev/null)
if [[ "$TG" != "None" && "$TG" != "" ]]; then
    echo "✅ Target Group '$TG_NAME' exists"
    SCORE=$((SCORE+7))
else
    echo "❌ Target Group '$TG_NAME' not found"
fi

ASG=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null)
if [[ "$ASG" != "None" && "$ASG" != "" ]]; then
    echo "✅ ASG '$ASG_NAME' exists"
    SCORE=$((SCORE+7))

    DESIRED=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query "AutoScalingGroups[0].DesiredCapacity" --output text 2>/dev/null)
    MIN=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query "AutoScalingGroups[0].MinSize" --output text 2>/dev/null)
    MAX=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query "AutoScalingGroups[0].MaxSize" --output text 2>/dev/null)

    if [[ "$MIN" -eq 1 && "$DESIRED" -eq 1 && "$MAX" -eq 3 ]]; then
        echo "✅ ASG scaling config is correct (1/3/1)"
        SCORE=$((SCORE+7))
    else
        echo "❌ Wrong ASG scaling config (Min:$MIN, Desired:$DESIRED, Max:$MAX)"
    fi
else
    echo "❌ ASG '$ASG_NAME' not found"
fi

########################################
# Task 3: S3 Static Website (35%)
########################################
echo -e "\n[Task 3: S3 Static Website (35%)]"

BUCKET_NAME="s3-$NAME_LOWER"
WEBSITE_URL="http://$BUCKET_NAME.s3-website-$(aws configure get region).amazonaws.com"

if aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
    echo "✅ S3 bucket '$BUCKET_NAME' found"
    SCORE=$((SCORE+5))

    if aws s3api get-bucket-website --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
        echo "✅ Static website hosting enabled"
        SCORE=$((SCORE+8))
    else
        echo "❌ Static website hosting not enabled"
    fi

    if aws s3 ls "s3://$BUCKET_NAME/index.html" >/dev/null 2>&1; then
        echo "✅ index.html uploaded"
        SCORE=$((SCORE+7))
    else
        echo "❌ index.html not found"
    fi

    CONTENT=$(curl -s "$WEBSITE_URL")
    if echo "$CONTENT" | grep -q "$STUDENT_NAME"; then
        echo "✅ S3 page shows student name"
        SCORE=$((SCORE+5))
    else
        echo "❌ S3 page missing student name"
    fi

    POLICY=$(aws s3api get-bucket-policy --bucket "$BUCKET_NAME" --query Policy --output text 2>/dev/null)
    if [[ "$POLICY" != "None" && "$POLICY" != "" && "$POLICY" == *"Allow"* ]]; then
        echo "✅ Bucket policy configured"
        SCORE=$((SCORE+5))
    else
        echo "❌ No valid bucket policy found"
    fi

    PUBLIC=$(aws s3api get-bucket-public-access-block --bucket "$BUCKET_NAME" --output json 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        BLOCK_ALL=$(echo "$PUBLIC" | jq '.PublicAccessBlockConfiguration.BlockPublicAcls or .PublicAccessBlockConfiguration.BlockPublicPolicy')
        if [[ "$BLOCK_ALL" == "true" ]]; then
            echo "❌ Public access block still enabled"
        else
            echo "✅ Public access block disabled"
            SCORE=$((SCORE+5))
        fi
    else
        # Fallback: check if website URL is accessible
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WEBSITE_URL")
        if [[ "$HTTP_STATUS" == "200" ]]; then
            echo "✅ Public access working (via website test)"
            SCORE=$((SCORE+5))
        else
            echo "⚠️ Could not confirm Public Access Block (partial +3)"
            SCORE=$((SCORE+3))
        fi
    fi
else
    echo "❌ Bucket '$BUCKET_NAME' not found"
fi

########################################
# Final Score
########################################
echo -e "\n============================="
echo "Final Score: $SCORE / 100"
echo "============================="

echo "Final Score: $SCORE / 100" >> $REPORT
echo "Report saved as: $REPORT"
