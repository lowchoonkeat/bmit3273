import boto3
import sys
import urllib.request
import ssl

# --- CONFIGURATION ---
ssl_context = ssl._create_unverified_context()

# Global Score Keepers
TOTAL_MARKS = 0
SCORED_MARKS = 0

def print_header(title):
    print(f"\n{'='*60}")
    print(f" {title}")
    print(f"{'='*60}")

def grade_step(description, max_points, condition, details=""):
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
    try:
        with urllib.request.urlopen(url, timeout=5, context=ssl_context) as response:
            if response.status == 200:
                content = response.read().decode('utf-8')
                if keyword.lower() in content.lower():
                    return True, "Content matched"
                else:
                    return True, "Page loads, but student name not found"
    except Exception as e:
        return False, str(e)
    return False, "Unknown error"

def main():
    print_header("BMIT3273 CLOUD COMPUTING - AUTO GRADER")
    
    session = boto3.session.Session()
    region = session.region_name
    print(f"Scanning Region: {region}")
    
    student_name_input = input("Enter Student Full Name (as used in resource naming): ").strip().lower()
    student_name_nospace = student_name_input.replace(" ", "")
    print(f"Looking for resources containing: '{student_name_nospace}' or parts of it...")

    ec2 = boto3.client('ec2')
    asg_client = boto3.client('autoscaling')
    elbv2 = boto3.client('elbv2')
    s3 = boto3.client('s3')
    rds = boto3.client('rds')

    # --- TASK 1: EC2 & SECURITY (25 MARKS) ---
    print_header("Task 1: EC2, Launch Template & Security")
    try:
        # 1. Check Launch Template (5 Marks)
        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if "lt-" in lt['LaunchTemplateName']), None)
        lt_found = False
        if target_lt:
            lt_found = True
            lt_id = target_lt['LaunchTemplateId']
            grade_step("Launch Template created", 5, True)
            
            # 2. Check Instance Type (5 Marks)
            lt_ver = ec2.describe_launch_template_versions(LaunchTemplateId=lt_id)['LaunchTemplateVersions'][0]
            instance_type = lt_ver['LaunchTemplateData'].get('InstanceType', 'Unknown')
            grade_step("Instance Type is t3.medium", 5, instance_type == 't3.medium')
            
            # 3. Check User Data (10 Marks)
            grade_step("User Data Script configured", 10, 'UserData' in lt_ver['LaunchTemplateData'])
        else:
            grade_step("Launch Template created", 5, False)
            grade_step("Instance Type is t3.medium", 5, False)
            grade_step("User Data Script configured", 10, False)

        # 4. Check Security Group 'web-access' (5 Marks)
        sgs = ec2.describe_security_groups()['SecurityGroups']
        web_sg = next((sg for sg in sgs if sg['GroupName'] == 'web-access'), None)
        
        if web_sg:
            perms = web_sg['IpPermissions']
            has_ssh = False
            has_http = False
            
            for p in perms:
                if p.get('FromPort') == 22 or p.get('IpProtocol') == '-1': has_ssh = True
                if p.get('FromPort') == 80 or p.get('IpProtocol') == '-1': has_http = True
            
            if has_ssh and has_http:
                grade_step("SG 'web-access' allows SSH & HTTP", 5, True)
            else:
                grade_step("SG 'web-access' allows SSH & HTTP", 5, False, f"Missing ports (SSH:{has_ssh}, HTTP:{has_http})")
        else:
            grade_step("SG 'web-access' allows SSH & HTTP", 5, False, "Security Group 'web-access' not found")

    except Exception as e:
        print(f"Error Task 1: {e}")

    # --- TASK 2: ASG & ALB (25 MARKS) ---
    print_header("Task 2: ASG & ALB")
    alb_dns = None
    try:
        albs = elbv2.describe_load_balancers()['LoadBalancers']
        target_alb = next((alb for alb in albs if "alb-" in alb['LoadBalancerName']), None)
        if target_alb:
            alb_dns = target_alb['DNSName']
            grade_step("ALB Exists & Internet Facing", 5, target_alb['Scheme'] == 'internet-facing')
        else:
            grade_step("ALB Exists", 5, False)

        tgs = elbv2.describe_target_groups()['TargetGroups']
        target_tg = next((tg for tg in tgs if "tg-" in tg['TargetGroupName']), None)
        if target_tg:
            health = elbv2.describe_target_health(TargetGroupArn=target_tg['TargetGroupArn'])
            grade_step("Target Group Exists & Healthy", 5, bool(health['TargetHealthDescriptions']))
        else:
            grade_step("Target Group Exists", 5, False)

        asgs = asg_client.describe_auto_scaling_groups()['AutoScalingGroups']
        target_asg = next((a for a in asgs if "asg-" in a['AutoScalingGroupName']), None)
        if target_asg:
            grade_step("ASG Created", 5, True)
            grade_step("Scaling Config (1-2-4)", 5, target_asg['MinSize']==1 and target_asg['MaxSize']==4)
        else:
            grade_step("ASG Created", 5, False)
            grade_step("Scaling Config (1-2-4)", 5, False)

        if alb_dns:
            print(f"    Testing ALB URL: http://{alb_dns}")
            success, msg = check_http_content(f"http://{alb_dns}", student_name_input)
            grade_step("Web accessible via ALB", 5, success, msg)
        else:
            grade_step("Web accessible via ALB", 5, False)
    except Exception as e:
        print(f"Error Task 2: {e}")

    # --- TASK 3: S3 (25 MARKS) ---
    print_header("Task 3: S3 Static Website")
    target_bucket_name = None
    try:
        buckets = s3.list_buckets()['Buckets']
        target_bucket = next((b for b in buckets if "s3-" in b['Name']), None)
        if target_bucket:
            target_bucket_name = target_bucket['Name']
            grade_step("Bucket Created", 5, True)
            try:
                s3.get_bucket_website(Bucket=target_bucket_name)
                grade_step("Static Hosting Enabled", 5, True)
            except:
                grade_step("Static Hosting Enabled", 5, False)
            
            try:
                objs = s3.list_objects_v2(Bucket=target_bucket_name)
                files = [o['Key'] for o in objs.get('Contents', [])]
                grade_step("Index/Error files exist", 5, 'index.html' in files and 'error.html' in files)
            except:
                 grade_step("Index/Error files exist", 5, False)

            try:
                pol = s3.get_bucket_policy(Bucket=target_bucket_name)
                grade_step("Bucket Policy (Public)", 5, "Allow" in pol['Policy'])
            except:
                grade_step("Bucket Policy (Public)", 5, False)

            s3_url = f"http://{target_bucket_name}.s3-website-{region}.amazonaws.com"
            print(f"    Testing S3 URL: {s3_url}")
            success, msg = check_http_content(s3_url, student_name_input)
            grade_step("Website Verified in Browser", 5, success, msg)
        else:
            grade_step("Bucket Created", 5, False)
            grade_step("Static Hosting Enabled", 5, False)
            grade_step("Index/Error files exist", 5, False)
            grade_step("Bucket Policy (Public)", 5, False)
            grade_step("Website Verified in Browser", 5, False)
    except Exception as e:
        print(f"Error Task 3: {e}")

    # --- TASK 4: RDS (25 MARKS) ---
    print_header("Task 4: RDS MySQL & Connection Evidence")
    try:
        dbs = rds.describe_db_instances()['DBInstances']
        
        target_rds = next((d for d in dbs if "rds-" in d['DBInstanceIdentifier']), None)
        using_default_name = False
        if not target_rds:
            target_rds = next((d for d in dbs if d['DBInstanceIdentifier'] == "database-1"), None)
            if target_rds:
                using_default_name = True

        if target_rds:
            # CHECK 1: RDS CONFIGURATION (5 Marks)
            inst_type = target_rds['DBInstanceClass']
            storage = target_rds['AllocatedStorage']
            db_name = target_rds.get('DBName', '')
            
            config_errors = []
            if using_default_name: config_errors.append("Wrong Name")
            if inst_type != 'db.t4g.micro': config_errors.append(f"Wrong Type ({inst_type})")
            if storage != 30: config_errors.append(f"Wrong Storage ({storage}GB)")
            if db_name != 'firstdb': config_errors.append(f"Wrong Initial DB ({db_name})")
            
            if not config_errors:
                grade_step("RDS Config (Specs, Name, InitialDB)", 5, True)
            else:
                grade_step("RDS Config (Specs, Name, InitialDB)", 5, False, f"Issues: {', '.join(config_errors)}")

            # CHECK 2: Security Group (5 Marks)
            vpc_sgs = target_rds['VpcSecurityGroups']
            secure = False
            details = "No SG found"
            if vpc_sgs:
                sg_id = vpc_sgs[0]['VpcSecurityGroupId']
                sg_resp = ec2.describe_security_groups(GroupIds=[sg_id])
                perms = sg_resp['SecurityGroups'][0]['IpPermissions']
                
                has_3306 = False
                is_public = False
                uses_sg_ref = False
                
                for p in perms:
                    if p.get('FromPort') == 3306 or p.get('IpProtocol') == '-1':
                        has_3306 = True
                        for r in p.get('IpRanges', []):
                            if r.get('CidrIp') == '0.0.0.0/0': is_public = True
                        if p.get('UserIdGroupPairs'): uses_sg_ref = True
                
                if has_3306 and not is_public and uses_sg_ref:
                    secure = True
                else:
                    details = f"Open:{has_3306}, Public:{is_public}, SG-Ref:{uses_sg_ref}"

            grade_step("Security Group (Restricted to EC2)", 5, secure, details)

            # CHECK 3 & 4: SPLIT EVIDENCE CHECK (10 + 5 Marks)
            print("    Checking S3 for evidence file 'db_results.txt'...")
            
            file_found = False
            has_firstdb = False
            has_testdb = False
            
            if target_bucket_name:
                try:
                    file_obj = s3.get_object(Bucket=target_bucket_name, Key='db_results.txt')
                    file_content = file_obj['Body'].read().decode('utf-8')
                    file_found = True
                    if "firstdb" in file_content: has_firstdb = True
                    if "testdb" in file_content: has_testdb = True
                except:
                    pass
            
            # Sub-Check A: File Exists + Connected (10 Marks)
            if file_found and has_firstdb:
                grade_step("Evidence: Connection Successful (File found)", 10, True)
            else:
                grade_step("Evidence: Connection Successful (File found)", 10, False, "File missing or 'firstdb' not in list")

            # Sub-Check B: Manual Task (5 Marks)
            if file_found and has_testdb:
                grade_step("Evidence: Manual 'testdb' Created", 5, True)
            else:
                grade_step("Evidence: Manual 'testdb' Created", 5, False, "'testdb' missing from list")

        else:
            grade_step("RDS Config (Specs, Name, InitialDB)", 5, False, "No Database Found")
            grade_step("Security Group (Restricted to EC2)", 5, False)
            grade_step("Evidence: Connection Successful", 10, False)
            grade_step("Evidence: Manual 'testdb' Created", 5, False)

    except Exception as e:
        print(f"Error checking RDS: {e}")

    # --- FINAL REPORT ---
    print_header("FINAL RESULT")
    print(f"TOTAL SCORE: {SCORED_MARKS} / 100")

if __name__ == "__main__":
    main()
