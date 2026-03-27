import boto3
import json
import urllib.request
import ssl
import base64
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# ═══════════════════════════════════════════════════════════════
#  BMIT3273 CLOUD COMPUTING — PRACTICAL TEST SET 2 AUTO GRADER
#  Topics: VPC & Networking | EC2 Web Server | EFS | EBS
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


def main():
    banner("BMIT3273 CLOUD COMPUTING — SET 2")
    print(f"  {W}Topics: VPC | EC2 Web Server | EFS | EBS{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()
    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2 = boto3.client('ec2')
    efs = boto3.client('efs')
    task_scores = {}

    # ══════════════════════════════════════════════════════════
    #  TASK 1 — CUSTOM VPC & NETWORKING (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 1: Custom VPC & Networking (25 Marks)")
    t1 = 0
    target_vpc_id = None
    try:
        vpcs = ec2.describe_vpcs(Filters=[{'Name': 'tag:Name', 'Values': ['*']}])['Vpcs']
        target_vpc = None
        for v in vpcs:
            n = tag_val(v.get('Tags', []), 'Name').lower().replace(' ', '')
            if f"vpc-{name}" in n:
                target_vpc = v; break

        if target_vpc:
            target_vpc_id = target_vpc['VpcId']
            t1 += ok(f"VPC: {tag_val(target_vpc.get('Tags', []), 'Name')}", 5)

            cidr = target_vpc.get('CidrBlock', '')
            if cidr == '10.0.0.0/16':
                t1 += ok("CIDR: 10.0.0.0/16", 3)
            elif cidr.startswith('10.'):
                t1 += partial("CIDR", 1, 3, f"Found: {cidr}")
            else:
                t1 += fail("CIDR 10.0.0.0/16", 3, f"Found: {cidr}")
        else:
            t1 += fail("VPC", 5, f"No 'vpc-{name}'")
            t1 += fail("CIDR", 3)

        # Subnet
        subnets = ec2.describe_subnets(
            Filters=[{'Name': 'tag:Name', 'Values': ['*']}]
        )['Subnets']
        target_sub = None
        for s in subnets:
            n = tag_val(s.get('Tags', []), 'Name').lower().replace(' ', '')
            if f"subnet-{name}" in n:
                target_sub = s; break

        if target_sub:
            in_vpc = (target_sub['VpcId'] == target_vpc_id) if target_vpc_id else False
            if in_vpc:
                t1 += ok("Subnet in correct VPC", 4)
            else:
                t1 += partial("Subnet exists", 2, 4, "Wrong VPC")

            scidr = target_sub.get('CidrBlock', '')
            t1 += ok("Subnet CIDR: 10.0.1.0/24", 2) if scidr == '10.0.1.0/24' \
                else fail("Subnet CIDR", 2, f"Found: {scidr}")
        else:
            t1 += fail("Subnet", 4, f"No 'subnet-{name}'")
            t1 += fail("Subnet CIDR", 2)

        # Internet Gateway
        igws = ec2.describe_internet_gateways(
            Filters=[{'Name': 'tag:Name', 'Values': ['*']}]
        )['InternetGateways']
        target_igw = None
        for ig in igws:
            n = tag_val(ig.get('Tags', []), 'Name').lower().replace(' ', '')
            if f"igw-{name}" in n:
                target_igw = ig; break

        if target_igw:
            attachments = target_igw.get('Attachments', [])
            attached_to_vpc = any(a['VpcId'] == target_vpc_id for a in attachments) if target_vpc_id else False
            if attached_to_vpc:
                t1 += ok("IGW attached to VPC", 5)
            elif attachments:
                t1 += partial("IGW attached", 3, 5, "Attached to different VPC")
            else:
                t1 += partial("IGW exists", 2, 5, "Not attached")
        else:
            t1 += fail("IGW", 5, f"No 'igw-{name}'")

        # Route Table
        rts = ec2.describe_route_tables(
            Filters=[{'Name': 'tag:Name', 'Values': ['*']}]
        )['RouteTables']
        target_rt = None
        for rt in rts:
            n = tag_val(rt.get('Tags', []), 'Name').lower().replace(' ', '')
            if f"rtb-{name}" in n:
                target_rt = rt; break

        if target_rt:
            t1 += ok(f"Route Table: {tag_val(target_rt.get('Tags', []), 'Name')}", 3)
            routes = target_rt.get('Routes', [])
            has_igw_route = any(
                r.get('DestinationCidrBlock') == '0.0.0.0/0' and 'igw-' in r.get('GatewayId', '')
                for r in routes)
            t1 += ok("Route 0.0.0.0/0 → IGW", 3) if has_igw_route \
                else fail("Route to IGW", 3)
        else:
            t1 += fail("Route Table", 3, f"No 'rtb-{name}'")
            t1 += fail("Route", 3)
    except Exception as e:
        print(f"  {R}Error Task 1: {e}{X}")

    task_scores['Task 1: VPC          '] = t1
    print(f"\n  {B}Task 1 Subtotal: {t1} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 2 — EC2 WITH WEB SERVER (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 2: EC2 Instance with Web Server (25 Marks)")
    t2 = 0
    target_ec2 = None
    try:
        # Security Group
        sgs = ec2.describe_security_groups()['SecurityGroups']
        target_sg = next((s for s in sgs if f"web-{name}" in s['GroupName'].lower().replace(' ', '')), None)

        if target_sg:
            sg_in_vpc = (target_sg['VpcId'] == target_vpc_id) if target_vpc_id else True
            if sg_in_vpc:
                t2 += ok(f"SG in custom VPC", 3)
            else:
                t2 += partial("SG exists", 1, 3, "Wrong VPC")

            perms = target_sg.get('IpPermissions', [])
            ports = set()
            for p in perms:
                fp, tp = p.get('FromPort', 0), p.get('ToPort', 0)
                if fp == tp: ports.add(fp)
                elif fp and tp:
                    for pp in (22, 80):
                        if fp <= pp <= tp: ports.add(pp)
            t2 += ok("SG: port 22 (SSH)", 2) if 22 in ports else fail("SG: SSH", 2)
            t2 += ok("SG: port 80 (HTTP)", 2) if 80 in ports else fail("SG: HTTP", 2)
        else:
            t2 += fail("Security Group", 3, f"No 'web-{name}'")
            t2 += fail("SSH", 2); t2 += fail("HTTP", 2)

        # EC2 Instance
        insts = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
        )['Reservations']
        for r in insts:
            for i in r['Instances']:
                n = tag_val(i.get('Tags', []), 'Name').lower().replace(' ', '')
                if f"ec2-{name}" in n:
                    target_ec2 = i; break
            if target_ec2: break

        if target_ec2:
            t2 += ok(f"EC2: {tag_val(target_ec2.get('Tags', []), 'Name')}", 3)

            itype = target_ec2.get('InstanceType', '')
            if itype == 't3.micro':
                t2 += ok("Instance type: t3.micro", 2)
            elif itype in ('t2.micro', 't3.small', 't3.nano'):
                t2 += partial("Instance type", 1, 2, f"Found: {itype}")
            else:
                t2 += fail("t3.micro", 2, f"Found: {itype}")

            inst_vpc = target_ec2.get('VpcId', '')
            if target_vpc_id and inst_vpc == target_vpc_id:
                t2 += ok("Instance in custom VPC", 3)
            elif target_vpc_id:
                t2 += fail("In custom VPC", 3, "Wrong VPC")
            else:
                t2 += fail("In custom VPC", 3, "VPC not found")

            prof = target_ec2.get('IamInstanceProfile', {}).get('Arn', '')
            t2 += ok("LabInstanceProfile", 2) if 'LabInstanceProfile' in prof \
                else fail("LabInstanceProfile", 2)

            # User Data check
            try:
                ud_resp = ec2.describe_instance_attribute(
                    InstanceId=target_ec2['InstanceId'], Attribute='userData'
                )
                ud = ud_resp.get('UserData', {}).get('Value', '')
                if ud:
                    script = base64.b64decode(ud).decode('utf-8', errors='ignore').lower()
                    has_web = 'httpd' in script or 'nginx' in script or 'apache' in script
                    if has_web:
                        t2 += ok("User Data: web server", 3)
                    else:
                        t2 += partial("User Data: script present", 1, 3, "No httpd/nginx")
                else:
                    t2 += fail("User Data", 3)
            except:
                t2 += partial("User Data: check failed", 1, 3)

            # Web page
            pub_ip = target_ec2.get('PublicIpAddress', '')
            if pub_ip:
                print(f"    {Y}Checking web page at {pub_ip}...{X}")
                try:
                    req = urllib.request.Request(f"http://{pub_ip}", headers={'User-Agent': 'BMIT3273'})
                    with urllib.request.urlopen(req, timeout=6, context=ssl_ctx) as resp:
                        body = resp.read().decode('utf-8', errors='ignore').lower().replace(' ', '')
                    if name in body and sid in body:
                        t2 += ok("Web page: name + ID", 5)
                    elif name in body:
                        t2 += partial("Web page: name found", 4, 5, "ID missing")
                    elif len(body) > 50:
                        t2 += partial("Web page: loads", 2, 5, "Name & ID missing")
                    else:
                        t2 += fail("Web page content", 5)
                except:
                    t2 += fail("Web page", 5, "Cannot reach HTTP")
            else:
                t2 += fail("Web page", 5, "No public IP")
        else:
            t2 += fail("EC2", 3, f"No running 'ec2-{name}'")
            for d, p in [("Type", 2), ("VPC", 3), ("Profile", 2), ("UserData", 3), ("Web page", 5)]:
                t2 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Task 2: {e}{X}")

    task_scores['Task 2: EC2 Web      '] = t2
    print(f"\n  {B}Task 2 Subtotal: {t2} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 3 — EFS FILE SYSTEM (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 3: EFS File System (25 Marks)")
    t3 = 0
    try:
        fss = efs.describe_file_systems()['FileSystems']
        target_fs = None
        for fs in fss:
            n = fs.get('Name', '').lower().replace(' ', '')
            if f"efs-{name}" in n:
                target_fs = fs; break

        if target_fs:
            fsid = target_fs['FileSystemId']
            t3 += ok(f"EFS: {target_fs.get('Name', fsid)}", 7)

            pm = target_fs.get('PerformanceMode', '')
            if pm == 'generalPurpose':
                t3 += ok("Performance: generalPurpose", 3)
            elif pm:
                t3 += partial("Performance mode", 1, 3, f"Found: {pm}")
            else:
                t3 += fail("Performance mode", 3)

            tags_resp = efs.describe_tags(FileSystemId=fsid)
            tags = tags_resp.get('Tags', [])
            proj = next((t['Value'] for t in tags if t['Key'] == 'Project'), '')
            if proj.upper() == 'BMIT3273':
                t3 += ok("Tag Project = BMIT3273", 5)
            elif proj:
                t3 += partial("Tag Project exists", 2, 5, f"Found: '{proj}'")
            else:
                t3 += fail("Tag Project", 5, "Missing")

            mts = efs.describe_mount_targets(FileSystemId=fsid)['MountTargets']
            t3 += ok(f"Mount targets: {len(mts)} AZ(s)", 10) if len(mts) > 0 \
                else fail("Mount target", 10)
        else:
            t3 += fail("EFS", 7, f"No 'efs-{name}'")
            for d, p in [("Performance", 3), ("Tag", 5), ("Mount target", 10)]:
                t3 += fail(d, p)
    except Exception as e:
        print(f"  {R}Error Task 3: {e}{X}")

    task_scores['Task 3: EFS          '] = t3
    print(f"\n  {B}Task 3 Subtotal: {t3} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 4 — EBS VOLUME & SNAPSHOT (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 4: EBS Volume & Snapshot (25 Marks)")
    t4 = 0
    try:
        vols = ec2.describe_volumes()['Volumes']
        target_v = None
        for v in vols:
            n = tag_val(v.get('Tags', []), 'Name').lower().replace(' ', '')
            if f"ebs-{name}" in n:
                target_v = v; break

        if target_v:
            t4 += ok(f"Volume: {tag_val(target_v.get('Tags', []), 'Name')}", 5)

            vt = target_v.get('VolumeType', '')
            if vt == 'gp3':
                t4 += ok("Type: gp3", 3)
            elif vt == 'gp2':
                t4 += partial("Type", 2, 3, "Found: gp2 (close)")
            else:
                t4 += fail("Type gp3", 3, f"Found: {vt}")

            sz = target_v.get('Size', 0)
            if sz == 10:
                t4 += ok("Size: 10 GiB", 3)
            elif 5 <= sz <= 20:
                t4 += partial("Size", 1, 3, f"Found: {sz} GiB")
            else:
                t4 += fail("10 GiB", 3, f"Found: {sz}")

            att = target_v.get('Attachments', [])
            if att:
                att_inst = att[0].get('InstanceId', '')
                ec2_id = target_ec2['InstanceId'] if target_ec2 else ''
                if ec2_id and att_inst == ec2_id:
                    t4 += ok("Attached to ec2-<name>", 4)
                elif att_inst:
                    t4 += partial("Attached", 2, 4, "Attached to different instance")
                else:
                    t4 += fail("Attached", 4)
            else:
                t4 += fail("Attached", 4, "Not attached")

            proj = tag_val(target_v.get('Tags', []), 'Project')
            if proj.upper() == 'BMIT3273':
                t4 += ok("Tag Project = BMIT3273", 3)
            elif proj:
                t4 += partial("Tag Project", 1, 3, f"Found: '{proj}'")
            else:
                t4 += fail("Tag Project", 3)
        else:
            t4 += fail("Volume", 5, f"No 'ebs-{name}'")
            for d, p in [("Type", 3), ("Size", 3), ("Attached", 4), ("Tag", 3)]:
                t4 += fail(d, p)

        # Snapshot
        snaps = ec2.describe_snapshots(OwnerIds=['self'])['Snapshots']
        target_s = None
        for s in snaps:
            n = tag_val(s.get('Tags', []), 'Name').lower().replace(' ', '')
            if f"snap-{name}" in n:
                target_s = s; break

        if target_s:
            t4 += ok(f"Snapshot: {tag_val(target_s.get('Tags', []), 'Name')}", 4)
            proj = tag_val(target_s.get('Tags', []), 'Project')
            if proj.upper() == 'BMIT3273':
                t4 += ok("Snap Tag Project = BMIT3273", 3)
            elif proj:
                t4 += partial("Snap Tag Project", 1, 3, f"Found: '{proj}'")
            else:
                t4 += fail("Snap Tag Project", 3)
        else:
            t4 += fail("Snapshot", 4, f"No 'snap-{name}'")
            t4 += fail("Snap Tag", 3)
    except Exception as e:
        print(f"  {R}Error Task 4: {e}{X}")

    task_scores['Task 4: EBS          '] = t4
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
