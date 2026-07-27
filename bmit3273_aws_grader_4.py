#!/usr/bin/env python3
"""BMIT3273 Cloud Computing Practical Test Set 4 auto-grader.

Run inside AWS Academy Learner Lab CloudShell:
    python3 bmit3273_aws_grader_4.py

Topics: Custom VPC & Networking | EC2 Web Server | Lambda | EBS Volume & Snapshot.
All checks are read-only AWS API calls, plus one live HTTP GET against the EC2
public IP and one Lambda test invocation. Total marks: 100 (4 x 25).
"""

import base64
import json
import ssl
import sys
import urllib.request

import boto3
from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError

SCORE = 0

G = "\033[92m"
R = "\033[91m"
Y = "\033[93m"
C = "\033[96m"
B = "\033[1m"
W = "\033[97m"
X = "\033[0m"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SSL_CTX = ssl._create_unverified_context()


def banner(title):
    print(f"\n{C}{B}{'=' * 68}\n  {title}\n{'=' * 68}{X}")


def section(title):
    print(f"\n{C}{'-' * 68}\n  {title}\n{'-' * 68}{X}")


def grade(desc, points, condition, issue=""):
    """Award full points when condition is true, else zero. Returns points won."""
    global SCORE
    if condition:
        SCORE += points
        print(f"  {G}[OK] +{points:2d}  {desc}{X}")
        return points
    print(f"  {R}[X]  0/{points:<2d} {desc}{X}")
    if issue:
        print(f"       {Y}-> {issue}{X}")
    return 0


def subtotal(label, score):
    print(f"\n  {B}{label} Subtotal: {score} / 25{X}")


def tag_value(tags, key):
    for t in tags or []:
        if t.get("Key", "").casefold() == key.casefold():
            return t.get("Value", "")
    return ""


def exact_name(resource, expected):
    return tag_value(resource.get("Tags", []), "Name").strip().casefold() == expected.casefold()


def find_named(resources, expected):
    return next((r for r in resources if exact_name(r, expected)), None)


def port_open_anywhere(permission, port):
    proto = permission.get("IpProtocol")
    anywhere = any(r.get("CidrIp") == "0.0.0.0/0" for r in permission.get("IpRanges", []))
    if not anywhere:
        return False
    if proto == "-1":
        return True
    if proto != "tcp":
        return False
    start, end = permission.get("FromPort"), permission.get("ToPort")
    return start is not None and end is not None and start <= port <= end


def http_page(ip, clean_name, student_id):
    try:
        req = urllib.request.Request(f"http://{ip}", headers={"User-Agent": "BMIT3273-Grader"})
        with urllib.request.urlopen(req, timeout=8, context=SSL_CTX) as r:
            raw = r.read().decode("utf-8", errors="ignore").lower()
        compact = raw.replace(" ", "").replace("\n", "")
        return (clean_name.replace(" ", "") in compact) and (student_id.casefold() in raw)
    except Exception:  # noqa: BLE001
        return False


