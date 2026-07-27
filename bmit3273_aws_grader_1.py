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
#  BMIT3273 CLOUD COMPUTING - PRACTICAL TEST SET 1 AUTO GRADER
#  Topics: EC2 + Launch Template | S3 Static Website | Lambda | DynamoDB
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

def tag_val(tags, key):
    if not tags: return ''
    for t in tags:
        if t['Key'].lower() == key.lower(): return t['Value']
    return ''


def main():
    banner("BMIT3273 CLOUD COMPUTING - SET 1")
    print(f"  {W}Topics: EC2+LT | S3 Static Website | Lambda | DynamoDB{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()
    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2 = boto3.client('ec2')
    s3  = boto3.client('s3')
    lam = boto3.client('lambda')
    ddb = boto3.client('dynamodb')
    task_scores = {}

    # ==========================================================
    # QUESTION 1 - EC2 WITH LAUNCH TEMPLATE (25 MARKS)
    # ==========================================================
    section("Question 1: EC2 with Launch Template")
    t1 = 0
    try:
        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if f"lt-{name}" in lt['LaunchTemplateName'].lower().replace(' ', '')), None)

        if target_lt:
            t1 += ok(f"Launch Template: {target_lt['LaunchTemplateName']}", 5)
            ver = ec2.describe_launch_template_versions(
                LaunchTemplateId=target_lt['LaunchTemplateId']
            )['LaunchTemplateVersions'][0]
            data = ver['LaunchTemplateData']

            itype = data.get('InstanceType', '')
            if itype == 't3.micro':
                t1 += ok("Instance type: t3.micro", 3)
            elif itype in ('t2.micro', 't3.small', 't3.nano'):
                t1 += partial("Instance type", 2, 3, f"Found: {itype} (close)")
            else:
                t1 += fail("Instance type: t3.micro", 3, f"Found: {itype}")

            prof = data.get('IamInstanceProfile', {})
            pname = prof.get('Name', '') or prof.get('Arn', '')
            t1 += ok("LabInstanceProfile", 2) if 'LabInstanceProfile' in pname \
                else fail("LabInstanceProfile", 2)

            ud = data.get('UserData', '')
            if ud:
                try:
                    script = base64.b64decode(ud).decode('utf-8', errors='ignore').lower()
                    has_web = 'httpd' in script or 'nginx' in script or 'apache' in script
                    if has_web:
                        t1 += ok("User Data: web server install", 5)
                    else:
                        t1 += partial("User Data: script present", 2, 5, "No httpd/nginx detected")
                except:
                    t1 += partial("User Data: decode error", 1, 5)
            else:
                t1 += fail("User Data script", 5)
        else:
            t1 += fail("Launch Template", 5, f"No LT 'lt-{name}'")
            t1 += fail("Instance type", 3)
            t1 += fail("LabInstanceProfile", 2)
            t1 += fail("User Data", 5)

        # EC2 instance
        insts = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
        )['Reservations']
        target_ec2 = None
        for r in insts:
            for i in r['Instances']:
                n = tag_val(i.get('Tags', []), 'Name').lower().replace(' ', '')
                if f"ec2-{name}" in n:
                    target_ec2 = i; break
            if target_ec2: break

        if target_ec2:
            t1 += ok(f"EC2: {tag_val(target_ec2.get('Tags', []), 'Name')}", 5)

            pub_ip = target_ec2.get('PublicIpAddress', '')
            if pub_ip:
                print(f"    {Y}Checking web page at {pub_ip}...{X}")
                try:
                    req = urllib.request.Request(f"http://{pub_ip}", headers={'User-Agent': 'BMIT3273'})
                    with urllib.request.urlopen(req, timeout=6, context=ssl_ctx) as resp:
                        body = resp.read().decode('utf-8', errors='ignore').lower().replace(' ', '')
                    if name in body and sid in body:
                        t1 += ok("Web page: name + ID", 5)
                    elif name in body:
                        t1 += partial("Web page: name found", 4, 5, "ID missing")
                    elif len(body) > 50:
                        t1 += partial("Web page: loads", 2, 5, "Name & ID missing")
                    else:
                        t1 += fail("Web page content", 5)
                except:
                    t1 += fail("Web page", 5, "Cannot reach HTTP")
            else:
                t1 += fail("Web page", 5, "No public IP")
        else:
            t1 += fail("EC2 instance", 5, f"No running 'ec2-{name}'")
            t1 += fail("Web page", 5)
    except Exception as e:
        print(f"  {R}Error Question 1: {e}{X}")

    task_scores['Question 1: EC2 + LT     '] = t1
    print(f"\n  {B}Question 1 Subtotal: {t1} / 25{X}")

    # ==========================================================
    # QUESTION 2 - S3 STATIC WEBSITE (25 MARKS)
    # ==========================================================
    section("Question 2: S3 Static Website")
    t2 = 0
    try:
        buckets = s3.list_buckets()['Buckets']
        target_b = next((b['Name'] for b in buckets if f"s3-{name}" in b['Name']), None)

        if target_b:
            t2 += ok(f"Bucket: {target_b}", 3)

            try:
                ws = s3.get_bucket_website(Bucket=target_b)
                t2 += ok("Static website hosting enabled", 5)
            except:
                t2 += fail("Static website hosting", 5)

            try:
                s3.head_object(Bucket=target_b, Key='index.html')
                t2 += ok("index.html uploaded", 3)
            except:
                t2 += fail("index.html", 3)

            try:
                s3.head_object(Bucket=target_b, Key='error.html')
                t2 += ok("error.html uploaded", 2)
            except:
                t2 += fail("error.html", 2)

            try:
                pol = s3.get_bucket_policy(Bucket=target_b)
                policy_str = pol['Policy'].lower()
                if 'allow' in policy_str and 'getobject' in policy_str:
                    t2 += ok("Bucket policy: public read", 5)
                elif 'allow' in policy_str:
                    t2 += partial("Bucket policy: exists", 3, 5, "Missing GetObject")
                else:
                    t2 += partial("Bucket policy: exists", 2, 5, "Misconfigured")
            except:
                t2 += fail("Bucket policy", 5)

            website_url = f"http://{target_b}.s3-website-{region}.amazonaws.com"
            print(f"    {Y}Checking website: {website_url}{X}")
            try:
                req = urllib.request.Request(website_url, headers={'User-Agent': 'BMIT3273'})
                with urllib.request.urlopen(req, timeout=8, context=ssl_ctx) as resp:
                    body = resp.read().decode('utf-8', errors='ignore').lower().replace(' ', '')
                if name in body:
                    t2 += ok("Website shows student name", 7)
                elif len(body) > 50:
                    t2 += partial("Website accessible", 3, 7, "Student name missing")
                else:
                    t2 += fail("Website content", 7)
            except:
                t2 += fail("Website accessible", 7, "Cannot reach endpoint")
        else:
            t2 += fail("Bucket", 3, f"No 's3-{name}'")
            for d, p in [("Hosting", 5), ("index.html", 3), ("error.html", 2),
                         ("Policy", 5), ("Website", 7)]:
                t2 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 2: {e}{X}")

    task_scores['Question 2: S3 Website   '] = t2
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
            if rt.startswith('python3'):
                t3 += ok(f"Runtime: {rt}", 3)
            elif 'python' in rt.lower():
                t3 += partial("Runtime", 2, 3, f"Found: {rt}")
            else:
                t3 += fail("Runtime Python3", 3, f"Found: {rt}")

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
                    if name in pc and sid in payload.lower():
                        t3 += ok("Response: name + ID", 5)
                    elif name in pc:
                        t3 += partial("Response: name only", 3, 5, "ID missing")
                    elif sid in payload.lower():
                        t3 += partial("Response: ID only", 2, 5, "Name missing")
                    else:
                        t3 += fail("Response content", 5, "Name & ID missing")
                else:
                    t3 += fail("Invoke", 3, f"Error: {inv.get('FunctionError')}")
                    t3 += fail("Response", 5)
            except Exception as e:
                t3 += fail("Invoke", 3, str(e)[:80])
                t3 += fail("Response", 5)

        except lam.exceptions.ResourceNotFoundException:
            t3 += fail("Lambda", 5, f"No '{fname}'")
            for d, p in [("Runtime", 3), ("LabRole", 3), ("Env NAME", 3), ("Env ID", 3),
                         ("Invoke", 3), ("Response", 5)]:
                t3 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 3: {e}{X}")

    task_scores['Question 3: Lambda       '] = t3
    print(f"\n  {B}Question 3 Subtotal: {t3} / 25{X}")

    # ==========================================================
    # QUESTION 4 - DYNAMODB TABLE (25 MARKS)
    # ==========================================================
    section("Question 4: DynamoDB Table")
    t4 = 0
    try:
        tables = ddb.list_tables()['TableNames']
        target_t = next((t for t in tables if f"ddb-{name}" in t.lower().replace(' ', '')), None)

        if target_t:
            t4 += ok(f"Table: {target_t}", 5)
            desc = ddb.describe_table(TableName=target_t)['Table']
            keys = {k['AttributeName']: k['KeyType'] for k in desc.get('KeySchema', [])}

            pk = [n for n, t in keys.items() if t == 'HASH']
            sk = [n for n, t in keys.items() if t == 'RANGE']

            if pk and pk[0].lower() == 'student_id':
                t4 += ok(f"PK: {pk[0]}", 5)
            elif pk:
                t4 += partial("PK exists", 2, 5, f"Found: {pk[0]} (expected student_id)")
            else:
                t4 += fail("PK: student_id", 5)

            if sk and sk[0].lower() == 'course_code':
                t4 += ok(f"SK: {sk[0]}", 5)
            elif sk:
                t4 += partial("SK exists", 2, 5, f"Found: {sk[0]} (expected course_code)")
            else:
                t4 += fail("SK: course_code", 5)

            try:
                resp = ddb.get_item(
                    TableName=target_t,
                    Key={'student_id': {'S': sid.upper()}, 'course_code': {'S': 'BMIT3273'}}
                )
                item = resp.get('Item')
                if not item:
                    resp2 = ddb.get_item(
                        TableName=target_t,
                        Key={'student_id': {'S': sid}, 'course_code': {'S': 'BMIT3273'}}
                    )
                    item = resp2.get('Item')

                if item:
                    t4 += ok("Item: student record", 5)
                    status = item.get('status', {}).get('S', '').lower()
                    if status == 'active':
                        t4 += ok("Status: active", 5)
                    elif status:
                        t4 += partial("Status exists", 2, 5, f"Found: '{status}'")
                    else:
                        t4 += fail("status=active", 5)
                else:
                    # Try scanning for any item with the student ID
                    scan = ddb.scan(TableName=target_t, Limit=10)
                    has_any = any(True for i in scan.get('Items', []))
                    if has_any:
                        t4 += partial("Item: exists", 2, 5, "Key values don't match exactly")
                        t4 += fail("Status", 5)
                    else:
                        t4 += fail("Item", 5, "Table is empty")
                        t4 += fail("Status", 5)
            except Exception as e:
                t4 += fail("Item", 5, str(e)[:80])
                t4 += fail("Status", 5)
        else:
            t4 += fail("Table", 5, f"No 'ddb-{name}'")
            for d, p in [("PK", 5), ("SK", 5), ("Item", 5), ("Status", 5)]:
                t4 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 4: {e}{X}")

    task_scores['Question 4: DynamoDB     '] = t4
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

