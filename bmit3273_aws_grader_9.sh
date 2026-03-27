import boto3
import json
import base64
import urllib.request
import ssl
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# ===============================================================
#  BMIT3273 CLOUD COMPUTING - PRACTICAL TEST SET 9 AUTO GRADER
#  Topics: Launch Template + ASG | S3 Versioning | Lambda | EFS
# ===============================================================

ssl_ctx = ssl._create_unverified_context()
SCORE = 0

G  = '\033[92m';  R  = '\033[91m';  Y  = '\033[93m'
C  = '\033[96m';  B  = '\033[1m';   W  = '\033[97m';  X  = '\033[0m'

def banner(t): print(f"\n{C}{B}{'='*60}\n  {t}\n{'='*60}{X}")
def section(t): print(f"\n{C}{'-'*60}\n  {t}\n{'-'*60}{X}")

def ok(d, p):
    global SCORE; SCORE += p
    print(f"  {G}[OK] +{p:2d}  {d}{X}"); return p

def fail(d, p, r=""):
    print(f"  {R}[X]  0/{p:<2d} {d}{X}")
    if r: print(f"       {Y}-> {r}{X}")
    return 0

def partial(d, earned, total, r=""):
    global SCORE; SCORE += earned
    sym = Y if earned > 0 else R
    print(f"  {sym}[~] +{earned}/{total}  {d}{X}")
    if r: print(f"       {Y}-> {r}{X}")
    return earned


