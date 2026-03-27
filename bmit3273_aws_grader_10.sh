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

# ═══════════════════════════════════════════════════════════════
#  BMIT3273 CLOUD COMPUTING — PRACTICAL TEST SET 10 AUTO GRADER
#  Topics: EC2 & Security | DynamoDB | EBS | ALB + Auto Scaling
# ═══════════════════════════════════════════════════════════════

ssl_ctx = ssl._create_unverified_context()
SCORE = 0

G  = '\033[92m';  R  = '\033[91m';  Y  = '\033[93m'
C  = '\033[96m';  B  = '\033[1m';   W  = '\033[97m';  X  = '\033[0m'

def banner(t): print(f"\n{C}{B}{'═'*60}\n  {t}\n{'═'*60}{X}")
def section(t): print(f"\n{C}{'─'*60}\n  {t}\n{'─'*60}{X}")

def ok(d, p):
    global SCORE; SCORE += p
    print(f"  {G}[✓] +{p:2d}  {d}{X}"); return p

def fail(d, p, r=""):
    print(f"  {R}[✗]  0/{p:<2d} {d}{X}")
    if r: print(f"       {Y}→ {r}{X}")
    return 0

def partial(d, earned, total, r=""):
    global SCORE; SCORE += earned
    sym = Y if earned > 0 else R
    print(f"  {sym}[~] +{earned}/{total}  {d}{X}")
    if r: print(f"       {Y}→ {r}{X}")
    return earned

def tag_val(tags, key):
    if not tags: return ''
    for t in tags:
        if t['Key'].lower() == key.lower(): return t['Value']
    return ''

def find_sg(ec2, name):
    sgs = ec2.describe_security_groups()['SecurityGroups']
    return next((s for s in sgs if f"web-{name}" in s['GroupName'].lower().replace(' ', '')), None)


