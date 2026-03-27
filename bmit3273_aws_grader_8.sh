import boto3
import json
import urllib.request
import ssl

# ═══════════════════════════════════════════════════════════════
#  BMIT3273 CLOUD COMPUTING — PRACTICAL TEST SET 8 AUTO GRADER
#  Topics: VPC & Networking | EC2 Web Server | S3 Static Website | RDS
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
    banner("BMIT3273 CLOUD COMPUTING — SET 8")
    print(f"  {W}Topics: VPC | EC2 | S3 Static Website | RDS{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()
    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2 = boto3.client('ec2')
    s3  = boto3.client('s3')
    rds_client = boto3.client('rds')
    task_scores = {}
    vpc_id = None

    # ══════════════════════════════════════════════════════════
    #  TASK 1 — VPC & NETWORKING (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 1: Custom VPC & Networking (25 Marks)")
    t1 = 0
    try:
        vpcs = ec2.describe_vpcs()['Vpcs']
        vpc = find_by_tag(vpcs, 'vpc', name)
        if vpc:
            vpc_id = vpc['VpcId']
            t1 += ok(f"VPC: {tag_val(vpc,'Name')}", 5)
            cidr = vpc.get('CidrBlock', '')
            if cidr == '10.0.0.0/16':
                t1 += ok("CIDR: 10.0.0.0/16", 3)
            elif cidr.startswith('10.'):
                t1 += partial("CIDR close", 1, 3, f"Found: {cidr}")
            else:
                t1 += fail("CIDR 10.0.0.0/16", 3, f"Found: {cidr}")
        else:
            t1 += fail("VPC", 5, f"No 'vpc-{name}'"); t1 += fail("CIDR", 3)

        subs = ec2.describe_subnets()['Subnets']
        sub = find_by_tag(subs, 'subnet', name)
        if sub:
            in_vpc = vpc_id and sub['VpcId'] == vpc_id
            t1 += ok("Subnet in VPC", 4) if in_vpc else partial("Subnet not in VPC", 2, 4)
            sc = sub.get('CidrBlock', '')
            t1 += ok("Subnet CIDR: 10.0.1.0/24", 2) if sc == '10.0.1.0/24' \
                else fail("Subnet CIDR", 2, f"Found: {sc}")
        else:
            t1 += fail("Subnet", 4, f"No 'subnet-{name}'"); t1 += fail("Subnet CIDR", 2)

        igws = ec2.describe_internet_gateways()['InternetGateways']
        igw = find_by_tag(igws, 'igw', name)
        if igw:
            attached = [a['VpcId'] for a in igw.get('Attachments', []) if a.get('State') == 'attached']
            t1 += ok("IGW attached to VPC", 5) if vpc_id and vpc_id in attached \
                else partial("IGW found but attachment issue", 2, 5)
        else:
            t1 += fail("IGW", 5, f"No 'igw-{name}'")

        rtbs = ec2.describe_route_tables()['RouteTables']
        rtb = find_by_tag(rtbs, 'rtb', name)
        if rtb:
            t1 += ok("Route Table exists", 3)
            has_pub = any(
                r.get('DestinationCidrBlock') == '0.0.0.0/0' and r.get('GatewayId', '').startswith('igw-')
                for r in rtb.get('Routes', []))
            t1 += ok("Route 0.0.0.0/0 → IGW", 3) if has_pub else fail("Public route", 3)
        else:
            found = False
            if vpc_id:
                for r in rtbs:
                    if r.get('VpcId') == vpc_id:
                        for route in r.get('Routes', []):
                            if route.get('DestinationCidrBlock') == '0.0.0.0/0' and route.get('GatewayId', '').startswith('igw-'):
                                t1 += partial("RTB unnamed but VPC has public route", 3, 6)
                                found = True; break
                    if found: break
            if not found:
                t1 += fail("Route Table", 3); t1 += fail("Public route", 3)
    except Exception as e:
        print(f"  {R}Error Task 1: {e}{X}")

    task_scores['Task 1: VPC          '] = t1
    print(f"\n  {B}Task 1 Subtotal: {t1} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 2 — EC2 WEB SERVER (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 2: EC2 Instance with Web Server (25 Marks)")
    t2 = 0
    try:
        sgs = ec2.describe_security_groups()['SecurityGroups']
        sg = None
        for s in sgs:
            gn = s.get('GroupName', '').lower().replace(' ', '')
            nt = tag_val(s, 'Name').lower().replace(' ', '')
            if f"web-{name}" in gn or f"web-{name}" in nt:
                sg = s; break

        if sg:
            in_vpc = vpc_id and sg.get('VpcId') == vpc_id
            t2 += ok("SG in custom VPC", 3) if in_vpc else partial("SG not in VPC", 1, 3)
            has_ssh = has_http = False
            for p in sg.get('IpPermissions', []):
                is_open = any(r.get('CidrIp') == '0.0.0.0/0' for r in p.get('IpRanges', []))
                if is_open:
                    if p.get('IpProtocol') == '-1': has_ssh = has_http = True
                    if p.get('FromPort') == 22: has_ssh = True
                    if p.get('FromPort') == 80: has_http = True
            t2 += ok("Port 22 open", 2) if has_ssh else fail("Port 22", 2)
            t2 += ok("Port 80 open", 2) if has_http else fail("Port 80", 2)
        else:
            t2 += fail("SG", 3, f"No 'web-{name}'"); t2 += fail("Port 22", 2); t2 += fail("Port 80", 2)

        reservations = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running', 'stopped', 'pending']}]
        )['Reservations']
        all_inst = [i for r in reservations for i in r['Instances']]
        inst = find_by_tag(all_inst, 'ec2', name)

        if inst:
            t2 += ok(f"EC2: {inst['InstanceId']}", 3)
            itype = inst.get('InstanceType', '')
            if itype == 't3.micro':
                t2 += ok("Type: t3.micro", 2)
            elif itype in ('t2.micro', 't3.small', 't3.nano'):
                t2 += partial("Instance type close", 1, 2, f"Found: {itype}")
            else:
                t2 += fail("Type: t3.micro", 2, f"Found: {itype}")
            inst_vpc = inst.get('VpcId', '')
            t2 += ok("In custom VPC", 3) if vpc_id and inst_vpc == vpc_id else fail("In custom VPC", 3)
            iam = inst.get('IamInstanceProfile', {}).get('Arn', '')
            t2 += ok("LabInstanceProfile", 2) if 'LabInstanceProfile' in iam else fail("LabInstanceProfile", 2)

            try:
                ud = ec2.describe_instance_attribute(InstanceId=inst['InstanceId'], Attribute='userData')
                t2 += ok("User Data configured", 3) if ud.get('UserData', {}).get('Value', '') else fail("User Data", 3)
            except:
                t2 += fail("User Data", 3)

            pub_ip = inst.get('PublicIpAddress', '')
            state = inst.get('State', {}).get('Name', '')
            if pub_ip and state == 'running':
                print(f"    {Y}Testing http://{pub_ip} ...{X}")
                try:
                    with urllib.request.urlopen(f"http://{pub_ip}", timeout=10, context=ssl_ctx) as resp:
                        html = resp.read().decode('utf-8', errors='ignore')
                        cl = html.lower().replace(' ', '')
                        if name in cl and sid in html.lower():
                            t2 += ok("Web page: Name AND ID", 5)
                        elif name in cl:
                            t2 += partial("Name found, ID missing", 4, 5)
                        elif sid in html.lower():
                            t2 += partial("ID found, name missing", 2, 5)
                        else:
                            t2 += partial("Page loads, content missing", 1, 5)
                except Exception as e:
                    t2 += fail("Web page", 5, str(e)[:80])
            else:
                t2 += fail("Web page", 5, f"State={state}, IP={pub_ip or 'none'}")
        else:
            t2 += fail("EC2", 3, f"No 'ec2-{name}'")
            for d, p in [("Type", 2), ("VPC", 3), ("LabIP", 2), ("UserData", 3), ("Web", 5)]: t2 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Task 2: {e}{X}")

    task_scores['Task 2: EC2 Web      '] = t2
    print(f"\n  {B}Task 2 Subtotal: {t2} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 3 — S3 STATIC WEBSITE (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 3: S3 Static Website (25 Marks)")
    t3 = 0
    try:
        buckets = s3.list_buckets()['Buckets']
        target_b = next((b['Name'] for b in buckets if f"s3-{name}" in b['Name']), None)

        if target_b:
            t3 += ok(f"Bucket: {target_b}", 3)
            try:
                s3.get_bucket_website(Bucket=target_b)
                t3 += ok("Static hosting enabled", 5)
            except:
                t3 += fail("Static hosting", 5)

            try:
                objs = s3.list_objects_v2(Bucket=target_b)
                files = [o['Key'] for o in objs.get('Contents', [])]
                t3 += ok("index.html uploaded", 3) if 'index.html' in files else fail("index.html", 3)
                t3 += ok("error.html uploaded", 2) if 'error.html' in files else fail("error.html", 2)
            except:
                t3 += fail("index.html", 3); t3 += fail("error.html", 2)

            try:
                pol = s3.get_bucket_policy(Bucket=target_b)
                pol_str = pol['Policy']
                if "Allow" in pol_str:
                    t3 += ok("Bucket policy (public)", 5)
                else:
                    t3 += partial("Policy exists, not public-read", 2, 5)
            except:
                t3 += fail("Bucket policy", 5)

            s3_url = f"http://{target_b}.s3-website-{region}.amazonaws.com"
            print(f"    {Y}Testing: {s3_url}{X}")
            try:
                with urllib.request.urlopen(s3_url, timeout=10, context=ssl_ctx) as resp:
                    html = resp.read().decode('utf-8', errors='ignore').lower().replace(' ', '')
                    t3 += ok("Website shows student name", 7) if name in html \
                        else partial("Website loads, name missing", 4, 7)
            except Exception as e:
                t3 += fail("Website accessible", 7, str(e)[:80])
        else:
            t3 += fail("Bucket", 3, f"No 's3-{name}'")
            for d, p in [("Hosting", 5), ("index", 3), ("error", 2), ("Policy", 5), ("Website", 7)]: t3 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Task 3: {e}{X}")

    task_scores['Task 3: S3 Website   '] = t3
    print(f"\n  {B}Task 3 Subtotal: {t3} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 4 — RDS DATABASE (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 4: RDS Database (25 Marks)")
    t4 = 0
    try:
        dbs = rds_client.describe_db_instances()['DBInstances']
        target_rds = next((d for d in dbs if f"rds-{name}" in d['DBInstanceIdentifier'].lower().replace(' ', '')), None)

        if target_rds:
            t4 += ok(f"RDS: {target_rds['DBInstanceIdentifier']}", 3)
            engine = target_rds.get('Engine', '')
            t4 += ok("Engine: MySQL", 3) if 'mysql' in engine.lower() else fail("Engine MySQL", 3, f"Found: {engine}")
            ic = target_rds.get('DBInstanceClass', '')
            if ic == 'db.t3.micro':
                t4 += ok("Class: db.t3.micro", 3)
            elif ic in ('db.t2.micro', 'db.t3.small'):
                t4 += partial("RDS class close", 2, 3, f"Found: {ic}")
            else:
                t4 += fail("Class db.t3.micro", 3, f"Found: {ic}")
            storage = target_rds.get('AllocatedStorage', 0)
            t4 += ok("Storage: 20 GB", 2) if storage == 20 else fail("Storage 20GB", 2, f"Found: {storage}")
            dbname = target_rds.get('DBName', '')
            t4 += ok("DB name: studentdb", 4) if dbname == 'studentdb' else fail("DB name: studentdb", 4, f"Found: '{dbname}'")

            vpc_sgs = target_rds.get('VpcSecurityGroups', [])
            has_3306 = False
            if vpc_sgs:
                sg_id = vpc_sgs[0]['VpcSecurityGroupId']
                sg_resp = ec2.describe_security_groups(GroupIds=[sg_id])
                for p in sg_resp['SecurityGroups'][0]['IpPermissions']:
                    if p.get('FromPort') == 3306 or p.get('IpProtocol') == '-1':
                        has_3306 = True; break
            t4 += ok("SG port 3306 open", 5) if has_3306 else fail("SG 3306", 5)

            pub = target_rds.get('PubliclyAccessible', True)
            t4 += ok("Not publicly accessible", 5) if not pub else fail("Not public", 5)
        else:
            t4 += fail("RDS instance", 3, f"No 'rds-{name}'")
            for d, p in [("Engine", 3), ("Class", 3), ("Storage", 2), ("DB name", 4), ("SG", 5), ("Not public", 5)]:
                t4 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Task 4: {e}{X}")

    task_scores['Task 4: RDS          '] = t4
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

if __name__ == "__main__":
    main()
