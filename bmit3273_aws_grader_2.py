#!/usr/bin/env python3
"""BMIT3273 Cloud Computing Practical Test Set 2 auto-grader.

Run inside AWS Academy Learner Lab CloudShell:
    python3 bmit3273_aws_grader_2_revised.py

The grader performs read-only AWS API checks except for optional AWS Systems
Manager Run Commands used to verify the active web service, EFS mount, and
student.txt on the EC2 instance. Those commands only inspect system state.
"""

import base64
import shlex
import ssl
import sys
import time
import urllib.request

import boto3
from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError

REGION = "us-east-1"
SCORE = 0
MANUAL_REVIEW = []

G = "\033[92m"
R = "\033[91m"
Y = "\033[93m"
C = "\033[96m"
B = "\033[1m"
W = "\033[97m"
X = "\033[0m"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def banner(title):
    print(f"\n{C}{B}{'=' * 68}\n  {title}\n{'=' * 68}{X}")


def section(title):
    print(f"\n{C}{'-' * 68}\n  {title}\n{'-' * 68}{X}")


def award(description, points):
    global SCORE
    SCORE += points
    print(f"  {G}[OK] +{points:2d}  {description}{X}")
    return points


def fail(description, points, reason=""):
    print(f"  {R}[X]  0/{points:<2d} {description}{X}")
    if reason:
        print(f"       {Y}-> {reason}{X}")
    return 0


def subtotal(label, score):
    print(f"\n  {B}{label} Subtotal: {score} / 25{X}")


def tag_value(tags, key):
    for tag in tags or []:
        if tag.get("Key", "").casefold() == key.casefold():
            return tag.get("Value", "")
    return ""


def exact_tag_name(resource, expected):
    return tag_value(resource.get("Tags", []), "Name").strip().casefold() == expected.casefold()


def all_ipv4_anywhere(permission):
    return any(item.get("CidrIp") == "0.0.0.0/0" for item in permission.get("IpRanges", []))


def permission_allows_port_from_anywhere(permission, port):
    protocol = permission.get("IpProtocol")
    if protocol == "-1":
        return all_ipv4_anywhere(permission)
    if protocol != "tcp":
        return False
    start = permission.get("FromPort")
    end = permission.get("ToPort")
    return start is not None and end is not None and start <= port <= end and all_ipv4_anywhere(permission)


def permission_allows_nfs_from_sg(permission, source_sg_id):
    if permission.get("IpProtocol") not in ("tcp", "-1"):
        return False
    if permission.get("IpProtocol") == "tcp":
        start = permission.get("FromPort")
        end = permission.get("ToPort")
        if start is None or end is None or not (start <= 2049 <= end):
            return False
    return any(pair.get("GroupId") == source_sg_id for pair in permission.get("UserIdGroupPairs", []))


def find_named(resources, expected):
    return next((resource for resource in resources if exact_tag_name(resource, expected)), None)


def find_efs_named(file_systems, expected):
    return next(
        (fs for fs in file_systems if fs.get("Name", "").strip().casefold() == expected.casefold()),
        None,
    )


def run_ssm_check(ssm, instance_id, command, comment):
    """Return (success, reason) for a read-only SSM shell command."""
    try:
        info = ssm.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
        ).get("InstanceInformationList", [])
        if not info or info[0].get("PingStatus") != "Online":
            return False, "EC2 is not online in Systems Manager"

        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": [command]},
            TimeoutSeconds=30,
            Comment=comment,
        )
        command_id = response["Command"]["CommandId"]
        for _ in range(30):
            time.sleep(1)
            try:
                invocation = ssm.get_command_invocation(
                    CommandId=command_id, InstanceId=instance_id
                )
            except ssm.exceptions.InvocationDoesNotExist:
                continue
            status = invocation.get("Status")
            if status == "Success":
                return True, ""
            if status in {"Cancelled", "Failed", "TimedOut", "Cancelling"}:
                detail = invocation.get("StandardErrorContent", "").strip()
                return False, detail or "SSM verification command failed"
        return False, "SSM verification timed out"
    except (ClientError, BotoCoreError) as exc:
        return None, f"SSM check unavailable: {exc}"


