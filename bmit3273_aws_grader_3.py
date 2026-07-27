#!/usr/bin/env python3
"""BMIT3273 Cloud Computing Practical Test Set 3 auto-grader.

Run inside AWS Academy Learner Lab CloudShell:
    python3 bmit3273_aws_grader_3.py

Topics: DynamoDB | S3 Security & Lifecycle | Web Tier (Launch Template) |
High Availability (ASG + ALB). All checks are read-only AWS API calls plus a
single live HTTP GET against the ALB DNS name to confirm the served page.
Total marks: 100 (4 questions x 25 marks each).
"""

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


def http_page(url, clean_name, student_id):
    """Return (name_found, id_found, message) for the ALB page."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "BMIT3273-Grader"})
        with urllib.request.urlopen(req, timeout=8, context=SSL_CTX) as r:
            raw = r.read().decode("utf-8", errors="ignore").lower()
        compact = raw.replace(" ", "").replace("\n", "")
        name_found = clean_name.replace(" ", "") in compact
        id_found = student_id.casefold() in raw
        if name_found and id_found:
            return True, True, "Name AND ID found on page"
        if name_found:
            return True, False, "Name found, ID missing"
        if id_found:
            return False, True, "ID found, name missing"
        return False, False, "Neither name nor ID found (content mismatch)"
    except Exception as exc:  # noqa: BLE001 - network/HTTP failures reported verbatim
        return False, False, f"HTTP check failed: {exc}"


def main():
    global SCORE
    banner("BMIT3273 CLOUD COMPUTING - PRACTICAL TEST SET 3")
    print(f"  {W}DynamoDB | S3 Security | Web Tier | High Availability{X}")

    raw_name = input("\n  Enter Student Full Name : ").strip()
    student_id = input("  Enter Student ID        : ").strip()
    name = "".join(raw_name.lower().split())
    if not name or not student_id:
        print(f"\n{R}Student name and ID are required.{X}")
        sys.exit(2)

    expected = {
        "ddb": f"ddb-{name}",
        "s3": f"s3-{name}",
        "lt": f"lt-{name}",
        "tg": f"tg-{name}",
        "alb": f"alb-{name}",
        "asg": f"asg-{name}",
    }

    try:
        session = boto3.session.Session()
        sts = session.client("sts")
        identity = sts.get_caller_identity()
        ddb = session.client("dynamodb")
        s3 = session.client("s3")
        ec2 = session.client("ec2")
        asg = session.client("autoscaling")
        elbv2 = session.client("elbv2")
    except (NoCredentialsError, ClientError, BotoCoreError) as exc:
        print(f"\n{R}Unable to access the Learner Lab AWS account: {exc}{X}")
        sys.exit(2)

    print(f"\n  Region  : {session.region_name}")
    print(f"  Account : {identity.get('Account', 'Unknown')}")
    print(f"  Student : {raw_name} ({student_id})")

    scores = {}
    launch_template = None

    # ------------------------------------------------------------------ Q1
    section("Question 1: Serverless Database (DynamoDB)")
    q1 = 0
    try:
        tables = ddb.list_tables().get("TableNames", [])
        target = next((t for t in tables if t.casefold() == expected["ddb"].casefold()), None)
        if target:
            q1 += grade(f"DynamoDB table exists: {expected['ddb']}", 10, True)
            desc = ddb.describe_table(TableName=target)["Table"]
            pk = next((k["AttributeName"] for k in desc.get("KeySchema", []) if k.get("KeyType") == "HASH"), None)
            q1 += grade("Partition key = student_id", 5, pk == "student_id", f"Found partition key: {pk}")
            items = ddb.scan(TableName=target, Limit=50).get("Items", [])
            has_active = any(
                (it.get("status", {}).get("S", "").casefold() == "active") for it in items
            )
            q1 += grade("Item exists with status = active", 10, has_active, "No item with status=active found")
        else:
            q1 += grade(f"DynamoDB table exists: {expected['ddb']}", 10, False)
            q1 += grade("Partition key = student_id", 5, False)
            q1 += grade("Item exists with status = active", 10, False)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 1 API error: {exc}{X}")
    scores["Question 1: DynamoDB"] = q1
    subtotal("Question 1", q1)

    # ------------------------------------------------------------------ Q2
    section("Question 2: Secure Storage & Lifecycle (S3)")
    q2 = 0
    try:
        buckets = s3.list_buckets().get("Buckets", [])
        target = next((b["Name"] for b in buckets if b["Name"].casefold().startswith(expected["s3"].casefold())), None)
        if target:
            q2 += grade(f"S3 bucket exists: {expected['s3']}", 2, True)

            try:
                tags = s3.get_bucket_tagging(Bucket=target).get("TagSet", [])
            except ClientError:
                tags = []
            q2 += grade("Tag Project = FinalAssessment", 4, tag_value(tags, "Project").casefold() == "finalassessment")

            try:
                ver = s3.get_bucket_versioning(Bucket=target).get("Status")
            except ClientError:
                ver = None
            q2 += grade("Versioning enabled", 4, ver == "Enabled", f"Versioning status: {ver}")

            try:
                rules = s3.get_bucket_lifecycle_configuration(Bucket=target).get("Rules", [])
            except ClientError:
                rules = []
            ia_ok = any(
                (t.get("StorageClass") == "STANDARD_IA")
                for rule in rules if rule.get("Status") == "Enabled"
                for t in rule.get("Transitions", [])
            )
            q2 += grade("Lifecycle rule transitions to Standard-IA", 10, ia_ok, "No enabled rule transitions to STANDARD_IA")

            try:
                s3.head_object(Bucket=target, Key="config.txt")
                file_ok = True
            except ClientError:
                listing = s3.list_objects_v2(Bucket=target).get("Contents", [])
                file_ok = any(o["Key"] == "config.txt" for o in listing)
            q2 += grade("File config.txt uploaded", 5, file_ok)
        else:
            q2 += grade(f"S3 bucket exists: {expected['s3']}", 2, False)
            q2 += grade("Tag Project = FinalAssessment", 4, False)
            q2 += grade("Versioning enabled", 4, False)
            q2 += grade("Lifecycle rule transitions to Standard-IA", 10, False)
            q2 += grade("File config.txt uploaded", 5, False)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 2 API error: {exc}{X}")
    scores["Question 2: S3"] = q2
    subtotal("Question 2", q2)

    # ------------------------------------------------------------------ Q3
    section("Question 3: Web Tier Configuration (Launch Template)")
    q3 = 0
    try:
        templates = ec2.describe_launch_templates().get("LaunchTemplates", [])
        launch_template = next(
            (lt for lt in templates if lt.get("LaunchTemplateName", "").casefold() == expected["lt"].casefold()),
            None,
        )
        if launch_template:
            version = ec2.describe_launch_template_versions(
                LaunchTemplateId=launch_template["LaunchTemplateId"], Versions=["$Latest"]
            )["LaunchTemplateVersions"][0]
            data = version.get("LaunchTemplateData", {})

            q3 += grade("Instance type = t3.small", 2, data.get("InstanceType") == "t3.small", f"Found {data.get('InstanceType')}")

            profile = data.get("IamInstanceProfile", {}) or {}
            profile_ref = f"{profile.get('Arn', '')}{profile.get('Name', '')}"
            q3 += grade("LabInstanceProfile attached", 3, profile_ref.casefold().endswith("labinstanceprofile"))

            sg_ids = list(data.get("SecurityGroupIds", []))
            http_ok = False
            if sg_ids:
                try:
                    sgs = ec2.describe_security_groups(GroupIds=sg_ids)["SecurityGroups"]
                    for sg in sgs:
                        for p in sg.get("IpPermissions", []):
                            proto = p.get("IpProtocol")
                            start, end = p.get("FromPort"), p.get("ToPort")
                            anywhere = any(r.get("CidrIp") == "0.0.0.0/0" for r in p.get("IpRanges", []))
                            if anywhere and (proto == "-1" or (proto == "tcp" and start is not None and start <= 80 <= end)):
                                http_ok = True
                except ClientError:
                    pass
            q3 += grade("Security Group allows HTTP (port 80) from anywhere", 5, http_ok)

            user_data = data.get("UserData", "")
            decoded = ""
            if user_data:
                try:
                    import base64
                    decoded = base64.b64decode(user_data).decode("utf-8", errors="ignore").casefold()
                except Exception:  # noqa: BLE001
                    decoded = ""
            q3 += grade("User Data includes Nginx logic", 5, "nginx" in decoded)
            q3 += grade("User Data includes S3 or AWS CLI logic", 5, ("aws s3" in decoded) or ("aws " in decoded) or ("s3://" in decoded) or ("s3api" in decoded))
            q3 += grade("User Data includes append/write page logic", 5, ("index.html" in decoded) and (">>" in decoded or ">" in decoded or "echo" in decoded or "cat" in decoded))
        else:
            for d, p in [("Instance type = t3.small", 2), ("LabInstanceProfile attached", 3),
                         ("Security Group allows HTTP (port 80) from anywhere", 5),
                         ("User Data includes Nginx logic", 5), ("User Data includes S3 or AWS CLI logic", 5),
                         ("User Data includes append/write page logic", 5)]:
                q3 += grade(d, p, False)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 3 API error: {exc}{X}")
    scores["Question 3: Web Tier"] = q3
    subtotal("Question 3", q3)

    # ------------------------------------------------------------------ Q4
    section("Question 4: High Availability (ASG & ALB)")
    q4 = 0
    try:
        lbs = elbv2.describe_load_balancers().get("LoadBalancers", [])
        target_alb = next((lb for lb in lbs if lb.get("LoadBalancerName", "").casefold() == expected["alb"].casefold()), None)
        q4 += grade(f"ALB exists: {expected['alb']}", 2, target_alb is not None)

        groups = asg.describe_auto_scaling_groups().get("AutoScalingGroups", [])
        target_asg = next((g for g in groups if g.get("AutoScalingGroupName", "").casefold() == expected["asg"].casefold()), None)
        cap_ok = bool(target_asg and target_asg.get("MinSize") == 2 and target_asg.get("DesiredCapacity") == 2 and target_asg.get("MaxSize") == 4)
        issue = ""
        if target_asg:
            issue = f"Found Min:{target_asg.get('MinSize')} Des:{target_asg.get('DesiredCapacity')} Max:{target_asg.get('MaxSize')}"
        q4 += grade("ASG capacity = Min 2 / Desired 2 / Max 4", 3, cap_ok, issue)

        policy_ok = False
        if target_asg:
            pols = asg.describe_policies(AutoScalingGroupName=target_asg["AutoScalingGroupName"]).get("ScalingPolicies", [])
            for pol in pols:
                cfg = pol.get("TargetTrackingConfiguration", {})
                metric = cfg.get("PredefinedMetricSpecification", {}).get("PredefinedMetricType")
                if metric == "ASGAverageCPUUtilization" and abs(float(cfg.get("TargetValue", 0)) - 60.0) < 0.01:
                    policy_ok = True
        q4 += grade("Scaling policy target CPU = 60%", 5, policy_ok)

        name_ok = id_ok = False
        if target_alb and target_alb.get("DNSName"):
            name_ok, id_ok, msg = http_page(f"http://{target_alb['DNSName']}", name, student_id)
            print(f"       {W}ALB page: {msg}{X}")
        q4 += grade("ALB DNS loads page showing student name", 5, name_ok)
        q4 += grade("ALB page also shows student ID", 10, id_ok)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 4 API error: {exc}{X}")
    scores["Question 4: HA"] = q4
    subtotal("Question 4", q4)

    # ------------------------------------------------------------------ Result
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
