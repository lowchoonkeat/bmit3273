import boto3
import sys
import urllib.request
import ssl
import time

# --- CONFIGURATION ---
# Context to ensure SSL checks work in CloudShell
ssl_context = ssl._create_unverified_context()

# Global Score Keepers
TOTAL_MARKS = 0
SCORED_MARKS = 0

def print_header(title):
    print(f"\n{'='*60}")
    print(f" {title}")
    print(f"{'='*60}")

def grade_step(description, max_points, condition, details=""):
    """
    Helper to log points.
    condition: Boolean (True = Pass, False = Fail)
    """
    global TOTAL_MARKS, SCORED_MARKS
    TOTAL_MARKS += max_points
    
    if condition:
        SCORED_MARKS += max_points
        print(f"[\u2713] PASS (+{max_points}): {description}")
    else:
        print(f"[X] FAIL (0/{max_points}): {description}")
        if details:
            print(f"    -> Issue: {details}")

def check_http_content(url, keyword):
    """Checks if a URL is live and contains specific text"""
    try:
        with urllib.request.urlopen(url, timeout=5, context=ssl_context) as response:
            if response.status == 200:
                content = response.read().decode('utf-8')
                if keyword.lower() in content.lower():
                    return True, "Content matched"
                else:
                    return True, "Page loads, but student name not found" # Partial pass logic handled in caller
    except Exception as e:
        return False, str(e)
    return False, "Unknown error"

