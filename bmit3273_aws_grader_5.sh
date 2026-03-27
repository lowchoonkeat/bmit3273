import boto3
import json
import urllib.request
import ssl
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# ===============================================================
#  BMIT3273 CLOUD COMPUTING - PRACTICAL TEST SET 5 AUTO GRADER
#  Topics: S3 Static Website | EC2 + Launch Template | DynamoDB | EFS
# ===============================================================

ssl_ctx = ssl._create_unverified_context()
SCORE = 0

G  = '\033[92m';  R  = '\033[91m';  Y  = '\033[93m'
C  = '\033[96m';  B  = '\033[1m';   W  = '\033[97m';  X  = '\033[0m'

def banner(t):
    print(f"\n{C}{B}{'='*60}\n  {t}\n{'='*60}{X}")

def section(t):
    print(f"\n{C}{'-'*60}\n  {t}\n{'-'*60}{X}")

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

def tag_val(resource, key):
    for t in resource.get('Tags', resource.get('tags', [])):
        if t.get('Key', t.get('key')) == key:
            return t.get('Value', t.get('value', ''))
    return ''


def main():
    banner("BMIT3273 CLOUD COMPUTING - SET 5")
    print(f"  {W}Practical Test Auto Grader v1.0{X}")
    print(f"  {W}Topics: S3 | EC2 + LT | DynamoDB | EFS{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()

    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2 = boto3.client('ec2')
    s3  = boto3.client('s3')
    ddb = boto3.client('dynamodb')
    efs = boto3.client('efs')

    task_scores = {}

    # ==========================================================
    # QUESTION 1 - S3 STATIC WEBSITE HOSTING (25 MARKS)
    # ==========================================================
    section("Question 1: S3 Static Website Hosting")
    t1 = 0
    target_bucket = None
    try:
        buckets = s3.list_buckets()['Buckets']
        target_bucket = next((b['Name'] for b in buckets if f"s3-{name}" in b['Name']), None)

        if target_bucket:
            t1 += ok(f"Bucket found: {target_bucket}", 3)

            try:
                s3.get_bucket_website(Bucket=target_bucket)
                t1 += ok("Static website hosting enabled", 5)
            except:
                t1 += fail("Static website hosting enabled", 5)

            try:
                objs = s3.list_objects_v2(Bucket=target_bucket)
                files = [o['Key'] for o in objs.get('Contents', [])]
                t1 += ok("index.html uploaded", 3) if 'index.html' in files \
                    else fail("index.html uploaded", 3)
                t1 += ok("error.html uploaded", 2) if 'error.html' in files \
                    else fail("error.html uploaded", 2)
            except:
                t1 += fail("index.html uploaded", 3)
                t1 += fail("error.html uploaded", 2)

            try:
                pol = s3.get_bucket_policy(Bucket=target_bucket)
                t1 += ok("Bucket policy configured (public)", 5) if "Allow" in pol['Policy'] \
                    else fail("Bucket policy", 5, "Policy exists but no Allow")
            except:
                t1 += fail("Bucket policy (public read)", 5)

            s3_url = f"http://{target_bucket}.s3-website-{region}.amazonaws.com"
            print(f"    {Y}Testing: {s3_url}{X}")
            try:
                with urllib.request.urlopen(s3_url, timeout=10, context=ssl_ctx) as resp:
                    html = resp.read().decode('utf-8', errors='ignore')
                    cl = html.lower().replace(' ', '').replace('\n', '')
                    if name in cl:
                        t1 += ok("Website accessible & shows student name", 7)
                    else:
                        t1 += partial("Website accessible but name not found", 4, 7)
            except Exception as e:
                t1 += fail("Website accessible", 7, str(e)[:80])
        else:
            t1 += fail("S3 bucket found", 3, f"No bucket containing 's3-{name}'")
            for d, p in [("Static hosting", 5), ("index.html", 3), ("error.html", 2),
                         ("Bucket policy", 5), ("Website accessible", 7)]:
                t1 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 1: {e}{X}")

    task_scores['Question 1: S3 Website    '] = t1
    print(f"\n  {B}Question 1 Subtotal: {t1} / 25{X}")

    # ==========================================================
    # QUESTION 2 - EC2 WITH LAUNCH TEMPLATE (25 MARKS)
    # ==========================================================
    section("Question 2: EC2 with Launch Template")
    t2 = 0
    try:
        import base64

        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if f"lt-{name}" in lt['LaunchTemplateName'].lower().replace(' ', '')), None)

        if target_lt:
            t2 += ok(f"Launch Template: {target_lt['LaunchTemplateName']}", 5)

            ver = ec2.describe_launch_template_versions(
                LaunchTemplateId=target_lt['LaunchTemplateId']
            )['LaunchTemplateVersions'][0]
            data = ver['LaunchTemplateData']

            itype = data.get('InstanceType', 'Unknown')
            if itype == 't3.micro':
                t2 += ok("Instance type: t3.micro", 3)
            elif itype in ('t2.micro', 't3.small', 't3.nano'):
                t2 += partial("Instance type", 2, 3, f"Found: {itype} (close)")
            else:
                t2 += fail("Instance type: t3.micro", 3, f"Found: {itype}")

            iam_prof = data.get('IamInstanceProfile', {}).get('Name', '') or \
                       data.get('IamInstanceProfile', {}).get('Arn', '')
            t2 += ok("LabInstanceProfile attached", 2) if 'LabInstanceProfile' in iam_prof \
                else fail("LabInstanceProfile", 2)

            ud = data.get('UserData', '')
            if ud:
                try:
                    script = base64.b64decode(ud).decode('utf-8', errors='ignore').lower()
                    has_web = 'httpd' in script or 'nginx' in script or 'apache' in script
                    t2 += ok("User Data: web server install", 5) if has_web \
                        else partial("User Data exists but no web server", 2, 5)
                except:
                    t2 += partial("User Data exists (decode error)", 2, 5)
            else:
                t2 += fail("User Data configured", 5)
        else:
            t2 += fail("Launch Template found", 5, f"No LT named 'lt-{name}'")
            t2 += fail("Instance type", 3)
            t2 += fail("LabInstanceProfile", 2)
            t2 += fail("User Data", 5)

        # Check running EC2
        reservations = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running', 'stopped', 'pending']}]
        )['Reservations']
        all_inst = [i for r in reservations for i in r['Instances']]
        inst = None
        for i in all_inst:
            n = ''
            for t in i.get('Tags', []):
                if t['Key'] == 'Name': n = t['Value']
            if f"ec2-{name}" in n.lower().replace(' ', ''):
                inst = i; break

        if inst:
            t2 += ok(f"EC2 instance: {inst['InstanceId']}", 5)

            pub_ip = inst.get('PublicIpAddress', '')
            state = inst.get('State', {}).get('Name', '')
            if pub_ip and state == 'running':
                print(f"    {Y}Testing http://{pub_ip} ...{X}")
                try:
                    with urllib.request.urlopen(f"http://{pub_ip}", timeout=10, context=ssl_ctx) as resp:
                        html = resp.read().decode('utf-8', errors='ignore')
                        cl = html.lower().replace(' ', '').replace('\n', '')
                        if name in cl and sid in html.lower():
                            t2 += ok("Web page: Name AND ID displayed", 5)
                        elif name in cl:
                            t2 += partial("Web page: Name found, ID missing", 3, 5)
                        else:
                            t2 += fail("Web page content", 5, "Name/ID not found")
                except Exception as e:
                    t2 += fail("Web page accessible", 5, str(e)[:80])
            else:
                t2 += fail("Web page", 5, f"State: {state}, IP: {pub_ip or 'none'}")
        else:
            t2 += fail("EC2 instance found", 5, f"No instance named 'ec2-{name}'")
            t2 += fail("Web page", 5)

    except Exception as e:
        print(f"  {R}Error Question 2: {e}{X}")

    task_scores['Question 2: EC2 + LT      '] = t2
    print(f"\n  {B}Question 2 Subtotal: {t2} / 25{X}")

    # ==========================================================
    # QUESTION 3 - DYNAMODB TABLE (25 MARKS)
    # ==========================================================
    section("Question 3: DynamoDB Table")
    t3 = 0
    try:
        tbls = ddb.list_tables()['TableNames']
        target_t = next((t for t in tbls if f"ddb-{name}" in t.lower().replace(' ', '')), None)

        if target_t:
            t3 += ok(f"Table found: {target_t}", 5)
            desc = ddb.describe_table(TableName=target_t)['Table']
            keys = desc['KeySchema']
            attrs = {a['AttributeName']: a['AttributeType'] for a in desc['AttributeDefinitions']}

            pk = next((k['AttributeName'] for k in keys if k['KeyType'] == 'HASH'), None)
            sk = next((k['AttributeName'] for k in keys if k['KeyType'] == 'RANGE'), None)

            if pk == 'student_id' and attrs.get(pk) == 'S':
                t3 += ok("PK: student_id (String)", 5)
            elif pk == 'student_id':
                t3 += partial("PK: student_id", 3, 5, f"Type: {attrs.get(pk, '?')} (expected S)")
            elif pk:
                t3 += partial("PK exists", 2, 5, f"Found: {pk} (expected student_id)")
            else:
                t3 += fail("PK: student_id", 5)

            if sk == 'course_code' and attrs.get(sk) == 'S':
                t3 += ok("SK: course_code (String)", 5)
            elif sk == 'course_code':
                t3 += partial("SK: course_code", 3, 5, f"Type: {attrs.get(sk, '?')} (expected S)")
            elif sk:
                t3 += partial("SK exists", 2, 5, f"Found: {sk} (expected course_code)")
            else:
                t3 += fail("SK: course_code", 5)

            scan = ddb.scan(TableName=target_t)
            items = scan.get('Items', [])
            has_item = any(
                i.get('course_code', {}).get('S', '').upper() == 'BMIT3273'
                for i in items
            )
            t3 += ok("Item with course_code = BMIT3273", 5) if has_item \
                else fail("Item with course_code = BMIT3273", 5)

            has_active = any(
                i.get('status', {}).get('S', '').lower() == 'active'
                for i in items
            )
            has_any_status = any(i.get('status', {}).get('S', '') for i in items)
            if has_active:
                t3 += ok("Item has status = active", 5)
            elif has_any_status:
                found_status = next((i.get('status', {}).get('S', '') for i in items if i.get('status', {}).get('S', '')), '')
                t3 += partial("Status exists", 2, 5, f"Found: '{found_status}' (expected active)")
            else:
                t3 += fail("Item status = active", 5)
        else:
            t3 += fail("DynamoDB table found", 5, f"No table containing 'ddb-{name}'")
            for d, p in [("Partition key", 5), ("Sort key", 5), ("Item", 5), ("Status", 5)]:
                t3 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 3: {e}{X}")

    task_scores['Question 3: DynamoDB      '] = t3
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
            t4 += ok(f"EFS file system: {target_fs.get('Name', fsid)}", 7)

            pm = target_fs.get('PerformanceMode', '')
            if pm == 'generalPurpose':
                t4 += ok("Performance mode: generalPurpose", 3)
            elif pm:
                t4 += partial("Performance mode", 1, 3, f"Found: {pm}")
            else:
                t4 += fail("Performance mode", 3)

            # Check tags
            tags_resp = efs.describe_tags(FileSystemId=fsid)
            tags = tags_resp.get('Tags', [])
            proj = next((t['Value'] for t in tags if t['Key'] == 'Project'), '')
            if proj.upper() == 'BMIT3273':
                t4 += ok("Tag Project = BMIT3273", 5)
            elif proj:
                t4 += partial("Tag Project", 2, 5, f"Found: '{proj}'")
            else:
                t4 += fail("Tag Project", 5, "No Project tag")

            mts = efs.describe_mount_targets(FileSystemId=fsid)['MountTargets']
            t4 += ok(f"Mount target(s) exist: {len(mts)} AZ(s)", 10) if len(mts) > 0 \
                else fail("Mount target exists", 10, "No mount targets")
        else:
            t4 += fail("EFS file system found", 7, f"No EFS named 'efs-{name}'")
            for d, p in [("Performance mode", 3), ("Tag Project", 5), ("Mount target", 10)]:
                t4 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 4: {e}{X}")

    task_scores['Question 4: EFS           '] = t4
    print(f"\n  {B}Question 4 Subtotal: {t4} / 25{X}")

    # ==========================================================
    #  FINAL RESULT
    # ==========================================================
    banner("FINAL RESULT")
    for task, score in task_scores.items():
        filled = int(score * 10 / 25)
        bar = '#' * filled + '-' * (10 - filled)
        print(f"  {task} {bar} {score:2d}/25")

    print(f"\n  {'-'*44}")
    color = G if SCORE >= 80 else (Y if SCORE >= 50 else R)
    print(f"  {color}{B}  TOTAL SCORE :  {SCORE} / 100{X}")
    print(f"  {'-'*44}")

    if SCORE == 100:
        print(f"\n  {G}{B}  *  PERFECT SCORE - Excellent work!  *{X}")
    elif SCORE >= 80:
        print(f"\n  {G}  Great job! Review any missed items above.{X}")
    elif SCORE >= 50:
        print(f"\n  {Y}  Decent progress. Check failed items and retry.{X}")
    else:
        print(f"\n  {R}  Needs improvement. Re-read instructions carefully.{X}")
    print()
    print("  Mr Low blessing you!")


if __name__ == "__main__":
    main()

