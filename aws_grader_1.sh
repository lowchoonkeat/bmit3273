import boto3
import urllib.request
import ssl
import time

# --- CONFIGURATION ---
ssl_context = ssl._create_unverified_context()
SCORED_MARKS = 0

def print_header(title):
    print(f"\n{'-'*60}\n {title}\n{'-'*60}")

def grade_step(desc, points, condition, issue=""):
    global SCORED_MARKS
    if condition:
        SCORED_MARKS += points
        print(f"[\u2713] PASS (+{points}): {desc}")
    else:
        print(f"[X] FAIL (0/{points}): {desc}")
        if issue: print(f"    -> Issue: {issue}")

def check_http_content(url, name, student_id):
    try:
        with urllib.request.urlopen(url, timeout=5, context=ssl_context) as r:
            content = r.read().decode('utf-8').lower()
            
            # We check if BOTH the name and the ID (from S3) are visible
            has_name = name in content
            has_id = student_id in content
            
            if has_name and has_id:
                return True, "Name AND Student ID found (S3 Read Success)"
            elif has_name:
                return False, "Name found, but Student ID missing (S3 Download Failed?)"
            elif "nginx" in content:
                return False, "Default Nginx page (User Data failed)"
            else:
                return False, "Page loads, content incorrect"
    except Exception as e: return False, str(e)