def main():
    banner("BMIT3273 CLOUD COMPUTING — SET 10")
    print(f"  {W}Topics: EC2 & Security | DynamoDB | EBS | ALB + ASG{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()
    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2 = boto3.client('ec2')
    ddb = boto3.client('dynamodb')
    asg_client = boto3.client('autoscaling')
    elbv2 = boto3.client('elbv2')
    task_scores = {}

    # ══════════════════════════════════════════════════════════
    #  TASK 1 — EC2 INSTANCE & SECURITY (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 1: EC2 Instance & Security (25 Marks)")
    t1 = 0
    try:
        # Security group
        sg = find_sg(ec2, name)
        if sg:
            t1 += ok(f"SG: {sg['GroupName']}", 3)
            perms = sg.get('IpPermissions', [])
            ports = set()
            for p in perms:
                fp = p.get('FromPort', 0)
                tp = p.get('ToPort', 0)
                if fp == tp: ports.add(fp)
                elif fp <= 22 <= tp: ports.add(22)

            t1 += ok("SG: port 22 (SSH)", 2) if 22 in ports else fail("SG: SSH", 2)
            t1 += ok("SG: port 80 (HTTP)", 2) if 80 in ports else fail("SG: HTTP", 2)
            t1 += ok("SG: port 443 (HTTPS)", 2) if 443 in ports else fail("SG: HTTPS", 2)
        else:
            t1 += fail("Security Group", 3, f"No 'web-{name}'")
            t1 += fail("SSH", 2); t1 += fail("HTTP", 2); t1 += fail("HTTPS", 2)

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
            t1 += ok(f"EC2: {tag_val(target_ec2.get('Tags', []), 'Name')}", 3)
            itype = target_ec2.get('InstanceType', '')
            if itype == 't3.micro':
                t1 += ok("Type: t3.micro", 2)
            elif itype in ('t2.micro', 't3.small', 't3.nano'):
                t1 += partial("Instance type close", 1, 2, f"Found: {itype}")
            else:
                t1 += fail("t3.micro", 2, f"Found: {itype}")

            prof = target_ec2.get('IamInstanceProfile', {}).get('Arn', '')
            t1 += ok("LabInstanceProfile", 3) if 'LabInstanceProfile' in prof else fail("LabInstanceProfile", 3)

            # Web page check
            pub_ip = target_ec2.get('PublicIpAddress', '')
            if pub_ip:
                print(f"    {Y}Checking web page at {pub_ip}...{X}")
                try:
                    req = urllib.request.Request(f"http://{pub_ip}", headers={'User-Agent': 'BMIT3273'})
                    with urllib.request.urlopen(req, timeout=6, context=ssl_ctx) as resp:
                        body = resp.read().decode('utf-8', errors='ignore').lower().replace(' ', '')
                    has_name = name in body
                    has_id = sid in body.lower()
                    if has_name and has_id:
                        t1 += ok("Web page: name AND ID", 8)
                    elif has_name:
                        t1 += partial("Web page: name only", 5, 8)
                    elif has_id:
                        t1 += partial("Web page: ID only", 3, 8)
                    else:
                        t1 += partial("Page loads, content missing", 1, 8)
                except:
                    t1 += fail("Web page", 8, "Cannot reach HTTP")
            else:
                t1 += fail("Web page", 8, "No public IP")
        else:
            t1 += fail("EC2", 3, f"No running 'ec2-{name}'")
            for d, p in [("Type", 2), ("Profile", 3), ("Web page", 8)]: t1 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Task 1: {e}{X}")

    task_scores['Task 1: EC2 Security '] = t1
    print(f"\n  {B}Task 1 Subtotal: {t1} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 2 — DYNAMODB TABLE (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 2: DynamoDB Table (25 Marks)")
    t2 = 0
    try:
        tables = ddb.list_tables()['TableNames']
        target_t = next((t for t in tables if f"ddb-{name}" in t.lower().replace(' ', '')), None)

        if target_t:
            t2 += ok(f"Table: {target_t}", 5)
            desc = ddb.describe_table(TableName=target_t)['Table']
            keys = {k['AttributeName']: k['KeyType'] for k in desc.get('KeySchema', [])}

            pk = [n for n, t in keys.items() if t == 'HASH']
            sk = [n for n, t in keys.items() if t == 'RANGE']

            if pk and pk[0].lower() == 'student_id':
                t2 += ok(f"PK: {pk[0]}", 5)
            elif pk:
                t2 += partial("PK exists", 2, 5, f"Found: {pk[0]}")
            else:
                t2 += fail("PK: student_id", 5)
            if sk and sk[0].lower() == 'course_code':
                t2 += ok(f"SK: {sk[0]}", 5)
            elif sk:
                t2 += partial("SK exists", 2, 5, f"Found: {sk[0]}")
            else:
                t2 += fail("SK: course_code", 5, "No sort key defined")

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
                    t2 += ok("Item: student record", 5)
                    status = item.get('status', {}).get('S', '').lower()
                    if status == 'active':
                        t2 += ok("Status: active", 5)
                    elif status:
                        t2 += partial("Status exists", 2, 5, f"Found: '{status}'")
                    else:
                        t2 += fail("status=active", 5, "No status attribute")
                else:
                    t2 += fail("Item", 5, "No matching item")
                    t2 += fail("Status", 5)
            except Exception as e:
                t2 += fail("Item", 5, str(e)[:80]); t2 += fail("Status", 5)
        else:
            t2 += fail("Table", 5, f"No 'ddb-{name}'")
            for d, p in [("PK", 5), ("SK", 5), ("Item", 5), ("Status", 5)]: t2 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Task 2: {e}{X}")

    task_scores['Task 2: DynamoDB     '] = t2
    print(f"\n  {B}Task 2 Subtotal: {t2} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 3 — EBS VOLUME & SNAPSHOT (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 3: EBS Volume & Snapshot (25 Marks)")
    t3 = 0
    try:
        vols = ec2.describe_volumes()['Volumes']
        target_v = None
        for v in vols:
            n = tag_val(v.get('Tags', []), 'Name').lower().replace(' ', '')
            if f"ebs-{name}" in n:
                target_v = v; break

        if target_v:
            t3 += ok(f"Volume: {tag_val(target_v.get('Tags', []), 'Name')}", 5)

            vt = target_v.get('VolumeType', '')
            if vt == 'gp3':
                t3 += ok("Type: gp3", 3)
            elif vt == 'gp2':
                t3 += partial("Volume type close", 2, 3, f"Found: {vt}")
            else:
                t3 += fail("Type gp3", 3, f"Found: {vt}")

            sz = target_v.get('Size', 0)
            if sz == 10:
                t3 += ok("Size: 10 GiB", 3)
            elif 8 <= sz <= 12:
                t3 += partial("Size close", 1, 3, f"Found: {sz} GiB")
            else:
                t3 += fail("10 GiB", 3, f"Found: {sz}")

            att = target_v.get('Attachments', [])
            t3 += ok("Attached", 4) if att else fail("Attached", 4)

            proj = tag_val(target_v.get('Tags', []), 'Project')
            t3 += ok(f"Tag Project = {proj}", 3) if proj else fail("Tag Project", 3)
        else:
            t3 += fail("Volume", 5, f"No 'ebs-{name}'")
            for d, p in [("Type", 3), ("Size", 3), ("Attached", 4), ("Tag", 3)]: t3 += fail(d, p)

        # Snapshot
        snaps = ec2.describe_snapshots(OwnerIds=['self'])['Snapshots']
        target_s = None
        for s in snaps:
            n = tag_val(s.get('Tags', []), 'Name').lower().replace(' ', '')
            if f"snap-{name}" in n:
                target_s = s; break

        if target_s:
            t3 += ok(f"Snapshot: {tag_val(target_s.get('Tags', []), 'Name')}", 4)
            proj = tag_val(target_s.get('Tags', []), 'Project')
            t3 += ok(f"Snap Project = {proj}", 3) if proj else fail("Snap Tag Project", 3)
        else:
            t3 += fail("Snapshot", 4, f"No 'snap-{name}'")
            t3 += fail("Snap Tag", 3)
    except Exception as e:
        print(f"  {R}Error Task 3: {e}{X}")

    task_scores['Task 3: EBS          '] = t3
    print(f"\n  {B}Task 3 Subtotal: {t3} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 4 — ALB + AUTO SCALING (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 4: ALB + Auto Scaling (25 Marks)")
    t4 = 0
    try:
        # ALB
        lbs = elbv2.describe_load_balancers()['LoadBalancers']
        target_lb = next(
            (l for l in lbs if f"alb-{name}" in l['LoadBalancerName'].lower().replace(' ', '') and l['Type'] == 'application'),
            None)

        if target_lb:
            t4 += ok(f"ALB: {target_lb['LoadBalancerName']}", 3)
            scheme = target_lb.get('Scheme', '')
            t4 += ok("Scheme: internet-facing", 3) if scheme == 'internet-facing' \
                else fail("internet-facing", 3, f"Found: {scheme}")
        else:
            t4 += fail("ALB", 3, f"No 'alb-{name}'")
            t4 += fail("Scheme", 3)

        # Target Group
        tgs = elbv2.describe_target_groups()['TargetGroups']
        target_tg = next(
            (t for t in tgs if f"tg-{name}" in t['TargetGroupName'].lower().replace(' ', '')),
            None)

        if target_tg:
            t4 += ok(f"TG: {target_tg['TargetGroupName']}", 3)
            health = elbv2.describe_target_health(TargetGroupArn=target_tg['TargetGroupArn'])
            targets = health.get('TargetHealthDescriptions', [])
            healthy = [t for t in targets if t.get('TargetHealth', {}).get('State') == 'healthy']
            t4 += ok(f"Targets healthy: {len(healthy)}", 3) if healthy \
                else fail("Healthy targets", 3, f"{len(targets)} registered, 0 healthy")
        else:
            t4 += fail("TG", 3, f"No 'tg-{name}'")
            t4 += fail("Targets", 3)

        # ASG
        asgs = asg_client.describe_auto_scaling_groups()['AutoScalingGroups']
        target_asg = next(
            (a for a in asgs if f"asg-{name}" in a['AutoScalingGroupName'].lower().replace(' ', '')),
            None)

        if target_asg:
            mn, mx = target_asg['MinSize'], target_asg['MaxSize']
            if mn == 1 and mx == 3:
                t4 += ok("ASG: Min=1, Max=3", 5)
            elif mn == 1:
                t4 += partial("ASG Min correct", 2, 5, f"Max={mx}")
            elif mx == 3:
                t4 += partial("ASG Max correct", 2, 5, f"Min={mn}")
            else:
                t4 += fail("ASG 1/3", 5, f"Found Min={mn}, Max={mx}")

            pols = asg_client.describe_policies(
                AutoScalingGroupName=target_asg['AutoScalingGroupName']
            )['ScalingPolicies']
            t4 += ok("Scaling policy", 3) if pols else fail("Scaling policy", 3)
        else:
            t4 += fail("ASG", 5, f"No 'asg-{name}'")
            t4 += fail("Scaling policy", 3)

        # Web page via ALB DNS
        if target_lb:
            dns = target_lb.get('DNSName', '')
            if dns:
                print(f"    {Y}Checking ALB: {dns}...{X}")
                try:
                    req = urllib.request.Request(f"http://{dns}", headers={'User-Agent': 'BMIT3273'})
                    with urllib.request.urlopen(req, timeout=10, context=ssl_ctx) as resp:
                        body = resp.read().decode('utf-8', errors='ignore').lower().replace(' ', '')
                    t4 += ok("ALB web page accessible", 5) if len(body) > 10 \
                        else fail("ALB web page", 5)
                except:
                    t4 += fail("ALB web page", 5, "Cannot reach")
            else:
                t4 += fail("ALB DNS", 5)
        else:
            t4 += fail("ALB DNS", 5, "No ALB")
    except Exception as e:
        print(f"  {R}Error Task 4: {e}{X}")

    task_scores['Task 4: ALB + ASG    '] = t4
    print(f"\n  {B}Task 4 Subtotal: {t4} / 25{X}")

    # ══════════════════════════════════════════════════════════
    banner("FINAL RESULT")
    for task, score in task_scores.items():
        filled = int(score * 10 / 25); bar = '█' * filled + '░' * (10 - filled)
        print(f"  {task} {bar} {score:2d}/25")
    print(f"\n  {'─'*44}")
    color = G if SCORE >= 80 else (Y if SCORE >= 50 else R)
    print(f"  {color}{B}  TOTAL SCORE :  {SCORE} / 100{X}")
    print(f"  {'─'*44}")
    if SCORE == 100: print(f"\n  {G}{B}  ★  PERFECT SCORE — Excellent work!  ★{X}")
    elif SCORE >= 80: print(f"\n  {G}  Great job!{X}")
    elif SCORE >= 50: print(f"\n  {Y}  Decent progress.{X}")
    else: print(f"\n  {R}  Needs improvement.{X}")
    print()
    print("  Mr Low blessing you!")

if __name__ == "__main__":
    main()
