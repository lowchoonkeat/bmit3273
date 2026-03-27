import boto3
import json
import urllib.request
import ssl

# ═══════════════════════════════════════════════════════════════
#  BMIT3273 CLOUD COMPUTING — PRACTICAL TEST SET 4 AUTO GRADER
#  Topics: VPC Networking | EC2 Web Server | Lambda | EBS
# ═══════════════════════════════════════════════════════════════

ssl_ctx = ssl._create_unverified_context()
SCORE = 0

# ── ANSI colours (CloudShell supports these) ──
G  = '\033[92m'   # green
R  = '\033[91m'   # red
Y  = '\033[93m'   # yellow
C  = '\033[96m'   # cyan
B  = '\033[1m'    # bold
W  = '\033[97m'   # white
X  = '\033[0m'    # reset

# ── Output helpers ──
def banner(t):
    print(f"\n{C}{B}{'═'*60}")
    print(f"  {t}")
    print(f"{'═'*60}{X}")

def section(t):
    print(f"\n{C}{'─'*60}")
    print(f"  {t}")
    print(f"{'─'*60}{X}")

def ok(d, p):
    global SCORE; SCORE += p
    print(f"  {G}[✓] +{p:2d}  {d}{X}")
    return p

def fail(d, p, r=""):
    print(f"  {R}[✗]  0/{p:<2d} {d}{X}")
    if r: print(f"       {Y}→ {r}{X}")
    return 0

def partial(d, earned, total, r=""):
    global SCORE; SCORE += earned
    if earned > 0:
        print(f"  {Y}[~] +{earned}/{total}  {d}{X}")
    else:
        print(f"  {R}[✗]  0/{total:<2d} {d}{X}")
    if r: print(f"       {Y}→ {r}{X}")
    return earned

# ── Resource helpers ──
def tag_val(resource, key):
    for t in resource.get('Tags', []):
        if t['Key'] == key:
            return t['Value']
    return ''

def find_by_tag(resources, prefix, student):
    """Find a resource whose Name tag contains '<prefix>-<student>'."""
    target = f"{prefix}-{student}"
    for r in resources:
        name = tag_val(r, 'Name').lower().replace(' ', '')
        if target in name:
            return r
    return None


