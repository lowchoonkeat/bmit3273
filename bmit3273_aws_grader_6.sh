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
#  BMIT3273 CLOUD COMPUTING - PRACTICAL TEST SET 6 AUTO GRADER
#  Topics: VPC & Networking | RDS Database | S3 Versioning | Lambda
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
    for t in resource.get('Tags', []):
        if t['Key'] == key: return t['Value']
    return ''

def find_by_tag(resources, prefix, student):
    target = f"{prefix}-{student}"
    for r in resources:
        n = tag_val(r, 'Name').lower().replace(' ', '')
        if target in n: return r
    return None


def main():
    banner("BMIT3273 CLOUD COMPUTING - SET 6")
    print(f"  {W}Practical Test Auto Grader v1.0{X}")
    print(f"  {W}Topics: VPC | RDS | S3 Versioning | Lambda{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()

    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2 = boto3.client('ec2')
    rds = boto3.client('rds')
    s3  = boto3.client('s3')
    lam = boto3.client('lambda')

    task_scores = {}

    # ==========================================================
    # QUESTION 1 - VPC & NETWORKING (25 MARKS)
    # ==========================================================
    section("Question 1: Custom VPC & Networking")
    t1 = 0
    vpc_id = None
    try:
        vpcs = ec2.describe_vpcs()['Vpcs']
        vpc = find_by_tag(vpcs, 'vpc', name)
        if vpc:
            vpc_id = vpc['VpcId']
            t1 += ok(f"VPC: {tag_val(vpc,'Name')} [{vpc_id}]", 5)
            cidr = vpc.get('CidrBlock', '')
            if cidr == '10.0.0.0/16':
                t1 += ok("VPC CIDR: 10.0.0.0/16", 3)
            elif cidr.startswith('10.'):
                t1 += partial("VPC CIDR", 1, 3, f"Found: {cidr}")
            else:
                t1 += fail("VPC CIDR: 10.0.0.0/16", 3, f"Found: {cidr}")
        else:
            t1 += fail("VPC found", 5, f"No VPC named 'vpc-{name}'")
            t1 += fail("VPC CIDR", 3)

        subs = ec2.describe_subnets()['Subnets']
        pub_sub = find_by_tag(subs, 'pubsub', name)
        if pub_sub:
            in_vpc = vpc_id and pub_sub['VpcId'] == vpc_id
            sc = pub_sub.get('CidrBlock', '')
            if in_vpc and sc == '10.0.1.0/24':
                t1 += ok("Public subnet: pubsub-<name> 10.0.1.0/24", 4)
            elif in_vpc:
                t1 += partial("Public subnet in VPC but wrong CIDR", 2, 4, f"Found: {sc}")
            else:
                t1 += partial("Public subnet found but not in VPC", 2, 4)
        else:
            t1 += fail("Public subnet found", 4, f"No subnet named 'pubsub-{name}'")

        priv_sub = find_by_tag(subs, 'privsub', name)
        if priv_sub:
            in_vpc = vpc_id and priv_sub['VpcId'] == vpc_id
            sc = priv_sub.get('CidrBlock', '')
            if in_vpc and sc == '10.0.2.0/24':
                t1 += ok("Private subnet: privsub-<name> 10.0.2.0/24", 4)
            elif in_vpc:
                t1 += partial("Private subnet in VPC but wrong CIDR", 2, 4, f"Found: {sc}")
            else:
                t1 += partial("Private subnet found but not in VPC", 2, 4)
        else:
            t1 += fail("Private subnet found", 4, f"No subnet named 'privsub-{name}'")

        igws = ec2.describe_internet_gateways()['InternetGateways']
        igw = find_by_tag(igws, 'igw', name)
        if igw:
            attached = [a['VpcId'] for a in igw.get('Attachments', []) if a.get('VpcId') and a.get('State') in ('attached', 'available')]
            if vpc_id and vpc_id in attached:
                t1 += ok("IGW attached to VPC", 5)
            elif attached:
                t1 += partial("IGW attached to wrong VPC", 2, 5)
            else:
                t1 += partial("IGW found but not attached", 2, 5)
        else:
            t1 += fail("IGW found", 5, f"No IGW named 'igw-{name}'")

        rtbs = ec2.describe_route_tables()['RouteTables']
        rtb = find_by_tag(rtbs, 'rtb', name)
        if rtb:
            has_pub = any(
                r.get('DestinationCidrBlock') == '0.0.0.0/0'
                and r.get('GatewayId', '').startswith('igw-')
                for r in rtb.get('Routes', [])
            )
            t1 += ok("Route Table with 0.0.0.0/0 -> IGW", 4) if has_pub \
                else fail("Route 0.0.0.0/0 -> IGW", 4, "No public route")
        else:
            found = False
            if vpc_id:
                for r in rtbs:
                    if r.get('VpcId') == vpc_id:
                        for route in r.get('Routes', []):
                            if route.get('DestinationCidrBlock') == '0.0.0.0/0' and route.get('GatewayId', '').startswith('igw-'):
                                t1 += partial("RTB not named but VPC has public route", 2, 4)
                                found = True; break
                    if found: break
            if not found:
                t1 += fail("Route Table found", 4, f"No RTB named 'rtb-{name}'")

    except Exception as e:
        print(f"  {R}Error Question 1: {e}{X}")

    task_scores['Question 1: VPC & Network'] = t1
    print(f"\n  {B}Question 1 Subtotal: {t1} / 25{X}")

    # ==========================================================
    # QUESTION 2 - RDS DATABASE (25 MARKS)
    # ==========================================================
    section("Question 2: RDS Database Instance")
    t2 = 0
    try:
        dbs = rds.describe_db_instances()['DBInstances']
        target_rds = next((d for d in dbs if f"rds-{name}" in d['DBInstanceIdentifier'].lower().replace(' ', '')), None)

        if target_rds:
            t2 += ok(f"RDS: {target_rds['DBInstanceIdentifier']}", 3)

            engine = target_rds.get('Engine', '')
            t2 += ok("Engine: MySQL", 3) if 'mysql' in engine.lower() \
                else fail("Engine: MySQL", 3, f"Found: {engine}")

            ic = target_rds.get('DBInstanceClass', '')
            if ic == 'db.t3.micro':
                t2 += ok("Instance class: db.t3.micro", 3)
            elif ic in ('db.t2.micro', 'db.t3.small', 'db.t4g.micro'):
                t2 += partial("Instance class", 2, 3, f"Found: {ic} (close)")
            else:
                t2 += fail("Instance class: db.t3.micro", 3, f"Found: {ic}")

            storage = target_rds.get('AllocatedStorage', 0)
            t2 += ok("Storage: 20 GB", 2) if storage == 20 \
                else fail("Storage: 20 GB", 2, f"Found: {storage} GB")

            dbname = target_rds.get('DBName', '')
            t2 += ok("Initial DB: studentdb", 4) if dbname == 'studentdb' \
                else fail("Initial DB: studentdb", 4, f"Found: '{dbname}'")

            # SG check port 3306
            vpc_sgs = target_rds.get('VpcSecurityGroups', [])
            has_3306 = False
            if vpc_sgs:
                sg_id = vpc_sgs[0]['VpcSecurityGroupId']
                sg_resp = ec2.describe_security_groups(GroupIds=[sg_id])
                perms = sg_resp['SecurityGroups'][0]['IpPermissions']
                for p in perms:
                    if p.get('FromPort') == 3306 or p.get('IpProtocol') == '-1':
                        has_3306 = True; break
            t2 += ok("SG: Port 3306 open", 5) if has_3306 \
                else fail("SG: Port 3306", 5)

            pub = target_rds.get('PubliclyAccessible', True)
            t2 += ok("Not publicly accessible", 5) if not pub \
                else fail("Not publicly accessible", 5, "Public access is ON")
        else:
            t2 += fail("RDS instance found", 3, f"No RDS named 'rds-{name}'")
            for d, p in [("Engine", 3), ("Instance class", 3), ("Storage", 2),
                         ("Initial DB", 4), ("SG 3306", 5), ("Not public", 5)]:
                t2 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 2: {e}{X}")

    task_scores['Question 2: RDS Database '] = t2
    print(f"\n  {B}Question 2 Subtotal: {t2} / 25{X}")

    # ==========================================================
    # QUESTION 3 - S3 VERSIONING & LIFECYCLE (25 MARKS)
    # ==========================================================
    section("Question 3: S3 Versioning & Lifecycle")
    t3 = 0
    try:
        buckets = s3.list_buckets()['Buckets']
        target_b = next((b['Name'] for b in buckets if f"s3-{name}" in b['Name']), None)

        if target_b:
            t3 += ok(f"Bucket found: {target_b}", 2)

            try:
                tags = s3.get_bucket_tagging(Bucket=target_b)['TagSet']
                has_tag = any(t['Key'].lower() == 'project' and t['Value'].lower() == 'finaltest' for t in tags)
                has_key = any(t['Key'].lower() == 'project' for t in tags)
                if has_tag:
                    t3 += ok("Tag Project = FinalTest", 4)
                elif has_key:
                    found_val = next((t['Value'] for t in tags if t['Key'].lower() == 'project'), '')
                    t3 += partial("Tag Project", 2, 4, f"Value: '{found_val}' (expected FinalTest)")
                else:
                    t3 += fail("Tag Project = FinalTest", 4)
            except:
                t3 += fail("Tag Project = FinalTest", 4, "No tags")

            ver = s3.get_bucket_versioning(Bucket=target_b)
            t3 += ok("Versioning enabled", 5) if ver.get('Status') == 'Enabled' \
                else fail("Versioning enabled", 5)

            try:
                lc = s3.get_bucket_lifecycle_configuration(Bucket=target_b)
                has_ia = any(
                    t.get('StorageClass') == 'STANDARD_IA'
                    for r in lc.get('Rules', [])
                    for t in r.get('Transitions', [])
                )
                t3 += ok("Lifecycle: transition to Standard-IA", 9) if has_ia \
                    else fail("Lifecycle: Standard-IA", 9, "No matching rule")
            except:
                t3 += fail("Lifecycle rule", 9, "No lifecycle configuration")

            try:
                s3.head_object(Bucket=target_b, Key='config.txt')
                t3 += ok("File config.txt uploaded", 5)
            except:
                t3 += fail("File config.txt", 5)
        else:
            t3 += fail("S3 bucket found", 2, f"No bucket containing 's3-{name}'")
            for d, p in [("Tag", 4), ("Versioning", 5), ("Lifecycle", 9), ("config.txt", 5)]:
                t3 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 3: {e}{X}")

    task_scores['Question 3: S3 Lifecycle '] = t3
    print(f"\n  {B}Question 3 Subtotal: {t3} / 25{X}")

    # ==========================================================
    # QUESTION 4 - LAMBDA FUNCTION (25 MARKS)
    # ==========================================================
    section("Question 4: Lambda Function")
    t4 = 0
    try:
        fname = f"lambda-{name}"
        try:
            func = lam.get_function(FunctionName=fname)
            cfg  = func['Configuration']
            t4 += ok(f"Lambda: {fname}", 5)

            rt = cfg.get('Runtime', '')
            t4 += ok(f"Runtime: {rt}", 3) if rt.startswith('python3') \
                else fail("Runtime: Python 3.x", 3, f"Found: {rt}")

            role = cfg.get('Role', '')
            t4 += ok("Execution Role: LabRole", 3) if 'LabRole' in role \
                else fail("LabRole", 3, f"Found: {role.split('/')[-1]}")

            env = cfg.get('Environment', {}).get('Variables', {})
            t4 += ok(f"Env STUDENT_NAME set", 3) if 'STUDENT_NAME' in env else fail("Env STUDENT_NAME", 3)
            t4 += ok(f"Env STUDENT_ID set", 3) if 'STUDENT_ID' in env else fail("Env STUDENT_ID", 3)

            print(f"    {Y}Invoking {fname} ...{X}")
            try:
                inv = lam.invoke(FunctionName=fname, InvocationType='RequestResponse')
                if inv.get('StatusCode') == 200 and not inv.get('FunctionError'):
                    t4 += ok("Invocation success (200)", 3)
                    payload = inv['Payload'].read().decode('utf-8')
                    pc = payload.lower().replace(' ', '')
                    if name in pc and sid in payload.lower():
                        t4 += ok("Response: name + ID", 5)
                    elif name in pc:
                        t4 += partial("Response: name only", 3, 5, "ID missing")
                    elif sid in payload.lower():
                        t4 += partial("Response: ID only", 2, 5, "Name missing")
                    else:
                        t4 += fail("Response content", 5, "Name & ID missing")
                else:
                    t4 += fail("Invocation", 3, f"Error: {inv.get('FunctionError')}")
                    t4 += fail("Response: name", 3); t4 += fail("Response: ID", 2)
            except Exception as e:
                t4 += fail("Invocation", 3, str(e)[:80])
                t4 += fail("Response: name", 3); t4 += fail("Response: ID", 2)

        except lam.exceptions.ResourceNotFoundException:
            t4 += fail("Lambda found", 5, f"No function '{fname}'")
            for d, p in [("Runtime", 3), ("LabRole", 3), ("Env NAME", 3), ("Env ID", 3),
                         ("Invoke", 3), ("Response name", 3), ("Response ID", 2)]:
                t4 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Question 4: {e}{X}")

    task_scores['Question 4: Lambda       '] = t4
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
    elif SCORE >= 80: print(f"\n  {G}  Great job! Review any missed items above.{X}")
    elif SCORE >= 50: print(f"\n  {Y}  Decent progress. Check failed items and retry.{X}")
    else: print(f"\n  {R}  Needs improvement. Re-read instructions carefully.{X}")
    print()
    print("  Mr Low blessing you!")

if __name__ == "__main__":
    main()