def main():
    print_header("BMIT3273 JAN 2026 - FINAL ASSESSMENT GRADER")
    
    session = boto3.session.Session()
    region = session.region_name
    print(f"Region: {region}")
    
    # INPUTS
    student_name = input("Enter Student Name (as used in resource names): ").strip().lower().replace(" ", "")
    student_id = input("Enter Student ID (to verify S3 retrieval): ").strip().lower()
    
    ec2 = boto3.client('ec2')
    s3 = boto3.client('s3')
    ddb = boto3.client('dynamodb')
    asg = boto3.client('autoscaling')
    elbv2 = boto3.client('elbv2')

    # ---------------------------------------------------------
    # TASK 1: DYNAMODB (25 Marks)
    # ---------------------------------------------------------
    print_header("Task 1: DynamoDB (Database)")
    try:
        tbls = ddb.list_tables()['TableNames']
        target_t = next((t for t in tbls if f"ddb-{student_name}" in t), None)
        
        if target_t:
            grade_step(f"Table Found ({target_t})", 10, True)
            
            desc = ddb.describe_table(TableName=target_t)['Table']
            pk = next((k['AttributeName'] for k in desc['KeySchema'] if k['KeyType'] == 'HASH'), None)
            grade_step("Partition Key is 'student_id'", 5, pk == 'student_id', f"Found: {pk}")
            
            scan = ddb.scan(TableName=target_t)
            has_item = False
            if scan['Count'] > 0:
                for item in scan['Items']:
                    if item.get('status', {}).get('S') == 'active': has_item = True
            grade_step("Item Added (status: active)", 10, has_item)
        else:
            grade_step("Table Created", 10, False)
            grade_step("Partition Key Correct", 5, False)
            grade_step("Item Added", 10, False)

    except Exception as e: print(f"Error Task 1: {e}")

    # ---------------------------------------------------------
    # TASK 2: S3 SECURITY (25 Marks)
    # ---------------------------------------------------------
    print_header("Task 2: S3 Security")
    try:
        buckets = s3.list_buckets()['Buckets']
        target_b = next((b['Name'] for b in buckets if f"s3-{student_name}" in b['Name']), None)
        
        if target_b:
            grade_step(f"Bucket Found ({target_b})", 5, True)
            
            try:
                pab = s3.get_public_access_block(Bucket=target_b)
                conf = pab['PublicAccessBlockConfiguration']
                is_blocked = conf['BlockPublicAcls'] and conf['IgnorePublicAcls'] and conf['BlockPublicPolicy'] and conf['RestrictPublicBuckets']
                grade_step("Block All Public Access Enabled", 5, is_blocked)
            except:
                grade_step("Block All Public Access Enabled", 5, False, "Not configured")

            ver = s3.get_bucket_versioning(Bucket=target_b)
            grade_step("Versioning Enabled", 5, ver.get('Status') == 'Enabled')
            
            try:
                lc = s3.get_bucket_lifecycle_configuration(Bucket=target_b)
                rules = lc.get('Rules', [])
                has_ia = any(t.get('StorageClass') == 'STANDARD_IA' for r in rules for t in r.get('Transitions', []))
                grade_step("Lifecycle Rule (Standard-IA)", 5, has_ia)
            except:
                grade_step("Lifecycle Rule (Standard-IA)", 5, False)

            try:
                s3.head_object(Bucket=target_b, Key='config.txt')
                grade_step("File 'config.txt' Uploaded", 5, True)
            except:
                grade_step("File 'config.txt' Uploaded", 5, False)
        else:
            grade_step("Bucket Created", 5, False)
            grade_step("Block Public Access", 5, False)
            grade_step("Versioning Enabled", 5, False)
            grade_step("Lifecycle Rule", 5, False)
            grade_step("File Uploaded", 5, False)

    except Exception as e: print(f"Error Task 2: {e}")

    # ---------------------------------------------------------
    # TASK 3: EC2 & USER DATA (25 Marks)
    # ---------------------------------------------------------
    print_header("Task 3: Web Tier Config")
    try:
        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if f"lt-{student_name}" in lt['LaunchTemplateName']), None)
        
        if target_lt:
            lt_id = target_lt['LaunchTemplateId']
            ver = ec2.describe_launch_template_versions(LaunchTemplateId=lt_id)['LaunchTemplateVersions'][0]
            data = ver['LaunchTemplateData']
            
            # Instance Type Check (t3.small)
            itype = data.get('InstanceType', 'Unknown')
            grade_step("Instance Type is t3.small", 5, itype == 't3.small', f"Found: {itype}")
            
            # LabInstanceProfile Check
            iam_prof = data.get('IamInstanceProfile', {}).get('Name', '') or data.get('IamInstanceProfile', {}).get('Arn', '')
            grade_step("LabInstanceProfile Attached", 10, "LabInstanceProfile" in iam_prof)
            
            ud = data.get('UserData', '')
            grade_step("User Data Script Present", 10, bool(ud))
        else:
            grade_step("Launch Template Found", 0, False)
            grade_step("Instance Type is t3.small", 5, False)
            grade_step("LabInstanceProfile Attached", 10, False)
            grade_step("User Data Present", 10, False)

    except Exception as e: print(f"Error Task 3: {e}")

    # ---------------------------------------------------------
    # TASK 4: ASG & WEB VERIFICATION (25 Marks)
    # ---------------------------------------------------------
    print_header("Task 4: High Availability & Integration")
    alb_dns = None
    try:
        albs = elbv2.describe_load_balancers()['LoadBalancers']
        target_alb = next((a for a in albs if f"alb-{student_name}" in a['LoadBalancerName']), None)
        if target_alb:
            alb_dns = target_alb['DNSName']
            grade_step("ALB Created", 5, True)
        else:
            grade_step("ALB Created", 5, False)

        asgs = asg.describe_auto_scaling_groups()['AutoScalingGroups']
        target_asg = next((a for a in asgs if f"asg-{student_name}" in a['AutoScalingGroupName']), None)
        
        if target_asg:
            grade_step("ASG Created", 5, True)
            
            pols = asg.describe_policies(AutoScalingGroupName=target_asg['AutoScalingGroupName'])['ScalingPolicies']
            has_tt = any(p['PolicyType'] == 'TargetTrackingScaling' for p in pols)
            grade_step("Target Tracking Policy Configured", 5, has_tt)
            
            # FUNCTIONAL TEST (Passes both Name and ID to check function)
            if alb_dns:
                print(f"    Testing URL: http://{alb_dns}")
                ok, msg = check_http_content(f"http://{alb_dns}", student_name, student_id)
                grade_step("Web Page: Name & ID Found", 10, ok, msg)
            else:
                grade_step("Web Page: Name & ID Found", 10, False)
        else:
            grade_step("ASG Created", 5, False)
            grade_step("Scaling Policy", 5, False)
            grade_step("Web Page: Name & ID Found", 10, False)

    except Exception as e: print(f"Error Task 4: {e}")

    print_header("FINAL RESULT")
    print(f"TOTAL: {SCORED_MARKS} / 100")

if __name__ == "__main__":
    main()