def main():
    banner("BMIT3273 CLOUD COMPUTING — SET 4")
    print(f"  {W}Practical Test Auto Grader v1.0{X}")
    print(f"  {W}Topics: VPC | EC2 | Lambda | EBS{X}")

    session = boto3.session.Session()
    region = session.region_name
    print(f"\n  Region: {region}")

    raw = input(f"\n  Enter Student Name : ").strip()
    name = raw.lower().replace(" ", "")
    sid  = input(f"  Enter Student ID   : ").strip().lower()

    print(f"\n  {B}Looking for resources containing: '{name}'{X}\n")

    ec2 = boto3.client('ec2')
    lam = boto3.client('lambda')

    task_scores = {}
    vpc_id      = None
    instance_id = None

    # ══════════════════════════════════════════════════════════
    #  TASK 1 — CUSTOM VPC & NETWORKING  (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 1: Custom VPC & Networking (25 Marks)")
    t1 = 0
    try:
        # ── 1a. VPC (5) ──
        vpcs = ec2.describe_vpcs()['Vpcs']
        vpc = find_by_tag(vpcs, 'vpc', name)
        if vpc:
            vpc_id = vpc['VpcId']
            t1 += ok(f"VPC found: {tag_val(vpc,'Name')} [{vpc_id}]", 5)
            # ── 1b. CIDR (3) ──
            cidr = vpc.get('CidrBlock', '')
            if cidr == '10.0.0.0/16':
                t1 += ok("VPC CIDR: 10.0.0.0/16", 3)
            else:
                t1 += fail("VPC CIDR: 10.0.0.0/16", 3, f"Found: {cidr}")
        else:
            t1 += fail("VPC found", 5, f"No VPC with Name containing 'vpc-{name}'")
            t1 += fail("VPC CIDR", 3)

        # ── 1c. Subnet (4) ──
        subs = ec2.describe_subnets()['Subnets']
        sub  = find_by_tag(subs, 'subnet', name)
        if sub:
            in_vpc = vpc_id and sub['VpcId'] == vpc_id
            if in_vpc:
                t1 += ok(f"Subnet in VPC: {tag_val(sub,'Name')}", 4)
            else:
                t1 += partial("Subnet found but NOT in custom VPC", 2, 4)
            # ── 1d. Subnet CIDR (2) ──
            sc = sub.get('CidrBlock', '')
            if sc == '10.0.1.0/24':
                t1 += ok("Subnet CIDR: 10.0.1.0/24", 2)
            else:
                t1 += fail("Subnet CIDR: 10.0.1.0/24", 2, f"Found: {sc}")
        else:
            t1 += fail("Subnet found", 4, f"No subnet named 'subnet-{name}'")
            t1 += fail("Subnet CIDR", 2)

        # ── 1e. Internet Gateway attached (5) ──
        igws = ec2.describe_internet_gateways()['InternetGateways']
        igw  = find_by_tag(igws, 'igw', name)
        if igw:
            attached = [a['VpcId'] for a in igw.get('Attachments', [])
                        if a.get('State') == 'attached']
            if vpc_id and vpc_id in attached:
                t1 += ok(f"IGW attached to VPC: {tag_val(igw,'Name')}", 5)
            elif attached:
                t1 += partial("IGW attached to WRONG VPC", 2, 5)
            else:
                t1 += partial("IGW found but NOT attached", 2, 5, "Attach it to your VPC")
        else:
            t1 += fail("IGW found", 5, f"No IGW named 'igw-{name}'")

        # ── 1f. Route Table (3) + 1g. Public route (3) ──
        rtbs = ec2.describe_route_tables()['RouteTables']
        rtb  = find_by_tag(rtbs, 'rtb', name)
        if rtb:
            t1 += ok(f"Route Table: {tag_val(rtb,'Name')}", 3)
            has_pub = any(
                r.get('DestinationCidrBlock') == '0.0.0.0/0'
                and r.get('GatewayId', '').startswith('igw-')
                for r in rtb.get('Routes', [])
            )
            if has_pub:
                t1 += ok("Route 0.0.0.0/0 → IGW", 3)
            else:
                t1 += fail("Route 0.0.0.0/0 → IGW", 3, "No public route found")
        else:
            # Fallback: unnamed RTB in VPC with public route
            found_fb = False
            if vpc_id:
                for r in rtbs:
                    if r.get('VpcId') == vpc_id:
                        for route in r.get('Routes', []):
                            if (route.get('DestinationCidrBlock') == '0.0.0.0/0'
                                    and route.get('GatewayId', '').startswith('igw-')):
                                t1 += partial("RTB not named, but VPC has public route", 3, 6,
                                              "Name your route table 'rtb-<name>'")
                                found_fb = True
                                break
                    if found_fb:
                        break
            if not found_fb:
                t1 += fail("Route Table found", 3, f"No RTB named 'rtb-{name}'")
                t1 += fail("Route 0.0.0.0/0 → IGW", 3)

    except Exception as e:
        print(f"  {R}Error Task 1: {e}{X}")

    task_scores['Task 1: VPC & Networking'] = t1
    print(f"\n  {B}Task 1 Subtotal: {t1} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 2 — EC2 INSTANCE WITH WEB SERVER  (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 2: EC2 Instance with Web Server (25 Marks)")
    t2 = 0
    try:
        # ── 2a-c. Security Group (3+2+2 = 7) ──
        sgs = ec2.describe_security_groups()['SecurityGroups']
        sg  = None
        for s in sgs:
            gn = s.get('GroupName', '').lower().replace(' ', '')
            nt = tag_val(s, 'Name').lower().replace(' ', '')
            if f"web-{name}" in gn or f"web-{name}" in nt:
                sg = s
                break

        if sg:
            in_vpc = vpc_id and sg.get('VpcId') == vpc_id
            if in_vpc:
                t2 += ok(f"Security Group in VPC: {sg['GroupName']}", 3)
            else:
                t2 += partial("SG found but NOT in custom VPC", 1, 3)

            has_ssh = has_http = False
            for p in sg.get('IpPermissions', []):
                is_open = any(r.get('CidrIp') == '0.0.0.0/0' for r in p.get('IpRanges', []))
                if is_open:
                    if p.get('IpProtocol') == '-1':
                        has_ssh = has_http = True
                    if p.get('FromPort') == 22:
                        has_ssh = True
                    if p.get('FromPort') == 80:
                        has_http = True
            t2 += ok("SG: Port 22 (SSH) open", 2) if has_ssh else fail("SG: Port 22 (SSH)", 2)
            t2 += ok("SG: Port 80 (HTTP) open", 2) if has_http else fail("SG: Port 80 (HTTP)", 2)
        else:
            t2 += fail("Security Group found", 3, f"No SG named 'web-{name}'")
            t2 += fail("Port 22", 2)
            t2 += fail("Port 80", 2)

        # ── 2d-i. EC2 Instance (3+2+3+2+3+5 = 18) ──
        reservations = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name',
                       'Values': ['running', 'stopped', 'pending']}]
        )['Reservations']
        all_inst = [i for r in reservations for i in r['Instances']]
        inst = find_by_tag(all_inst, 'ec2', name)

        if inst:
            instance_id = inst['InstanceId']
            t2 += ok(f"EC2 Instance: {tag_val(inst,'Name')} [{instance_id}]", 3)

            itype = inst.get('InstanceType', '')
            t2 += ok("Instance Type: t3.micro", 2) if itype == 't3.micro' \
                else fail("Instance Type: t3.micro", 2, f"Found: {itype}")

            inst_vpc = inst.get('VpcId', '')
            if vpc_id and inst_vpc == vpc_id:
                t2 += ok("Instance in Custom VPC", 3)
            else:
                t2 += fail("Instance in Custom VPC", 3,
                           "In default VPC" if inst_vpc else "VPC not detected")

            iam = inst.get('IamInstanceProfile', {}).get('Arn', '')
            t2 += ok("LabInstanceProfile attached", 2) if 'LabInstanceProfile' in iam \
                else fail("LabInstanceProfile attached", 2)

            try:
                ud = ec2.describe_instance_attribute(
                    InstanceId=instance_id, Attribute='userData')
                has_ud = bool(ud.get('UserData', {}).get('Value', ''))
                t2 += ok("User Data script configured", 3) if has_ud \
                    else fail("User Data script", 3, "Empty or missing")
            except:
                t2 += fail("User Data script", 3)

            # Web page live check
            pub_ip = inst.get('PublicIpAddress', '')
            state  = inst.get('State', {}).get('Name', '')
            if pub_ip and state == 'running':
                print(f"    {Y}Testing http://{pub_ip} ...{X}")
                try:
                    with urllib.request.urlopen(
                            f"http://{pub_ip}", timeout=10, context=ssl_ctx) as resp:
                        html = resp.read().decode('utf-8', errors='ignore')
                        cl   = html.lower().replace(' ', '').replace('\n', '')
                        has_name = name in cl
                        has_id   = sid in html.lower()
                        if has_name and has_id:
                            t2 += ok("Web page: Name AND Student ID displayed", 5)
                        elif has_name:
                            t2 += partial("Web page: Name found, ID missing", 3, 5)
                        elif has_id:
                            t2 += partial("Web page: ID found, Name missing", 3, 5)
                        else:
                            t2 += fail("Web page content", 5,
                                       "Page loads but name/ID not found")
                except Exception as e:
                    t2 += fail("Web page accessible", 5, str(e)[:80])
            elif state != 'running':
                t2 += fail("Web page", 5, f"Instance state: {state}")
            else:
                t2 += fail("Web page", 5, "No public IP — enable auto-assign or use Elastic IP")
        else:
            t2 += fail("EC2 Instance found", 3, f"No instance named 'ec2-{name}'")
            for d, p in [("Instance Type", 2), ("In Custom VPC", 3),
                         ("LabInstanceProfile", 2), ("User Data", 3), ("Web page", 5)]:
                t2 += fail(d, p)

    except Exception as e:
        print(f"  {R}Error Task 2: {e}{X}")

    task_scores['Task 2: EC2 Web Server '] = t2
    print(f"\n  {B}Task 2 Subtotal: {t2} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 3 — LAMBDA FUNCTION  (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 3: Lambda Function (25 Marks)")
    t3 = 0
    try:
        fname = f"lambda-{name}"
        try:
            func = lam.get_function(FunctionName=fname)
            cfg  = func['Configuration']
            t3 += ok(f"Lambda Function: {fname}", 5)

            rt = cfg.get('Runtime', '')
            t3 += ok(f"Runtime: {rt}", 3) if rt.startswith('python3') \
                else fail("Runtime: Python 3.x", 3, f"Found: {rt}")

            role = cfg.get('Role', '')
            t3 += ok("Execution Role: LabRole", 3) if 'LabRole' in role \
                else fail("Execution Role: LabRole", 3,
                          f"Found: {role.split('/')[-1]}")

            env = cfg.get('Environment', {}).get('Variables', {})
            t3 += ok(f"Env STUDENT_NAME = '{env.get('STUDENT_NAME','')}'", 3) \
                if 'STUDENT_NAME' in env else fail("Env var STUDENT_NAME", 3)
            t3 += ok(f"Env STUDENT_ID = '{env.get('STUDENT_ID','')}'", 3) \
                if 'STUDENT_ID' in env else fail("Env var STUDENT_ID", 3)

            # Invoke
            print(f"    {Y}Invoking {fname} ...{X}")
            try:
                inv = lam.invoke(FunctionName=fname,
                                 InvocationType='RequestResponse')
                if inv.get('StatusCode') == 200 and not inv.get('FunctionError'):
                    t3 += ok("Invocation successful (HTTP 200)", 3)
                    payload = inv['Payload'].read().decode('utf-8')
                    pc = payload.lower().replace(' ', '')
                    t3 += ok("Response contains student name", 3) \
                        if name in pc else fail("Response: name", 3,
                                                "Name not in output")
                    t3 += ok("Response contains student ID", 2) \
                        if sid in payload.lower() else fail("Response: ID", 2,
                                                            "ID not in output")
                else:
                    err = inv.get('FunctionError', 'Unknown')
                    t3 += fail("Invocation", 3, f"FunctionError: {err}")
                    t3 += fail("Response: name", 3)
                    t3 += fail("Response: ID", 2)
            except Exception as e:
                t3 += fail("Invocation", 3, str(e)[:80])
                t3 += fail("Response: name", 3)
                t3 += fail("Response: ID", 2)

        except lam.exceptions.ResourceNotFoundException:
            t3 += fail("Lambda Function found", 5, f"No function '{fname}'")
            for d, p in [("Runtime", 3), ("LabRole", 3), ("Env STUDENT_NAME", 3),
                         ("Env STUDENT_ID", 3), ("Invocation", 3),
                         ("Response: name", 3), ("Response: ID", 2)]:
                t3 += fail(d, p)

        except Exception as e:
            t3 += fail("Lambda Function", 5, str(e)[:80])

    except Exception as e:
        print(f"  {R}Error Task 3: {e}{X}")

    task_scores['Task 3: Lambda Function'] = t3
    print(f"\n  {B}Task 3 Subtotal: {t3} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  TASK 4 — EBS VOLUME & SNAPSHOT  (25 MARKS)
    # ══════════════════════════════════════════════════════════
    section("Task 4: EBS Volume & Snapshot (25 Marks)")
    t4 = 0
    vol_id = None
    try:
        # ── 4a. Volume (5) ──
        vols = ec2.describe_volumes()['Volumes']
        vol  = find_by_tag(vols, 'ebs', name)
        if vol:
            vol_id = vol['VolumeId']
            t4 += ok(f"EBS Volume: {tag_val(vol,'Name')} [{vol_id}]", 5)

            # ── 4b. Type gp3 (3) ──
            vt = vol.get('VolumeType', '')
            if vt == 'gp3':
                t4 += ok("Volume Type: gp3", 3)
            elif vt == 'gp2':
                t4 += partial("Volume Type gp2 (expected gp3)", 1, 3)
            else:
                t4 += fail("Volume Type: gp3", 3, f"Found: {vt}")

            # ── 4c. Size 10 GB (3) ──
            vs = vol.get('Size', 0)
            t4 += ok("Volume Size: 10 GB", 3) if vs == 10 \
                else fail("Volume Size: 10 GB", 3, f"Found: {vs} GB")

            # ── 4d. Attached (4) ──
            att = vol.get('Attachments', [])
            if att and att[0].get('State') in ('attached', 'attaching'):
                ai = att[0].get('InstanceId', '')
                if instance_id and ai == instance_id:
                    t4 += ok(f"Volume attached to ec2-{name}", 4)
                elif instance_id:
                    t4 += partial("Attached to a different instance", 2, 4)
                else:
                    t4 += ok("Volume attached to an instance", 4)
            else:
                t4 += fail("Volume attached to EC2", 4, "Not attached")

            # ── 4e. Tag Project=BMIT3273 (3) ──
            proj = tag_val(vol, 'Project')
            if proj.upper() == 'BMIT3273':
                t4 += ok("Volume Tag: Project = BMIT3273", 3)
            elif proj:
                t4 += partial(f"Volume Tag: Project = {proj}", 1, 3,
                              "Expected 'BMIT3273'")
            else:
                t4 += fail("Volume Tag: Project = BMIT3273", 3, "Tag not found")
        else:
            t4 += fail("EBS Volume found", 5, f"No volume named 'ebs-{name}'")
            for d, p in [("Volume Type", 3), ("Volume Size", 3),
                         ("Attached", 4), ("Volume Tag", 3)]:
                t4 += fail(d, p)

        # ── 4f. Snapshot (4) ──
        snaps = ec2.describe_snapshots(OwnerIds=['self'])['Snapshots']
        snap  = find_by_tag(snaps, 'snap', name)

        # Fallback: unnamed snapshot from the correct volume
        if not snap and vol_id:
            for s in snaps:
                if s.get('VolumeId') == vol_id:
                    snap = s
                    break

        if snap:
            t4 += ok(f"Snapshot: {tag_val(snap,'Name') or snap['SnapshotId']}", 4)
            # ── 4g. Snapshot tag (3) ──
            sp = tag_val(snap, 'Project')
            if sp.upper() == 'BMIT3273':
                t4 += ok("Snapshot Tag: Project = BMIT3273", 3)
            elif sp:
                t4 += partial(f"Snapshot Tag: Project = {sp}", 1, 3,
                              "Expected 'BMIT3273'")
            else:
                t4 += fail("Snapshot Tag: Project = BMIT3273", 3, "Tag not found")
        else:
            t4 += fail("Snapshot found", 4,
                        f"No snapshot named 'snap-{name}' or from volume")
            t4 += fail("Snapshot Tag", 3)

    except Exception as e:
        print(f"  {R}Error Task 4: {e}{X}")

    task_scores['Task 4: EBS & Snapshot '] = t4
    print(f"\n  {B}Task 4 Subtotal: {t4} / 25{X}")

    # ══════════════════════════════════════════════════════════
    #  FINAL RESULT
    # ══════════════════════════════════════════════════════════
    banner("FINAL RESULT")
    for task, score in task_scores.items():
        filled = int(score * 10 / 25)
        empty  = 10 - filled
        bar    = '█' * filled + '░' * empty
        print(f"  {task:32s} {bar} {score:2d}/25")

    print(f"\n  {'─'*44}")
    if   SCORE >= 80: color = G
    elif SCORE >= 50: color = Y
    else:             color = R
    print(f"  {color}{B}  TOTAL SCORE :  {SCORE} / 100{X}")
    print(f"  {'─'*44}")

    if SCORE == 100:
        print(f"\n  {G}{B}  ★  PERFECT SCORE — Excellent work!  ★{X}")
    elif SCORE >= 80:
        print(f"\n  {G}  Great job! Review any missed items above.{X}")
    elif SCORE >= 50:
        print(f"\n  {Y}  Decent progress. Check failed items and retry.{X}")
    else:
        print(f"\n  {R}  Needs improvement. Re-read instructions carefully.{X}")
    print()


if __name__ == "__main__":
    main()
