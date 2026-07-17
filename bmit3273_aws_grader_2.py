#!/usr/bin/env python3
"""Patch the revised BMIT3273 Set 2 grader.

Fixes:
1. AWS SSM TimeoutSeconds minimum (15 -> 30).
2. Q3 maximum mark bug (27 -> 25).
3. Distinguishes an unavailable SSM service from a failed EFS mount check.

Usage:
    python3 fix_bmit3273_aws_grader_2.py bmit3273_aws_grader_2.py

The original file is preserved as <filename>.bak.
"""

from pathlib import Path
import py_compile
import shutil
import sys


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Patch '{label}' expected 1 match but found {count}.")
    return text.replace(old, new, 1)


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 fix_bmit3273_aws_grader_2.py <grader.py>")
        return 2

    target = Path(sys.argv[1]).expanduser().resolve()
    if not target.is_file():
        print(f"File not found: {target}")
        return 2

    text = target.read_text(encoding="utf-8")

    text = replace_once(
        text,
        'TimeoutSeconds=15,',
        'TimeoutSeconds=30,',
        'SSM minimum timeout',
    )

    text = replace_once(
        text,
        'return False, "EC2 is not online in Systems Manager; verify /mnt/efs manually"',
        'return None, "EC2 is not online in Systems Manager; verify /mnt/efs manually"',
        'SSM offline status',
    )

    text = replace_once(
        text,
        'return False, f"SSM check unavailable: {exc}"',
        'return None, f"SSM check unavailable: {exc}"',
        'SSM unavailable status',
    )

    old_block = '''                if verified:\n                    q3 += award("/mnt/efs mounted and student.txt contains name and ID", 3)\n                else:\n                    q3 += fail("/mnt/efs mounted and student.txt contains name and ID", 3, reason)\n                    if "Systems Manager" in reason or "SSM" in reason:\n                        MANUAL_REVIEW.append("Q3: Verify /mnt/efs and /mnt/efs/student.txt manually (3 marks).")'''

    new_block = '''                if verified is True:\n                    q3 += award("/mnt/efs mounted and student.txt contains name and ID", 2)\n                elif verified is None:\n                    print(f"  {Y}[MANUAL] 0/2  /mnt/efs and student.txt require manual verification{X}")\n                    print(f"       {Y}-> {reason}{X}")\n                    MANUAL_REVIEW.append("Q3: Verify /mnt/efs and /mnt/efs/student.txt manually (2 marks).")\n                else:\n                    q3 += fail("/mnt/efs mounted and student.txt contains name and ID", 2, reason)'''
    text = replace_once(text, old_block, new_block, 'Q3 tri-state SSM result')

    # Q3 allocation correction: NFS relationship 4 -> 3, mount/file proof 3 -> 2.
    replacements = [
        (
            'q3 += award("NFS access permits only the EC2 web security group", 4) if nfs_ok else fail("NFS TCP 2049 access from web security group", 4)',
            'q3 += award("NFS access permits only the EC2 web security group", 3) if nfs_ok else fail("NFS TCP 2049 access from web security group", 3)',
            'NFS marks',
        ),
        (
            'q3 += fail("NFS TCP 2049 access from web security group", 4)',
            'q3 += fail("NFS TCP 2049 access from web security group", 3)',
            'NFS missing-SG marks',
        ),
        (
            '("NFS TCP 2049 access from web security group", 4),',
            '("NFS TCP 2049 access from web security group", 3),',
            'NFS missing-EFS marks',
        ),
        (
            'q3 += fail("/mnt/efs mounted and student.txt contains name and ID", 3, "EC2 not found")',
            'q3 += fail("/mnt/efs mounted and student.txt contains name and ID", 2, "EC2 not found")',
            'mount proof EC2-missing marks',
        ),
        (
            '("/mnt/efs mounted and student.txt contains name and ID", 3)]:',
            '("/mnt/efs mounted and student.txt contains name and ID", 2)]:',
            'mount proof EFS-missing marks',
        ),
    ]
    for old, new, label in replacements:
        text = replace_once(text, old, new, label)

    backup = target.with_name(target.name + ".bak")
    shutil.copy2(target, backup)
    target.write_text(text, encoding="utf-8")

    try:
        py_compile.compile(str(target), doraise=True)
    except py_compile.PyCompileError:
        shutil.copy2(backup, target)
        raise

    print(f"Patched successfully: {target}")
    print(f"Backup preserved     : {backup}")
    print("Q3 maximum           : 25 marks")
    print("SSM timeout           : 30 seconds")
    print("SSM unavailable       : manual review, not reported as a student failure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