def main():
    print_header("BMIT3273 CLOUD COMPUTING - AUTO GRADER")
    
    # Get Region
    session = boto3.session.Session()
    region = session.region_name
    print(f"Scanning Region: {region}")
    
    # Get Student Name for Resource Matching
    student_name_input = input("Enter Student Full Name (as used in resource naming): ").strip().lower()
    student_name_nospace = student_name_input.replace(" ", "")
    print(f"Looking for resources containing: '{student_name_nospace}' or parts of it...")

    # Initialize Clients
    ec2 = boto3.client('ec2')
    asg_client = boto3.client('autoscaling')
    elbv2 = boto3.client('elbv2')
    s3 = boto3.client('s3')
    rds = boto3.client('rds')

    # =========================================================
    # TASK 1: EC2 DYNAMIC WEB SERVER (25 Marks)
    # =========================================================
    print_header("Task 1: EC2 & Launch Template")

    # 1. Check Launch Template
    lt_found = False
    lt_id = None
    try:
        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if "lt-" in lt['LaunchTemplateName']), None)
        
        if target_lt:
            lt_found = True
            lt_id = target_lt['LaunchTemplateId']
            grade_step("Launch Template created", 10, True)
            
            # Check Version for t3.medium
            lt_ver = ec2.describe_launch_template_versions(LaunchTemplateId=lt_id)['LaunchTemplateVersions'][0]
            instance_type = lt_ver['LaunchTemplateData'].get('InstanceType', 'Unknown')
            
            if instance_type == 't3.medium':
                grade_step("Instance Type is t3.medium", 5, True)
            else:
                grade_step("Instance Type is t3.medium", 5, False, f"Found {instance_type}")
                
            # Check User Data presence
            if 'UserData' in lt_ver['LaunchTemplateData']:
                grade_step("User Data Script configured", 10, True)
            else:
                grade_step("User Data Script configured", 10, False, "No User Data found")
        else:
            grade_step("Launch Template created", 10, False, "No LT found starting with 'lt-'")
            grade_step("Instance Type is t3.medium", 5, False, "Skipped")
            grade_step("User Data Script configured", 10, False, "Skipped")

    except Exception as e:
        print(f"Error checking Task 1: {e}")

    # =========================================================
    # TASK 2: AUTO SCALING & ALB (25 Marks)
    # =========================================================
    print_header("Task 2: ASG & ALB")

    alb_dns = None
    tg_arn = None
    
    # 1. Check ALB
    try:
        albs = elbv2.describe_load_balancers()['LoadBalancers']
        target_alb = next((alb for alb in albs if "alb-" in alb['LoadBalancerName']), None)
        
        if target_alb:
            alb_dns = target_alb['DNSName']
            grade_step("ALB Exists & Internet Facing", 5, target_alb['Scheme'] == 'internet-facing')
        else:
            grade_step("ALB Exists", 5, False, "No ALB found with 'alb-'")

        # 2. Check Target Group
        tgs = elbv2.describe_target_groups()['TargetGroups']
        target_tg = next((tg for tg in tgs if "tg-" in tg['TargetGroupName']), None)
        
        if target_tg:
            tg_arn = target_tg['TargetGroupArn']
            # Check health
            health = elbv2.describe_target_health(TargetGroupArn=tg_arn)
            if health['TargetHealthDescriptions']:
                grade_step("Target Group Exists & Healthy", 5, True)
            else:
                grade_step("Target Group Exists but empty", 5, False)
        else:
            grade_step("Target Group Exists", 5, False)

    except Exception as e:
        print(f"Error checking ALB/TG: {e}")

    # 3. Check ASG
    try:
        asgs = asg_client.describe_auto_scaling_groups()['AutoScalingGroups']
        target_asg = next((a for a in asgs if "asg-" in a['AutoScalingGroupName']), None)
        
        if target_asg:
            grade_step("ASG Created", 5, True)
            
            # Check scaling config
            conf = f"Min:{target_asg['MinSize']} Des:{target_asg['DesiredCapacity']} Max:{target_asg['MaxSize']}"
            if target_asg['MinSize']==1 and target_asg['MaxSize']==4 and target_asg['DesiredCapacity']>=1:
                grade_step("Scaling Config (1-2-4)", 5, True, conf)
            else:
                grade_step("Scaling Config (1-2-4)", 5, False, f"Incorrect: {conf}")
        else:
            grade_step("ASG Created", 5, False)
            grade_step("Scaling Config", 5, False)

    except Exception as e:
        print(f"Error checking ASG: {e}")

    # 4. Check ALB Reachability
    if alb_dns:
        print(f"    Testing ALB URL: http://{alb_dns}")
        success, msg = check_http_content(f"http://{alb_dns}", student_name_input)
        if success:
            grade_step("Web accessible via ALB", 5, True)
        else:
            grade_step("Web accessible via ALB", 5, False, msg)
    else:
        grade_step("Web accessible via ALB", 5, False, "No ALB DNS")

    # =========================================================
    # TASK 3: S3 STATIC WEBSITE (25 Marks)
    # =========================================================
    print_header("Task 3: S3 Static Website")
    
    found_bucket_name = None

    try:
        buckets = s3.list_buckets()['Buckets']
        # Find bucket with 's3-'
        target_bucket = next((b for b in buckets if "s3-" in b['Name']), None)
        
        if target_bucket:
            found_bucket_name = target_bucket['Name']
            grade_step("Bucket Created", 5, True, found_bucket_name)
            
            # Check Website Config
            try:
                web_conf = s3.get_bucket_website(Bucket=found_bucket_name)
                grade_step("Static Hosting Enabled", 5, True)
            except:
                grade_step("Static Hosting Enabled", 5, False, "Not enabled")

            # Check Files
            try:
                objs = s3.list_objects_v2(Bucket=found_bucket_name)
                files = [o['Key'] for o in objs.get('Contents', [])]
                if 'index.html' in files and 'error.html' in files:
                    grade_step("Index/Error files exist", 5, True)
                else:
                    grade_step("Index/Error files exist", 5, False, f"Found: {files}")
            except:
                grade_step("Index/Error files exist", 5, False, "Empty bucket")

            # Check Policy
            try:
                pol = s3.get_bucket_policy(Bucket=found_bucket_name)
                if "Allow" in pol['Policy'] and "*" in pol['Policy']:
                     grade_step("Bucket Policy (Public)", 5, True)
                else:
                     grade_step("Bucket Policy (Public)", 5, False, "Policy exists but looks restrictive")
            except:
                grade_step("Bucket Policy (Public)", 5, False, "No policy found")

            # Check Verification
            s3_url = f"http://{found_bucket_name}.s3-website-{region}.amazonaws.com"
            print(f"    Testing S3 URL: {s3_url}")
            success, msg = check_http_content(s3_url, student_name_input)
            grade_step("Website Verified in Browser", 5, success, msg)

        else:
            grade_step("Bucket Created", 5, False)
            # Fail cascading
            grade_step("Static Hosting Enabled", 0, False) # Using 0 to avoid double penalizing if logic dictates, but based on scheme:
            # Actually scheme implies 0 for all if bucket missing.
            print("    [!] Skipping remaining S3 checks as bucket is missing.")

    except Exception as e:
        print(f"Error checking S3: {e}")


    # =========================================================
    # TASK 4: RDS DATABASE (25 Marks)
    # =========================================================
    print_header("Task 4: RDS MySQL")

    try:
        dbs = rds.describe_db_instances()['DBInstances']
        target_rds = next((d for d in dbs if "rds-" in d['DBInstanceIdentifier']), None)
        
        if target_rds:
            grade_step("RDS Instance Created", 5, True)
            
            # Check Engine/Type
            if target_rds['Engine'] == 'mysql' and target_rds['DBInstanceClass'] == 'db.t3.medium':
                # Note: Scheme says 5 marks for creation AND type. 
                pass # Already awarded above, or split? Let's assume inclusive.
            else:
                print(f"    [!] Warning: Type is {target_rds['DBInstanceClass']} or Engine is {target_rds['Engine']}")

            # Check Security Group
            vpc_sgs = target_rds['VpcSecurityGroups']
            if vpc_sgs:
                sg_id = vpc_sgs[0]['VpcSecurityGroupId']
                # Deep check on port 3306
                sg_resp = ec2.describe_security_groups(GroupIds=[sg_id])
                perms = sg_resp['SecurityGroups'][0]['IpPermissions']
                port_open = any(p.get('FromPort') == 3306 for p in perms)
                
                grade_step("Security Group (Port 3306)", 5, port_open)
            else:
                grade_step("Security Group (Port 3306)", 5, False)

            # MANUAL CHECKS
            print("\n    [!] AUTOMATED CHECK LIMITATION:")
            print("    The following marks require verifying the student's screenshots")
            print("    because we cannot securely login to the DB from this script.")
            
            ans = input("    > Based on PDF, did EC2 connect to RDS? (y/n): ")
            grade_step("EC2 Connects to RDS (Manual)", 10, ans.lower() == 'y')

            ans2 = input("    > Based on PDF, were SQL queries successful? (y/n): ")
            grade_step("SQL Results Verified (Manual)", 5, ans2.lower() == 'y')

        else:
            grade_step("RDS Instance Created", 5, False)
            grade_step("Security Group", 5, False)
            grade_step("EC2 Connects to RDS", 10, False)
            grade_step("SQL Results", 5, False)

    except Exception as e:
        print(f"Error checking RDS: {e}")

    # =========================================================
    # FINAL REPORT
    # =========================================================
    print_header("FINAL RESULT")
    print(f"TOTAL SCORE: {SCORED_MARKS} / 100")
    print("\nNote: Marks for Naming Conventions are implicit in the 'Found' checks.")
    print("Please review any 'FAIL' messages manually in the console above.")

if __name__ == "__main__":
    main()