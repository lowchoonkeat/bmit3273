import boto3
import urllib.request
import ssl
import base64

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

def check_http_partial(url, name, student_id):
    try:
        with urllib.request.urlopen(url, timeout=5, context=ssl_context) as r:
            content = r.read().decode('utf-8').lower()
            
            found_name = name in content
            found_id = student_id in content
            
            if found_name and found_id:
                return True, True, "Success: Name AND ID found"
            elif found_name:
                return True, False, "Partial: Name found, but ID missing"
            else:
                return False, False, "Fail: Name not found (Nginx Default or Error)"
                
    except Exception as e: return False, False, str(e)

def main():
    print_header("BMIT3273 JAN 2026 - FINAL GRADER (VERSION 10.0)")
    
    session = boto3.session.Session()
    region = session.region_name
    print(f"Region: {region}")
    
    student_name = input("Enter Student Name: ").strip().lower().replace(" ", "")
    student_id = input("Enter Student ID: ").strip().lower()
    
    ec2 = boto3.client('ec2')
    s3 = boto3.client('s3')
    ddb = boto3.client('dynamodb')
    asg = boto3.client('autoscaling')
    elbv2 = boto3.client('elbv2')

    # ---------------------------------------------------------
    # TASK 1: DYNAMODB (25 Marks)
    # ---------------------------------------------------------
    print_header("Task 1: DynamoDB (25 Marks)")
    try:
        tbls = ddb.list_tables()['TableNames']
        target_t = next((t for t in tbls if f"ddb-{student_name}" in t), None)
        if target_t:
            grade_step(f"Table Found ({target_t})", 10, True)
            desc = ddb.describe_table(TableName=target_t)['Table']
            pk = next((k['AttributeName'] for k in desc['KeySchema'] if k['KeyType'] == 'HASH'), None)
            grade_step("Partition Key 'student_id'", 5, pk == 'student_id')
            
            # Case Insensitive Check
            scan = ddb.scan(TableName=target_t)
            has_item = False
            for i in scan.get('Items', []):
                status_val = i.get('status', {}).get('S', '').lower()
                if status_val == 'active':
                    has_item = True
            grade_step("Item Added (active/Active)", 10, has_item)
        else:
            grade_step("Table Found", 10, False)
            grade_step("Partition Key", 5, False)
            grade_step("Item Added", 10, False)
    except Exception as e: print(f"Error Task 1: {e}")

    # ---------------------------------------------------------
    # TASK 2: S3 SECURITY (25 Marks)
    # ---------------------------------------------------------
    print_header("Task 2: S3 Security (25 Marks)")
    try:
        buckets = s3.list_buckets()['Buckets']
        target_b = next((b['Name'] for b in buckets if f"s3-{student_name}" in b['Name']), None)
        if target_b:
            grade_step(f"Bucket Found", 2, True)
            
            # Tagging Check (Replaces Block Public Access)
            try:
                tags = s3.get_bucket_tagging(Bucket=target_b)['TagSet']
                has_tag = False
                for t in tags:
                    if t['Key'].lower() == 'project' and t['Value'].lower() == 'finalassessment':
                        has_tag = True
                grade_step("Tag Added (Project: FinalAssessment)", 4, has_tag)
            except: grade_step("Tag Added (Project: FinalAssessment)", 4, False, "No Tags")

            ver = s3.get_bucket_versioning(Bucket=target_b)
            grade_step("Versioning Enabled", 4, ver.get('Status') == 'Enabled')
            
            try:
                lc = s3.get_bucket_lifecycle_configuration(Bucket=target_b)
                has_ia = any(t.get('StorageClass') == 'STANDARD_IA' for r in lc.get('Rules', []) for t in r.get('Transitions', []))
                grade_step("Lifecycle Rule (Standard-IA)", 10, has_ia)
            except: grade_step("Lifecycle Rule (Standard-IA)", 10, False)

            try:
                s3.head_object(Bucket=target_b, Key='config.txt')
                grade_step("File 'config.txt' Uploaded", 5, True)
            except: grade_step("File 'config.txt' Uploaded", 5, False)
        else:
            grade_step("Bucket Found", 2, False)
            grade_step("Tag Added", 4, False)
            grade_step("Versioning", 4, False)
            grade_step("Lifecycle", 10, False)
            grade_step("File Uploaded", 5, False)
    except Exception as e: print(f"Error Task 2: {e}")

    # ---------------------------------------------------------
    # TASK 3: EC2 WEB TIER (25 Marks)
    # ---------------------------------------------------------
    print_header("Task 3: Web Tier Config (25 Marks)")
    try:
        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if f"lt-{student_name}" in lt['LaunchTemplateName']), None)
        
        if target_lt:
            ver = ec2.describe_launch_template_versions(LaunchTemplateId=target_lt['LaunchTemplateId'])['LaunchTemplateVersions'][0]
            data = ver['LaunchTemplateData']
            
            # Config Checks
            itype = data.get('InstanceType', 'Unknown')
            grade_step("Instance Type t3.small", 2, itype == 't3.small', f"Found: {itype}")
            
            iam_prof = data.get('IamInstanceProfile', {}).get('Name', '') or data.get('IamInstanceProfile', {}).get('Arn', '')
            grade_step("LabInstanceProfile Attached", 3, "LabInstanceProfile" in iam_prof)
            
            # Security Group Check (Partial Scoring)
            sg_ids = data.get('SecurityGroupIds', [])
            sg_points = 0
            sg_msg = "SG Not Found/Closed"
            
            if sg_ids:
                sg_resp = ec2.describe_security_groups(GroupIds=sg_ids)['SecurityGroups'][0]
                has_all = False
                has_http = False
                for p in sg_resp['IpPermissions']:
                    is_open = any(r.get('CidrIp') == '0.0.0.0/0' for r in p.get('IpRanges', []))
                    if is_open:
                        if p.get('IpProtocol') == '-1': has_all = True
                        if p.get('FromPort') == 80: has_http = True
                
                if has_all:
                    sg_points = 2
                    sg_msg = "Partial: 'All Traffic' (-3 Marks)"
                elif has_http:
                    sg_points = 5
                    sg_msg = "Perfect: Port 80 Open"
            
            global SCORED_MARKS
            SCORED_MARKS += sg_points
            print(f"[{'✓' if sg_points>0 else 'X'}] PASS/PARTIAL (+{sg_points}/5): Security Group - {sg_msg}")

            # Script Logic Checks (3 x 5 Marks)
            ud_encoded = data.get('UserData', '')
            if ud_encoded:
                try:
                    ud_script = base64.b64decode(ud_encoded).decode('utf-8').lower()
                    grade_step("Script: Nginx Logic", 5, "nginx" in ud_script)
                    grade_step("Script: S3 Logic", 5, ("aws" in ud_script or "s3" in ud_script))
                    has_append = (">>" in ud_script) or ("cat" in ud_script) or ("index.html" in ud_script)
                    grade_step("Script: Append/Write Logic", 5, has_append)
                except:
                    grade_step("Script: Nginx Logic", 5, False, "Encoding Error")
                    grade_step("Script: S3 Logic", 5, False)
                    grade_step("Script: Append Logic", 5, False)
            else:
                grade_step("Script: Nginx Logic", 5, False, "Empty")
                grade_step("Script: S3 Logic", 5, False)
                grade_step("Script: Append Logic", 5, False)

        else:
            grade_step("Launch Template Found", 0, False)
            grade_step("Instance Type t3.small", 2, False)
            grade_step("LabInstanceProfile Attached", 3, False)
            print("[X] FAIL (0/5): Security Group Not Found")
            grade_step("Script: Logic Checks", 15, False)
            
    except Exception as e: print(f"Error Task 3: {e}")

    # ---------------------------------------------------------
    # TASK 4: HA & FUNCTIONALITY (25 Marks)
    # ---------------------------------------------------------
    print_header("Task 4: High Availability (25 Marks)")
    alb_dns = None
    try:
        albs = elbv2.describe_load_balancers()['LoadBalancers']
        target_alb = next((a for a in albs if f"alb-{student_name}" in a['LoadBalancerName']), None)
        if target_alb:
            alb_dns = target_alb['DNSName']
            grade_step("ALB Created", 2, True)
        else:
            grade_step("ALB Created", 2, False)

        asgs = asg.describe_auto_scaling_groups()['AutoScalingGroups']
        target_asg = next((a for a in asgs if f"asg-{student_name}" in a['AutoScalingGroupName']), None)
        
        if target_asg:
            grade_step("ASG Created", 3, True)
            
            pols = asg.describe_policies(AutoScalingGroupName=target_asg['AutoScalingGroupName'])['ScalingPolicies']
            has_tt = any(p['PolicyType'] == 'TargetTrackingScaling' for p in pols)
            grade_step("Scaling Policy Configured", 5, has_tt)
            
            # Split Functional Check
            if alb_dns:
                print(f"    Testing URL: http://{alb_dns}")
                has_name, has_id, msg = check_http_partial(f"http://{alb_dns}", student_name, student_id)
                grade_step("Functional: Web Page Loads (Name)", 5, has_name, msg)
                grade_step("Functional: S3 Data Visible (ID)", 10, has_id, msg)
            else:
                grade_step("Functional: Web Page Loads (Name)", 5, False)
                grade_step("Functional: S3 Data Visible (ID)", 10, False)
        else:
            grade_step("ASG Created", 3, False)
            grade_step("Scaling Policy", 5, False)
            grade_step("Functional: Web Page Loads (Name)", 5, False)
            grade_step("Functional: S3 Data Visible (ID)", 10, False)

    except Exception as e: print(f"Error Task 4: {e}")

    print_header("FINAL RESULT")
    print(f"TOTAL: {SCORED_MARKS} / 100")

if __name__ == "__main__":
    main()