def verify_web_server_inside_instance(ssm, instance_id):
    return run_ssm_check(
        ssm,
        instance_id,
        "systemctl is-active --quiet httpd || "
        "systemctl is-active --quiet nginx || "
        "systemctl is-active --quiet apache2",
        "BMIT3273 web server verification",
    )


def verify_efs_inside_instance(ssm, instance_id, raw_name, student_id):
    normalized_name = "".join(raw_name.casefold().split())
    name_q = shlex.quote(normalized_name)
    sid_q = shlex.quote(student_id.strip())
    command = (
        "mountpoint -q /mnt/efs && "
        "test -f /mnt/efs/student.txt && "
        "tr -d '[:space:]' < /mnt/efs/student.txt | "
        f"tr '[:upper:]' '[:lower:]' | grep -Fq -- {name_q} && "
        f"grep -Fqi -- {sid_q} /mnt/efs/student.txt"
    )
    return run_ssm_check(
        ssm, instance_id, command, "BMIT3273 read-only EFS verification"
    )


def main():
    global SCORE

    banner("BMIT3273 CLOUD COMPUTING - PRACTICAL TEST SET 2")
    print(f"  {W}VPC | EC2 Web Server | EFS | EBS{X}")

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
        "route_table": f"rtb-{name}",
        "web_sg": f"web-{name}",
        "instance": f"ec2-{name}",
        "efs": f"efs-{name}",
        "efs_sg": f"efs-sg-{name}",
        "volume": f"ebs-{name}",
        "snapshot": f"snap-{name}",
    }

    try:
        session = boto3.session.Session(region_name=REGION)
        sts = session.client("sts")
        identity = sts.get_caller_identity()
        ec2 = session.client("ec2")
        efs = session.client("efs")
        ssm = session.client("ssm")
    except (NoCredentialsError, ClientError, BotoCoreError) as exc:
        print(f"\n{R}Unable to access the Learner Lab AWS account: {exc}{X}")
        sys.exit(2)

    print(f"\n  Region  : {REGION}")
    print(f"  Account : {identity.get('Account', 'Unknown')}")
    print(f"  Student : {raw_name} ({student_id})")

    scores = {}
    target_vpc = target_subnet = target_igw = target_rt = None
    target_web_sg = target_instance = target_efs_sg = target_fs = None
    target_volume = None

    # Question 1
    section("Question 1: Custom VPC & Networking")
    q1 = 0
    try:
        target_vpc = find_named(ec2.describe_vpcs()["Vpcs"], expected["vpc"])
        if target_vpc:
            q1 += award(f"Exact VPC name: {expected['vpc']}", 3)
            q1 += award("VPC CIDR: 10.0.0.0/16", 2) if target_vpc.get("CidrBlock") == "10.0.0.0/16" else fail("VPC CIDR: 10.0.0.0/16", 2, f"Found {target_vpc.get('CidrBlock')}")
        else:
            q1 += fail(f"Exact VPC name: {expected['vpc']}", 3)
            q1 += fail("VPC CIDR: 10.0.0.0/16", 2)

        target_subnet = find_named(ec2.describe_subnets()["Subnets"], expected["subnet"])
        if target_subnet:
            q1 += award(f"Exact subnet name: {expected['subnet']}", 2)
            q1 += award("Subnet CIDR: 10.0.1.0/24", 2) if target_subnet.get("CidrBlock") == "10.0.1.0/24" else fail("Subnet CIDR: 10.0.1.0/24", 2, f"Found {target_subnet.get('CidrBlock')}")
            correct_vpc = bool(target_vpc and target_subnet.get("VpcId") == target_vpc.get("VpcId"))
            q1 += award("Subnet belongs to the required VPC", 2) if correct_vpc else fail("Subnet belongs to the required VPC", 2)
        else:
            q1 += fail(f"Exact subnet name: {expected['subnet']}", 2)
            q1 += fail("Subnet CIDR: 10.0.1.0/24", 2)
            q1 += fail("Subnet belongs to the required VPC", 2)

        target_igw = find_named(ec2.describe_internet_gateways()["InternetGateways"], expected["igw"])
        if target_igw:
            q1 += award(f"Exact Internet Gateway name: {expected['igw']}", 2)
            attached = bool(target_vpc and any(a.get("VpcId") == target_vpc.get("VpcId") for a in target_igw.get("Attachments", [])))
            q1 += award("Internet Gateway attached to required VPC", 2) if attached else fail("Internet Gateway attached to required VPC", 2)
        else:
            q1 += fail(f"Exact Internet Gateway name: {expected['igw']}", 2)
            q1 += fail("Internet Gateway attached to required VPC", 2)

        target_rt = find_named(ec2.describe_route_tables()["RouteTables"], expected["route_table"])
        if target_rt:
            q1 += award(f"Exact route table name: {expected['route_table']}", 2)
            q1 += award("Route table belongs to required VPC", 1) if target_vpc and target_rt.get("VpcId") == target_vpc.get("VpcId") else fail("Route table belongs to required VPC", 1)
            route_ok = bool(target_igw and any(r.get("DestinationCidrBlock") == "0.0.0.0/0" and r.get("GatewayId") == target_igw.get("InternetGatewayId") for r in target_rt.get("Routes", [])))
            q1 += award("Default route targets the required Internet Gateway", 3) if route_ok else fail("Default route targets the required Internet Gateway", 3)
            assoc_ok = bool(target_subnet and any(a.get("SubnetId") == target_subnet.get("SubnetId") for a in target_rt.get("Associations", [])))
            q1 += award("Route table explicitly associated with required subnet", 4) if assoc_ok else fail("Route table explicitly associated with required subnet", 4)
        else:
            q1 += fail(f"Exact route table name: {expected['route_table']}", 2)
            q1 += fail("Route table belongs to required VPC", 1)
            q1 += fail("Default route targets required Internet Gateway", 3)
            q1 += fail("Route table explicitly associated with required subnet", 4)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 1 API error: {exc}{X}")
    scores["Question 1: VPC"] = q1
    subtotal("Question 1", q1)

    # Question 2
    section("Question 2: EC2 Instance with Web Server")
    q2 = 0
    try:
        groups = ec2.describe_security_groups()["SecurityGroups"]
        target_web_sg = next((sg for sg in groups if sg.get("GroupName", "").casefold() == expected["web_sg"].casefold()), None)
        if target_web_sg:
            q2 += award(f"Exact web security group name: {expected['web_sg']}", 2)
            q2 += award("Web security group belongs to required VPC", 1) if target_vpc and target_web_sg.get("VpcId") == target_vpc.get("VpcId") else fail("Web security group belongs to required VPC", 1)
            ssh_ok = any(permission_allows_port_from_anywhere(p, 22) for p in target_web_sg.get("IpPermissions", []))
            http_ok = any(permission_allows_port_from_anywhere(p, 80) for p in target_web_sg.get("IpPermissions", []))
            q2 += award("SSH TCP 22 allowed from 0.0.0.0/0", 2) if ssh_ok else fail("SSH TCP 22 allowed from 0.0.0.0/0", 2)
            q2 += award("HTTP TCP 80 allowed from 0.0.0.0/0", 2) if http_ok else fail("HTTP TCP 80 allowed from 0.0.0.0/0", 2)
        else:
            q2 += fail(f"Exact web security group name: {expected['web_sg']}", 2)
            q2 += fail("Web security group belongs to required VPC", 1)
            q2 += fail("SSH TCP 22 allowed from 0.0.0.0/0", 2)
            q2 += fail("HTTP TCP 80 allowed from 0.0.0.0/0", 2)

        reservations = ec2.describe_instances(Filters=[{"Name": "instance-state-name", "Values": ["pending", "running"]}])["Reservations"]
        instances = [instance for reservation in reservations for instance in reservation.get("Instances", [])]
        target_instance = find_named(instances, expected["instance"])
        if target_instance:
            q2 += award(f"Exact EC2 name: {expected['instance']}", 2)
            q2 += award("Instance type: t3.micro", 2) if target_instance.get("InstanceType") == "t3.micro" else fail("Instance type: t3.micro", 2, f"Found {target_instance.get('InstanceType')}")
            q2 += award("EC2 belongs to required VPC", 2) if target_vpc and target_instance.get("VpcId") == target_vpc.get("VpcId") else fail("EC2 belongs to required VPC", 2)
            q2 += award("EC2 belongs to required subnet", 2) if target_subnet and target_instance.get("SubnetId") == target_subnet.get("SubnetId") else fail("EC2 belongs to required subnet", 2)
            q2 += award("EC2 has a public IPv4 address", 2) if target_instance.get("PublicIpAddress") else fail("EC2 has a public IPv4 address", 2)
            profile_arn = target_instance.get("IamInstanceProfile", {}).get("Arn", "")
            q2 += award("LabInstanceProfile attached", 2) if profile_arn.endswith("/LabInstanceProfile") else fail("LabInstanceProfile attached", 2)
            sg_attached = bool(target_web_sg and target_web_sg.get("GroupId") in {g.get("GroupId") for g in target_instance.get("SecurityGroups", [])})
            q2 += award("Required web security group attached to EC2", 2) if sg_attached else fail("Required web security group attached to EC2", 2)

            try:
                data = ec2.describe_instance_attribute(InstanceId=target_instance["InstanceId"], Attribute="userData").get("UserData", {}).get("Value", "")
                decoded = base64.b64decode(data).decode("utf-8", errors="ignore").casefold() if data else ""
                user_data_ok = any(token in decoded for token in ("httpd", "apache", "nginx"))
                if user_data_ok:
                    q2 += award("User Data installs a web server", 2)
                else:
                    verified, reason = verify_web_server_inside_instance(
                        ssm, target_instance["InstanceId"]
                    )
                    if verified:
                        q2 += award(
                            "Web server active (User Data unreadable)", 2
                        )
                    else:
                        q2 += fail(
                            "User Data installs a web server",
                            2,
                            f"No web-server command found; fallback failed: {reason}",
                        )
            except (ClientError, ValueError) as exc:
                verified, reason = verify_web_server_inside_instance(
                    ssm, target_instance["InstanceId"]
                )
                if verified:
                    q2 += award(
                        "Web server active (User Data inspection unavailable)", 2
                    )
                else:
                    q2 += fail(
                        "User Data installs a web server",
                        2,
                        f"{exc}; fallback verification failed: {reason}",
                    )

            public_ip = target_instance.get("PublicIpAddress")
            if public_ip:
                try:
                    request = urllib.request.Request(f"http://{public_ip}", headers={"User-Agent": "BMIT3273-Grader"})
                    context = ssl._create_unverified_context()
                    with urllib.request.urlopen(request, timeout=8, context=context) as response:
                        body = response.read().decode("utf-8", errors="ignore").casefold()
                    compact_body = "".join(body.split())
                    page_ok = "".join(raw_name.casefold().split()) in compact_body and student_id.casefold() in body
                    q2 += award("Web page displays full name and student ID", 2) if page_ok else fail("Web page displays full name and student ID", 2)
                except Exception as exc:
                    q2 += fail("Web page displays full name and student ID", 2, f"HTTP check failed: {exc}")
            else:
                q2 += fail("Web page displays full name and student ID", 2, "No public IP")
        else:
            for description, points in [
                (f"Exact EC2 name: {expected['instance']}", 2), ("Instance type: t3.micro", 2),
                ("EC2 belongs to required VPC", 2), ("EC2 belongs to required subnet", 2),
                ("EC2 has a public IPv4 address", 2), ("LabInstanceProfile attached", 2),
                ("Required web security group attached to EC2", 2), ("User Data installs a web server", 2),
                ("Web page displays full name and student ID", 2)]:
                q2 += fail(description, points)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 2 API error: {exc}{X}")
    scores["Question 2: EC2"] = q2
    subtotal("Question 2", q2)

    # Question 3
    section("Question 3: EFS Shared File System Deployment")
    q3 = 0
    try:
        target_fs = find_efs_named(efs.describe_file_systems()["FileSystems"], expected["efs"])
        if target_fs:
            fs_id = target_fs["FileSystemId"]
            q3 += award(f"Exact EFS name: {expected['efs']}", 3)
            q3 += award("EFS lifecycle state: available", 2) if target_fs.get("LifeCycleState") == "available" else fail("EFS lifecycle state: available", 2, f"Found {target_fs.get('LifeCycleState')}")
            q3 += award("Performance mode: generalPurpose", 2) if target_fs.get("PerformanceMode") == "generalPurpose" else fail("Performance mode: generalPurpose", 2, f"Found {target_fs.get('PerformanceMode')}")
            q3 += award("Throughput mode: bursting", 2) if target_fs.get("ThroughputMode") == "bursting" else fail("Throughput mode: bursting", 2, f"Found {target_fs.get('ThroughputMode')}")
            tags = efs.list_tags_for_resource(ResourceId=fs_id).get("Tags", [])
            q3 += award("EFS tag Project = BMIT3273", 2) if tag_value(tags, "Project").casefold() == "bmit3273" else fail("EFS tag Project = BMIT3273", 2)

            mount_targets = efs.describe_mount_targets(FileSystemId=fs_id).get("MountTargets", [])
            in_vpc = bool(target_vpc and any(mt.get("VpcId") == target_vpc.get("VpcId") for mt in mount_targets))
            in_subnet = bool(target_subnet and any(mt.get("SubnetId") == target_subnet.get("SubnetId") and mt.get("LifeCycleState") == "available" for mt in mount_targets))
            q3 += award("EFS mount target is in the required VPC", 2) if in_vpc else fail("EFS mount target is in the required VPC", 2)
            q3 += award("Available EFS mount target is in required subnet", 3) if in_subnet else fail("Available EFS mount target is in required subnet", 3)

            target_efs_sg = next((sg for sg in ec2.describe_security_groups()["SecurityGroups"] if sg.get("GroupName", "").casefold() == expected["efs_sg"].casefold()), None)
            if target_efs_sg:
                q3 += award(f"Exact EFS security group name: {expected['efs_sg']}", 2)
                attached_to_mt = False
                for mt in mount_targets:
                    mt_sgs = efs.describe_mount_target_security_groups(MountTargetId=mt["MountTargetId"]).get("SecurityGroups", [])
                    if target_efs_sg.get("GroupId") in mt_sgs:
                        attached_to_mt = True
                        break
                q3 += award("EFS security group attached to mount target", 2) if attached_to_mt else fail("EFS security group attached to mount target", 2)
                nfs_ok = bool(target_web_sg and any(permission_allows_nfs_from_sg(p, target_web_sg.get("GroupId")) for p in target_efs_sg.get("IpPermissions", [])))
                q3 += award("NFS access permits only the EC2 web security group", 3) if nfs_ok else fail("NFS TCP 2049 access from web security group", 3)
            else:
                q3 += fail(f"Exact EFS security group name: {expected['efs_sg']}", 2)
                q3 += fail("EFS security group attached to mount target", 2)
                q3 += fail("NFS TCP 2049 access from web security group", 3)

            if target_instance:
                verified, reason = verify_efs_inside_instance(ssm, target_instance["InstanceId"], raw_name, student_id)
                if verified is True:
                    q3 += award("/mnt/efs mounted and student.txt contains name and ID", 2)
                elif verified is None:
                    print(f"  {Y}[MANUAL] 0/2  /mnt/efs and student.txt require manual verification{X}")
                    print(f"       {Y}-> {reason}{X}")
                    MANUAL_REVIEW.append("Q3: Verify /mnt/efs and /mnt/efs/student.txt manually (2 marks).")
                else:
                    q3 += fail("/mnt/efs mounted and student.txt contains name and ID", 2, reason)
            else:
                q3 += fail("/mnt/efs mounted and student.txt contains name and ID", 2, "EC2 not found")
        else:
            for description, points in [
                (f"Exact EFS name: {expected['efs']}", 3), ("EFS lifecycle state: available", 2),
                ("Performance mode: generalPurpose", 2), ("Throughput mode: bursting", 2),
                ("EFS tag Project = BMIT3273", 2), ("EFS mount target is in required VPC", 2),
                ("Available EFS mount target is in required subnet", 3),
                (f"Exact EFS security group name: {expected['efs_sg']}", 2),
                ("EFS security group attached to mount target", 2),
                ("NFS TCP 2049 access from web security group", 3),
                ("/mnt/efs mounted and student.txt contains name and ID", 2)]:
                q3 += fail(description, points)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 3 API error: {exc}{X}")
    scores["Question 3: EFS"] = q3
    subtotal("Question 3", q3)

    # Question 4
    section("Question 4: EBS Volume & Snapshot")
    q4 = 0
    try:
        target_volume = find_named(ec2.describe_volumes()["Volumes"], expected["volume"])
        if target_volume:
            q4 += award(f"Exact EBS volume name: {expected['volume']}", 3)
            q4 += award("EBS volume type: gp3", 2) if target_volume.get("VolumeType") == "gp3" else fail("EBS volume type: gp3", 2, f"Found {target_volume.get('VolumeType')}")
            q4 += award("EBS volume size: 10 GiB", 2) if target_volume.get("Size") == 10 else fail("EBS volume size: 10 GiB", 2, f"Found {target_volume.get('Size')} GiB")
            same_az = bool(target_instance and target_volume.get("AvailabilityZone") == target_instance.get("Placement", {}).get("AvailabilityZone"))
            q4 += award("EBS volume is in the same AZ as EC2", 3) if same_az else fail("EBS volume is in the same AZ as EC2", 3)
            attached = bool(target_instance and any(a.get("InstanceId") == target_instance.get("InstanceId") and a.get("State") in {"attaching", "attached"} for a in target_volume.get("Attachments", [])))
            q4 += award("EBS volume attached to required EC2", 4) if attached else fail("EBS volume attached to required EC2", 4)
            q4 += award("EBS tag Project = BMIT3273", 2) if tag_value(target_volume.get("Tags", []), "Project").casefold() == "bmit3273" else fail("EBS tag Project = BMIT3273", 2)
        else:
            for description, points in [(f"Exact EBS volume name: {expected['volume']}", 3), ("EBS volume type: gp3", 2), ("EBS volume size: 10 GiB", 2), ("EBS volume is in the same AZ as EC2", 3), ("EBS volume attached to required EC2", 4), ("EBS tag Project = BMIT3273", 2)]:
                q4 += fail(description, points)

        snapshots = ec2.describe_snapshots(OwnerIds=["self"])["Snapshots"]
        target_snapshot = find_named(snapshots, expected["snapshot"])
        if target_snapshot:
            q4 += award(f"Exact snapshot name: {expected['snapshot']}", 3)
            source_ok = bool(target_volume and target_snapshot.get("VolumeId") == target_volume.get("VolumeId"))
            q4 += award("Snapshot was created from required EBS volume", 3) if source_ok else fail("Snapshot was created from required EBS volume", 3)
            q4 += award("Snapshot tag Project = BMIT3273", 2) if tag_value(target_snapshot.get("Tags", []), "Project").casefold() == "bmit3273" else fail("Snapshot tag Project = BMIT3273", 2)
            q4 += award("Snapshot state: completed", 1) if target_snapshot.get("State") == "completed" else fail("Snapshot state: completed", 1, f"Found {target_snapshot.get('State')}")
        else:
            q4 += fail(f"Exact snapshot name: {expected['snapshot']}", 3)
            q4 += fail("Snapshot was created from required EBS volume", 3)
            q4 += fail("Snapshot tag Project = BMIT3273", 2)
            q4 += fail("Snapshot state: completed", 1)
    except (ClientError, BotoCoreError) as exc:
        print(f"  {R}Question 4 API error: {exc}{X}")
    scores["Question 4: EBS"] = q4
    subtotal("Question 4", q4)

    banner("FINAL RESULT")
    for label, score in scores.items():
        filled = round(score * 10 / 25)
        print(f"  {label:<19} [{'#' * filled}{'-' * (10 - filled)}] {score:2d}/25")
    print(f"\n  {'-' * 50}")
    colour = G if SCORE >= 80 else Y if SCORE >= 50 else R
    print(f"  {colour}{B}TOTAL SCORE: {SCORE} / 100{X}")
    print(f"  {'-' * 50}")

    if MANUAL_REVIEW:
        print(f"\n  {Y}{B}Manual review required:{X}")
        for item in MANUAL_REVIEW:
            print(f"  - {item}")
    print()


if __name__ == "__main__":
    main()