def main():
    global SCORE
    banner("BMIT3273 CLOUD COMPUTING - PRACTICAL TEST SET 4")
    print(f"  {W}Custom VPC | EC2 Web Server | Lambda | EBS{X}")

    raw_name = input("\n  Enter Student Full Name : ").strip()
    student_id = input("  Enter Student ID        : ").strip()
    name = "".join(raw_name.lower().split())
    if not name or not student_id:
        print(f"\n{R}Student name and ID are required.{X}")
        sys.exit(2)

    expected = {
        "vpc": f"vpc-{name}",
        "subnet": f"subnet-{name}",
        "igw": f"igw-{name}",
        "rtb": f"rtb-{name}",
        "web_sg": f"web-{name}",
        "ec2": f"ec2-{name}",
        "lambda": f"lambda-{name}",
        "ebs": f"ebs-{name}",
        "snap": f"snap-{name}",
    }

    try:
        session = boto3.session.Session()
        sts = session.client("sts")
        identity = sts.get_caller_identity()
        ec2 = session.client("ec2")
        lam = session.client("lambda")
    except (NoCredentialsError, ClientError, BotoCoreError) as exc:
        print(f"\n{R}Unable to access the Learner Lab AWS account: {exc}{X}")
        sys.exit(2)

    print(f"\n  Region  : {session.region_name}")
    print(f"  Account : {identity.get('Account', 'Unknown')}")
    print(f"  Student : {raw_name} ({student_id})")

    scores = {}
    target_vpc = target_subnet = target_igw = target_web_sg = target_instance = None

    # -------------------------------------------------------------- Q1 VPC
    section("Question 1: Custom VPC & Networking")
    q1 = 0
    try:
        target_vpc = find_named(ec2.describe_vpcs()["Vpcs"], expected["vpc"])
        if target_vpc:
            q1 += grade(f"VPC exists: {expected['vpc']}", 5, True)
            q1 += grade("VPC CIDR = 10.0.0.0/16", 3, target_vpc.get("CidrBlock") == "10.0.0.0/16", f"Found {target_vpc.get('CidrBlock')}")
        else:
            q1 += grade(f"VPC exists: {expected['vpc']}", 5, False)
            q1 += grade("VPC CIDR = 10.0.0.0/16", 3, False)

        target_subnet = find_named(ec2.describe_subnets()["Subnets"], expected["subnet"])
        in_vpc = bool(target_subnet and target_vpc and target_subnet.get("VpcId") == target_vpc.get("VpcId"))
        q1 += grade(f"Subnet {expected['subnet']} in correct VPC", 4, in_vpc)
        q1 += grade("Subnet CIDR = 10.0.1.0/24", 2, bool(target_subnet) and target_subnet.get("CidrBlock") == "10.0.1.0/24", f"Found {target_subnet.get('CidrBlock') if target_subnet else 'none'}")

        target_igw = find_named(ec2.describe_internet_gateways()["InternetGateways"], expected["igw"])
        igw_attached = bool(target_igw and target_vpc and any(a.get("VpcId") == target_vpc.get("VpcId") for a in target_igw.get("Attachments", [])))
        q1 += grade(f"IGW {expected['igw']} attached to VPC", 5, igw_attached)

        target_rtb = find_named(ec2.describe_route_tables()["RouteTables"], expected["rtb"])
        q1 += grade(f"Route Table {expected['rtb']} exists", 3, target_rtb is not None)
        route_ok = bool(target_rtb and target_igw and any(
            rt.get("DestinationCidrBlock") == "0.0.0.0/0" and rt.get("GatewayId") == target_igw.get("InternetGatewayId")
            for rt in target_rtb.get("Routes", [])
        ))
        q1 += grade("Route 0.0.0.0/0 -> IGW configured", 3, route_ok)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 1 API error: {exc}{X}")
    scores["Question 1: VPC"] = q1
    subtotal("Question 1", q1)

    # -------------------------------------------------------------- Q2 EC2
    section("Question 2: EC2 Instance with Web Server")
    q2 = 0
    try:
        groups = ec2.describe_security_groups()["SecurityGroups"]
        target_web_sg = next((sg for sg in groups if sg.get("GroupName", "").casefold() == expected["web_sg"].casefold()), None)
        sg_in_vpc = bool(target_web_sg and target_vpc and target_web_sg.get("VpcId") == target_vpc.get("VpcId"))
        q2 += grade(f"Security group {expected['web_sg']} in custom VPC", 3, sg_in_vpc)
        ssh_ok = bool(target_web_sg and any(port_open_anywhere(p, 22) for p in target_web_sg.get("IpPermissions", [])))
        http_ok = bool(target_web_sg and any(port_open_anywhere(p, 80) for p in target_web_sg.get("IpPermissions", [])))
        q2 += grade("SG: Port 22 (SSH) open from anywhere", 2, ssh_ok)
        q2 += grade("SG: Port 80 (HTTP) open from anywhere", 2, http_ok)

        reservations = ec2.describe_instances(Filters=[{"Name": "instance-state-name", "Values": ["pending", "running"]}])["Reservations"]
        instances = [i for r in reservations for i in r.get("Instances", [])]
        target_instance = find_named(instances, expected["ec2"])
        if target_instance:
            q2 += grade(f"EC2 exists: {expected['ec2']}", 3, True)
            q2 += grade("Instance type = t3.micro", 2, target_instance.get("InstanceType") == "t3.micro", f"Found {target_instance.get('InstanceType')}")
            q2 += grade("Instance in custom VPC", 3, bool(target_vpc) and target_instance.get("VpcId") == target_vpc.get("VpcId"))
            profile = target_instance.get("IamInstanceProfile", {}).get("Arn", "")
            q2 += grade("LabInstanceProfile attached", 2, profile.endswith("/LabInstanceProfile"))
            try:
                ud = ec2.describe_instance_attribute(InstanceId=target_instance["InstanceId"], Attribute="userData").get("UserData", {}).get("Value", "")
                decoded = base64.b64decode(ud).decode("utf-8", errors="ignore").casefold() if ud else ""
                ud_ok = any(tok in decoded for tok in ("httpd", "apache", "nginx"))
            except (ClientError, ValueError):
                ud_ok = False
            q2 += grade("User Data script configured (web server)", 3, ud_ok)

            ip = target_instance.get("PublicIpAddress")
            page_ok = http_page(ip, name, student_id) if ip else False
            q2 += grade("Web page shows student name & ID", 5, page_ok, "Page not reachable or name/ID missing")
        else:
            for d, p in [(f"EC2 exists: {expected['ec2']}", 3), ("Instance type = t3.micro", 2),
                         ("Instance in custom VPC", 3), ("LabInstanceProfile attached", 2),
                         ("User Data script configured (web server)", 3), ("Web page shows student name & ID", 5)]:
                q2 += grade(d, p, False)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 2 API error: {exc}{X}")
    scores["Question 2: EC2"] = q2
    subtotal("Question 2", q2)

    # -------------------------------------------------------------- Q3 Lambda
    section("Question 3: Lambda Function")
    q3 = 0
    try:
        try:
            fn = lam.get_function(FunctionName=expected["lambda"])
            config = fn["Configuration"]
        except ClientError:
            config = None

        if config:
            q3 += grade(f"Lambda function exists: {expected['lambda']}", 5, True)
            q3 += grade("Runtime = Python 3.x", 3, str(config.get("Runtime", "")).startswith("python3"), f"Found {config.get('Runtime')}")
            q3 += grade("Execution role = LabRole", 3, config.get("Role", "").endswith("/LabRole"))
            env = config.get("Environment", {}).get("Variables", {})
            q3 += grade("Env var STUDENT_NAME set", 3, "STUDENT_NAME" in env)
            q3 += grade("Env var STUDENT_ID set", 3, "STUDENT_ID" in env)

            invoke_ok = name_ok = id_ok = False
            try:
                resp = lam.invoke(FunctionName=expected["lambda"], InvocationType="RequestResponse")
                status = resp.get("StatusCode")
                payload = resp["Payload"].read().decode("utf-8", errors="ignore")
                body = payload.casefold()
                # statusCode may be inside the JSON body too
                invoke_ok = (status == 200) and ("errormessage" not in body)
                try:
                    parsed = json.loads(payload)
                    inner = json.dumps(parsed).casefold()
                except Exception:  # noqa: BLE001
                    inner = body
                haystack = (body + inner)
                name_ok = name.replace(" ", "") in haystack.replace(" ", "")
                id_ok = student_id.casefold() in haystack
            except (ClientError, BotoCoreError, KeyError) as exc:
                print(f"       {Y}-> Lambda invoke issue: {exc}{X}")
            q3 += grade("Invocation succeeds (HTTP 200)", 3, invoke_ok)
            q3 += grade("Response contains student name", 3, name_ok)
            q3 += grade("Response contains student ID", 2, id_ok)
        else:
            for d, p in [(f"Lambda function exists: {expected['lambda']}", 5), ("Runtime = Python 3.x", 3),
                         ("Execution role = LabRole", 3), ("Env var STUDENT_NAME set", 3),
                         ("Env var STUDENT_ID set", 3), ("Invocation succeeds (HTTP 200)", 3),
                         ("Response contains student name", 3), ("Response contains student ID", 2)]:
                q3 += grade(d, p, False)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 3 API error: {exc}{X}")
    scores["Question 3: Lambda"] = q3
    subtotal("Question 3", q3)

    # -------------------------------------------------------------- Q4 EBS
    section("Question 4: EBS Volume & Snapshot")
    q4 = 0
    try:
        target_volume = find_named(ec2.describe_volumes()["Volumes"], expected["ebs"])
        if target_volume:
            q4 += grade(f"EBS volume exists: {expected['ebs']}", 5, True)
            q4 += grade("Volume type = gp3", 3, target_volume.get("VolumeType") == "gp3", f"Found {target_volume.get('VolumeType')}")
            q4 += grade("Volume size = 10 GiB", 3, target_volume.get("Size") == 10, f"Found {target_volume.get('Size')} GiB")
            attached = bool(target_instance and any(a.get("InstanceId") == target_instance.get("InstanceId") and a.get("State") in {"attaching", "attached"} for a in target_volume.get("Attachments", [])))
            q4 += grade(f"Volume attached to {expected['ec2']}", 4, attached)
            q4 += grade("Volume tag Project = BMIT3273", 3, tag_value(target_volume.get("Tags", []), "Project").casefold() == "bmit3273")
        else:
            for d, p in [(f"EBS volume exists: {expected['ebs']}", 5), ("Volume type = gp3", 3),
                         ("Volume size = 10 GiB", 3), (f"Volume attached to {expected['ec2']}", 4),
                         ("Volume tag Project = BMIT3273", 3)]:
                q4 += grade(d, p, False)

        snapshots = ec2.describe_snapshots(OwnerIds=["self"])["Snapshots"]
        target_snap = find_named(snapshots, expected["snap"])
        q4 += grade(f"Snapshot exists: {expected['snap']}", 4, target_snap is not None)
        q4 += grade("Snapshot tag Project = BMIT3273", 3, bool(target_snap) and tag_value(target_snap.get("Tags", []), "Project").casefold() == "bmit3273")
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 4 API error: {exc}{X}")
    scores["Question 4: EBS"] = q4
    subtotal("Question 4", q4)

    # -------------------------------------------------------------- Result
    banner("FINAL RESULT")
    for label, score in scores.items():
        filled = round(score * 10 / 25)
        print(f"  {label:<22} [{'#' * filled}{'-' * (10 - filled)}] {score:2d}/25")
    print(f"\n  {'-' * 50}")
    colour = G if SCORE >= 80 else Y if SCORE >= 50 else R
    print(f"  {colour}{B}TOTAL SCORE: {SCORE} / 100{X}")
    print(f"  {'-' * 50}\n")


if __name__ == "__main__":
    main()