def main():
    banner("BMIT3273 CLOUD COMPUTING - SET 9")
    print(f"  {W}Topics: LT + ASG | S3 Versioning | Lambda | EFS{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()
    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2 = boto3.client('ec2')
    asg_client = boto3.client('autoscaling')
    s3  = boto3.client('s3')
    lam = boto3.client('lambda')
    efs = boto3.client('efs')
    task_scores = {}

    # ==========================================================
    # QUESTION 1 - LAUNCH TEMPLATE + ASG (25 MARKS)
    # ==========================================================
    section("Question 1: Launch Template + Auto Scaling")
    t1 = 0
    try:
        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if f"lt-{name}" in lt['LaunchTemplateName'].lower().replace(' ', '')), None)

        if target_lt:
            t1 += ok(f"Launch Template: {target_lt['LaunchTemplateName']}", 4)
            ver = ec2.describe_launch_template_versions(
                LaunchTemplateId=target_lt['LaunchTemplateId']
            )['LaunchTemplateVersions'][0]
            data = ver['LaunchTemplateData']

            itype = data.get('InstanceType', '')
            if itype == 't3.micro':
                t1 += ok("Instance type: t3.micro", 3)
            elif itype in ('t2.micro', 't3.small', 't3.nano'):
                t1 += partial("Instance type close", 2, 3, f"Found: {itype}")
            else:
                t1 += fail("Instance type: t3.micro", 3, f"Found: {itype}")

            ud = data.get('UserData', '')
            if ud:
                try:
                    script = base64.b64decode(ud).decode('utf-8', errors='ignore').lower()
                    has_web = 'httpd' in script or 'nginx' in script
                    t1 += ok("User Data: web server", 3) if has_web \
                        else partial("User Data exists, no web server", 1, 3)
                except:
                    t1 += partial("User Data (decode err)", 1, 3)
            else:
                t1 += fail("User Data", 3)
        else:
            t1 += fail("Launch Template", 4, f"No LT 'lt-{name}'")
            t1 += fail("Instance type", 3); t1 += fail("User Data", 3)

        # ASG
        asgs = asg_client.describe_auto_scaling_groups()['AutoScalingGroups']
        target_asg = next((a for a in asgs if f"asg-{name}" in a['AutoScalingGroupName'].lower().replace(' ', '')), None)

        if target_asg:
            t1 += ok(f"ASG: {target_asg['AutoScalingGroupName']}", 5)

            mn, mx, des = target_asg['MinSize'], target_asg['MaxSize'], target_asg['DesiredCapacity']
            if mn == 1 and mx == 3 and des == 1:
                t1 += ok("Capacity: Min=1, Max=3, Desired=1", 5)
            elif mn == 1 and mx == 3:
                t1 += partial("Min/Max correct, Desired wrong", 3, 5, f"Des={des}")
            elif mn == 1:
                t1 += partial("Min correct only", 2, 5, f"Min={mn}, Max={mx}, Des={des}")
            else:
                t1 += fail("Capacity 1/3/1", 5, f"Found Min={mn}, Max={mx}, Des={des}")

            pols = asg_client.describe_policies(AutoScalingGroupName=target_asg['AutoScalingGroupName'])['ScalingPolicies']
            policy_ok = False
            found_val = "None"
            for p in pols:
                if p['PolicyType'] == 'TargetTrackingScaling':
                    tv = p.get('TargetTrackingConfiguration', {}).get('TargetValue', 0.0)
                    found_val = tv
                    if tv == 50.0:
                        policy_ok = True; break
            t1 += ok("Scaling policy: CPU 50%", 5) if policy_ok \
                else fail("Scaling policy CPU 50%", 5, f"Found target: {found_val}%")
        else:
            t1 += fail("ASG", 5, f"No ASG 'asg-{name}'")
            t1 += fail("Capacity", 5); t1 += fail("Scaling policy", 5)
    except Exception as e:
        print(f"  {R}Error Question 1: {e}{X}")

    task_scores['Question 1: LT + ASG     '] = t1
    print(f"\n  {B}Question 1 Subtotal: {t1} / 25{X}")

    # ==========================================================
    # QUESTION 2 - S3 VERSIONING & LIFECYCLE (25 MARKS)
    # ==========================================================
    section("Question 2: S3 Versioning & Lifecycle")
    t2 = 0
    try:
        buckets = s3.list_buckets()['Buckets']
        target_b = next((b['Name'] for b in buckets if f"s3-{name}" in b['Name']), None)

        if target_b:
            t2 += ok(f"Bucket: {target_b}", 2)

            try:
                tags = s3.get_bucket_tagging(Bucket=target_b)['TagSet']
                proj_tag = next((t['Value'] for t in tags if t['Key'].lower() == 'project'), None)
                if proj_tag and proj_tag.lower() == 'finaltest':
                    t2 += ok("Tag Project = FinalTest", 4)
                elif proj_tag:
                    t2 += partial("Tag Project exists", 2, 4, f"Value: '{proj_tag}'")
                else:
                    t2 += fail("Tag Project=FinalTest", 4)
            except:
                t2 += fail("Tag", 4, "No tags")

            ver = s3.get_bucket_versioning(Bucket=target_b)
            t2 += ok("Versioning enabled", 5) if ver.get('Status') == 'Enabled' else fail("Versioning", 5)

            try:
                lc = s3.get_bucket_lifecycle_configuration(Bucket=target_b)
                has_ia = any(
                    t.get('StorageClass') == 'STANDARD_IA'
                    for r in lc.get('Rules', []) for t in r.get('Transitions', []))
                t2 += ok("Lifecycle: Standard-IA", 9) if has_ia else fail("Lifecycle Standard-IA", 9)
            except:
                t2 += fail("Lifecycle", 9, "No lifecycle config")

            try:
                s3.head_object(Bucket=target_b, Key='report.txt')
                t2 += ok("report.txt uploaded", 5)
            except:
                t2 += fail("report.txt", 5)
        else:
            t2 += fail("Bucket", 2, f"No 's3-{name}'")
            for d, p in [("Tag", 4), ("Versioning", 5), ("Lifecycle", 9), ("report.txt", 5)]: t2 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 2: {e}{X}")

    task_scores['Question 2: S3 Lifecycle '] = t2
    print(f"\n  {B}Question 2 Subtotal: {t2} / 25{X}")

    # ==========================================================
    # QUESTION 3 - LAMBDA FUNCTION (25 MARKS)
    # ==========================================================
    section("Question 3: Lambda Function")
    t3 = 0
    try:
        fname = f"lambda-{name}"
        try:
            func = lam.get_function(FunctionName=fname)
            cfg = func['Configuration']
            t3 += ok(f"Lambda: {fname}", 5)

            rt = cfg.get('Runtime', '')
            t3 += ok(f"Runtime: {rt}", 3) if rt.startswith('python3') else fail("Runtime Python3", 3, f"Found: {rt}")

            role = cfg.get('Role', '')
            t3 += ok("LabRole", 3) if 'LabRole' in role else fail("LabRole", 3)

            env = cfg.get('Environment', {}).get('Variables', {})
            t3 += ok("Env STUDENT_NAME", 3) if 'STUDENT_NAME' in env else fail("Env STUDENT_NAME", 3)
            t3 += ok("Env STUDENT_ID", 3) if 'STUDENT_ID' in env else fail("Env STUDENT_ID", 3)

            print(f"    {Y}Invoking {fname} ...{X}")
            try:
                inv = lam.invoke(FunctionName=fname, InvocationType='RequestResponse')
                if inv.get('StatusCode') == 200 and not inv.get('FunctionError'):
                    t3 += ok("Invocation success", 3)
                    payload = inv['Payload'].read().decode('utf-8')
                    pc = payload.lower().replace(' ', '')
                    has_name = name in pc
                    has_id = sid in payload.lower()
                    if has_name and has_id:
                        t3 += ok("Response: name AND ID", 5)
                    elif has_name:
                        t3 += partial("Response: name only", 3, 5)
                    elif has_id:
                        t3 += partial("Response: ID only", 2, 5)
                    else:
                        t3 += fail("Response content", 5)
                else:
                    t3 += fail("Invoke", 3, f"Error: {inv.get('FunctionError')}")
                    t3 += fail("Response", 5)
            except Exception as e:
                t3 += fail("Invoke", 3, str(e)[:80]); t3 += fail("Response", 5)

        except lam.exceptions.ResourceNotFoundException:
            t3 += fail("Lambda", 5, f"No '{fname}'")
            for d, p in [("Runtime", 3), ("LabRole", 3), ("Env NAME", 3), ("Env ID", 3),
                         ("Invoke", 3), ("Response", 5)]: t3 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 3: {e}{X}")

    task_scores['Question 3: Lambda       '] = t3
    print(f"\n  {B}Question 3 Subtotal: {t3} / 25{X}")

    # ==========================================================
    # QUESTION 4 - EFS FILE SYSTEM (25 MARKS)
    # ==========================================================
    section("Question 4: EFS File System")
    t4 = 0
    try:
        fss = efs.describe_file_systems()['FileSystems']
        target_fs = None
        for fs in fss:
            n = fs.get('Name', '').lower().replace(' ', '')
            if f"efs-{name}" in n:
                target_fs = fs; break

        if target_fs:
            fsid = target_fs['FileSystemId']
            t4 += ok(f"EFS: {target_fs.get('Name', fsid)}", 7)

            pm = target_fs.get('PerformanceMode', '')
            if pm == 'generalPurpose':
                t4 += ok("Performance: generalPurpose", 3)
            elif pm:
                t4 += partial("Performance mode set", 1, 3, f"Found: {pm}")
            else:
                t4 += fail("generalPurpose", 3)

            tags_resp = efs.describe_tags(FileSystemId=fsid)
            tags = tags_resp.get('Tags', [])
            proj = next((t['Value'] for t in tags if t['Key'] == 'Project'), '')
            if proj.upper() == 'BMIT3273':
                t4 += ok("Tag Project = BMIT3273", 5)
            elif proj:
                t4 += partial("Tag Project exists", 2, 5, f"Value: '{proj}'")
            else:
                t4 += fail("Tag BMIT3273", 5, "Missing")

            mts = efs.describe_mount_targets(FileSystemId=fsid)['MountTargets']
            t4 += ok(f"Mount targets: {len(mts)} AZ(s)", 10) if len(mts) > 0 \
                else fail("Mount target", 10)
        else:
            t4 += fail("EFS", 7, f"No 'efs-{name}'")
            for d, p in [("Performance", 3), ("Tag", 5), ("Mount target", 10)]: t4 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 4: {e}{X}")

    task_scores['Question 4: EFS          '] = t4
    print(f"\n  {B}Question 4 Subtotal: {t4} / 25{X}")

    # ==========================================================
    banner("FINAL RESULT")
    for task, score in task_scores.items():
        filled = int(score * 10 / 25); bar = '#' * filled + '-' * (10 - filled)
        print(f"  {task} {bar} {score:2d}/25")
    print(f"\n  {'-'*44}")
    color = G if SCORE >= 80 else (Y if SCORE >= 50 else R)
    print(f"  {color}{B}  TOTAL SCORE :  {SCORE} / 100{X}")
    print(f"  {'-'*44}")
    if SCORE == 100: print(f"\n  {G}{B}  *  PERFECT SCORE - Excellent work!  *{X}")
    elif SCORE >= 80: print(f"\n  {G}  Great job!{X}")
    elif SCORE >= 50: print(f"\n  {Y}  Decent progress.{X}")
    else: print(f"\n  {R}  Needs improvement.{X}")
    print()
    print("  Mr Low blessing you!")

if __name__ == "__main__":
    main()

