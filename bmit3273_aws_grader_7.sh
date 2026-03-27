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
#  BMIT3273 CLOUD COMPUTING — PRACTICAL TEST SET 7 AUTO GRADER
#  Topics: EC2 + Launch Template | ALB + TG | EBS | DynamoDB
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
    banner("BMIT3273 CLOUD COMPUTING — SET 7")
    print(f"  {W}Topics: EC2 + LT | ALB + TG | EBS | DynamoDB{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()
    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2   = boto3.client('ec2')
    elbv2 = boto3.client('elbv2')
    ddb   = boto3.client('dynamodb')
    task_scores = {}
    instance_id = None

    # ══════════════════════════════════════════════════════════
    #  TASK 1 — EC2 WITH LAUNCH TEMPLATE (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 1: EC2 with Launch Template (25 Marks)")
    t1 = 0
    try:
        lts = ec2.describe_launch_templates()['LaunchTemplates']
        target_lt = next((lt for lt in lts if f"lt-{name}" in lt['LaunchTemplateName'].lower().replace(' ', '')), None)

        if target_lt:
            t1 += ok(f"Launch Template: {target_lt['LaunchTemplateName']}", 4)
            ver = ec2.describe_launch_template_versions(LaunchTemplateId=target_lt['LaunchTemplateId'])['LaunchTemplateVersions'][0]
            data = ver['LaunchTemplateData']

            itype = data.get('InstanceType', '')
            if itype == 't3.micro':
                t1 += ok("Instance type: t3.micro", 3)
            elif itype in ('t2.micro', 't3.small', 't3.nano'):
                t1 += partial("Instance type", 2, 3, f"Found: {itype} (close)")
            else:
                t1 += fail("Instance type: t3.micro", 3, f"Found: {itype}")

            iam = data.get('IamInstanceProfile', {}).get('Name', '') or data.get('IamInstanceProfile', {}).get('Arn', '')
            t1 += ok("LabInstanceProfile", 3) if 'LabInstanceProfile' in iam else fail("LabInstanceProfile", 3)

            ud = data.get('UserData', '')
            if ud:
                try:
                    script = base64.b64decode(ud).decode('utf-8', errors='ignore').lower()
                    has_web = 'httpd' in script or 'nginx' in script
                    t1 += ok("User Data: web server", 5) if has_web \
                        else partial("User Data exists, no web server", 2, 5)
                except:
                    t1 += partial("User Data exists (decode err)", 2, 5)
            else:
                t1 += fail("User Data", 5)
        else:
            t1 += fail("Launch Template", 4, f"No LT 'lt-{name}'")
            t1 += fail("Instance type", 3); t1 += fail("LabInstanceProfile", 3); t1 += fail("User Data", 5)

        reservations = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running', 'stopped', 'pending']}]
        )['Reservations']
        all_inst = [i for r in reservations for i in r['Instances']]
        inst = find_by_tag(all_inst, 'ec2', name)

        if inst:
            instance_id = inst['InstanceId']
            t1 += ok(f"EC2 running: {instance_id}", 5)

            pub_ip = inst.get('PublicIpAddress', '')
            state = inst.get('State', {}).get('Name', '')
            if pub_ip and state == 'running':
                try:
                    with urllib.request.urlopen(f"http://{pub_ip}", timeout=10, context=ssl_ctx) as resp:
                        html = resp.read().decode('utf-8', errors='ignore').lower().replace(' ', '')
                        if name in html:
                            t1 += ok("Web page shows name", 5)
                        elif len(html) > 50:
                            t1 += partial("Web page loads", 2, 5, "Name not found")
                        else:
                            t1 += fail("Web page: name", 5)
                except Exception as e:
                    t1 += fail("Web page", 5, str(e)[:80])
            else:
                t1 += fail("Web page", 5, f"State={state}, IP={pub_ip or 'none'}")
        else:
            t1 += fail("EC2 instance", 5, f"No 'ec2-{name}'"); t1 += fail("Web page", 5)
    except Exception as e:
        print(f"  {R}Error Task 1: {e}{X}")

    task_scores['Task 1: EC2 + LT     '] = t1
    print(f"\n  {B}Task 1 Subtotal: {t1} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 2 — ALB + TARGET GROUP (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 2: ALB + Target Group (25 Marks)")
    t2 = 0
    alb_dns = None
    try:
        albs = elbv2.describe_load_balancers()['LoadBalancers']
        target_alb = next((a for a in albs if f"alb-{name}" in a['LoadBalancerName'].lower().replace(' ', '')), None)

        if target_alb:
            alb_dns = target_alb['DNSName']
            t2 += ok(f"ALB: {target_alb['LoadBalancerName']}", 3)
            t2 += ok("ALB internet-facing", 3) if target_alb['Scheme'] == 'internet-facing' \
                else fail("ALB internet-facing", 3, f"Scheme: {target_alb['Scheme']}")
        else:
            t2 += fail("ALB found", 3, f"No ALB 'alb-{name}'"); t2 += fail("Internet-facing", 3)

        tgs = elbv2.describe_target_groups()['TargetGroups']
        target_tg = next((t for t in tgs if f"tg-{name}" in t['TargetGroupName'].lower().replace(' ', '')), None)

        if target_tg:
            t2 += ok(f"Target Group: {target_tg['TargetGroupName']}", 3)

            health = elbv2.describe_target_health(TargetGroupArn=target_tg['TargetGroupArn'])
            healthy = any(t['TargetHealth']['State'] == 'healthy' for t in health['TargetHealthDescriptions'])
            registered = len(health['TargetHealthDescriptions']) > 0
            if healthy:
                t2 += ok("Target registered & healthy", 3)
            elif registered:
                t2 += partial("Target registered but unhealthy", 1, 3)
            else:
                t2 += fail("Target registered", 3, "No targets")

            hc = target_tg.get('HealthCheckPath', '')
            t2 += ok("Health check path: /", 3) if hc == '/' \
                else fail("Health check path: /", 3, f"Found: '{hc}'")
        else:
            t2 += fail("Target Group", 3, f"No TG 'tg-{name}'")
            t2 += fail("Target registered", 3); t2 += fail("Health check", 3)

        if alb_dns:
            print(f"    {Y}Testing http://{alb_dns} ...{X}")
            try:
                with urllib.request.urlopen(f"http://{alb_dns}", timeout=15, context=ssl_ctx) as resp:
                    html = resp.read().decode('utf-8', errors='ignore')
                    cl = html.lower().replace(' ', '')
                    if name in cl:
                        t2 += ok("ALB DNS loads page", 5)
                        t2 += ok("Page shows student name", 5)
                    elif html.strip():
                        t2 += ok("ALB DNS loads page", 5)
                        t2 += fail("Page: student name", 5, "Name not found")
                    else:
                        t2 += fail("ALB DNS", 5, "Empty response")
                        t2 += fail("Page: name", 5)
            except Exception as e:
                t2 += fail("ALB DNS loads", 5, str(e)[:80]); t2 += fail("Page: name", 5)
        else:
            t2 += fail("ALB DNS", 5); t2 += fail("Page: name", 5)
    except Exception as e:
        print(f"  {R}Error Task 2: {e}{X}")

    task_scores['Task 2: ALB + TG     '] = t2
    print(f"\n  {B}Task 2 Subtotal: {t2} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 3 — EBS VOLUME & SNAPSHOT (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 3: EBS Volume & Snapshot (25 Marks)")
    t3 = 0
    vol_id = None
    try:
        vols = ec2.describe_volumes()['Volumes']
        vol = find_by_tag(vols, 'ebs', name)

        if vol:
            vol_id = vol['VolumeId']
            t3 += ok(f"EBS Volume: {vol_id}", 5)

            vt = vol.get('VolumeType', '')
            t3 += ok("Volume type: gp3", 3) if vt == 'gp3' \
                else (partial("gp2 (expected gp3)", 1, 3) if vt == 'gp2' else fail("Type: gp3", 3, f"Found: {vt}"))

            vs = vol.get('Size', 0)
            t3 += ok("Size: 10 GB", 3) if vs == 10 else fail("Size: 10 GB", 3, f"Found: {vs} GB")

            att = vol.get('Attachments', [])
            if att and att[0].get('State') in ('attached', 'attaching'):
                ai = att[0].get('InstanceId', '')
                if instance_id and ai == instance_id:
                    t3 += ok(f"Attached to ec2-{name}", 4)
                elif instance_id:
                    t3 += partial("Attached to different instance", 2, 4)
                else:
                    t3 += ok("Attached to an instance", 4)
            else:
                t3 += fail("Attached to EC2", 4)

            proj = tag_val(vol, 'Project')
            if proj.upper() == 'BMIT3273':
                t3 += ok("Tag Project = BMIT3273", 3)
            elif proj:
                t3 += partial("Tag Project", 1, 3, f"Found: '{proj}'")
            else:
                t3 += fail("Tag Project", 3, "Missing")
        else:
            t3 += fail("EBS volume", 5, f"No volume 'ebs-{name}'")
            for d, p in [("Type", 3), ("Size", 3), ("Attached", 4), ("Tag", 3)]:
                t3 += fail(d, p)

        snaps = ec2.describe_snapshots(OwnerIds=['self'])['Snapshots']
        snap = find_by_tag(snaps, 'snap', name)
        if not snap and vol_id:
            snap = next((s for s in snaps if s.get('VolumeId') == vol_id), None)
        if snap:
            t3 += ok(f"Snapshot: {snap['SnapshotId']}", 4)
            sp = tag_val(snap, 'Project')
            if sp.upper() == 'BMIT3273':
                t3 += ok("Snapshot Tag Project = BMIT3273", 3)
            elif sp:
                t3 += partial("Snapshot Tag", 1, 3, f"Found: '{sp}'")
            else:
                t3 += fail("Snapshot Tag", 3, "Missing")
        else:
            t3 += fail("Snapshot", 4); t3 += fail("Snapshot Tag", 3)
    except Exception as e:
        print(f"  {R}Error Task 3: {e}{X}")

    task_scores['Task 3: EBS + Snap   '] = t3
    print(f"\n  {B}Task 3 Subtotal: {t3} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 4 — DYNAMODB TABLE (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 4: DynamoDB Table (25 Marks)")
    t4 = 0
    try:
        tbls = ddb.list_tables()['TableNames']
        target_t = next((t for t in tbls if f"ddb-{name}" in t.lower().replace(' ', '')), None)

        if target_t:
            t4 += ok(f"Table: {target_t}", 5)
            desc = ddb.describe_table(TableName=target_t)['Table']
            keys = desc['KeySchema']
            attrs = {a['AttributeName']: a['AttributeType'] for a in desc['AttributeDefinitions']}

            pk = next((k['AttributeName'] for k in keys if k['KeyType'] == 'HASH'), None)
            sk = next((k['AttributeName'] for k in keys if k['KeyType'] == 'RANGE'), None)

            if pk == 'student_id' and attrs.get(pk) == 'S':
                t4 += ok("PK: student_id (S)", 5)
            elif pk == 'student_id':
                t4 += partial("PK: student_id", 3, 5, f"Type: {attrs.get(pk, '?')}")
            elif pk:
                t4 += partial("PK exists", 2, 5, f"Found: {pk}")
            else:
                t4 += fail("PK: student_id", 5)

            if sk == 'subject' and attrs.get(sk) == 'S':
                t4 += ok("SK: subject (S)", 5)
            elif sk == 'subject':
                t4 += partial("SK: subject", 3, 5, f"Type: {attrs.get(sk, '?')}")
            elif sk:
                t4 += partial("SK exists", 2, 5, f"Found: {sk}")
            else:
                t4 += fail("SK: subject", 5)

            scan = ddb.scan(TableName=target_t)
            items = scan.get('Items', [])
            has_item = any(i.get('subject', {}).get('S', '').lower() == 'cloudcomputing' for i in items)
            t4 += ok("Item: subject=CloudComputing", 5) if has_item else fail("Item CloudComputing", 5)

            has_active = any(i.get('status', {}).get('S', '').lower() == 'active' for i in items)
            has_any_status = any(i.get('status', {}).get('S', '') for i in items)
            if has_active:
                t4 += ok("Item status = active", 5)
            elif has_any_status:
                found_s = next((i.get('status', {}).get('S', '') for i in items if i.get('status', {}).get('S', '')), '')
                t4 += partial("Status exists", 2, 5, f"Found: '{found_s}'")
            else:
                t4 += fail("Status active", 5)
        else:
            t4 += fail("DynamoDB table", 5, f"No table 'ddb-{name}'")
            for d, p in [("PK", 5), ("SK", 5), ("Item", 5), ("Status", 5)]: t4 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Task 4: {e}{X}")

    task_scores['Task 4: DynamoDB     '] = t4
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
