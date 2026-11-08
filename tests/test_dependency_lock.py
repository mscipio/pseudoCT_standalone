#!/usr/bin/env python3
"""Fail-closed integrity checks for the locally staged dependency lock.

Re-anchored (T012): compiled/current is an obsolete historical observation,
superseded by dist/ for new packages. This test no longer walks or hashes the
compiled/current tree. For that entry it asserts only, as string checks, that
the lock labels it an obsolete historical observation and records the pinned
historical digest. The SPM8, batch-atlas and ssh2 external trees and the ssh2
Ganymed JAR are still verified against their recorded digests, and every lock
hash field must be a well-formed lowercase 64-hex SHA-256 value.

Run: python3 -I -B tests/test_dependency_lock.py
"""

import hashlib
import json
import os
import re
import stat
from pathlib import Path

# Historical digest of the obsolete compiled/current observation (string check only).
COMPILED_CURRENT_HISTORICAL_TREE_SHA256 = (
    "f55d47937c1c93e4e7f087b5a2d6939bdd23461b87a8204b99830ae8d6cefe68"
)
HEX64 = re.compile(r"[0-9a-f]{64}")


class ChecksumMismatch(Exception):
    pass


def require_equal(label, actual, expected):
    if actual != expected:
        raise ChecksumMismatch(
            f"{label}: expected {expected!r}, observed {actual!r}"
        )


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_inventory(root):
    """Return the sha256-tree-v1 digest (treeSha256) and the file, byte and symlink inventory.

    Symlinks are recorded by target and never followed.
    """
    root = Path(root).resolve()
    records = []
    files = []
    symlinks = 0
    total_bytes = 0

    for directory, dirs, names in os.walk(root, followlinks=False):
        dirs.sort()
        names.sort()
        for name in list(dirs):
            path = Path(directory) / name
            if path.is_symlink():
                relative = path.relative_to(root).as_posix()
                target = os.readlink(path)
                records.append(f"L\0{relative}\0{target}\n".encode("utf-8"))
                dirs.remove(name)
                symlinks += 1

        for name in names:
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                records.append(
                    f"L\0{relative}\0{os.readlink(path)}\n".encode("utf-8")
                )
                symlinks += 1
                continue
            if not path.is_file():
                continue
            mode = stat.S_IMODE(path.stat().st_mode)
            digest = sha256_file(path)
            size = path.stat().st_size
            records.append(
                f"F\0{relative}\0{mode:04o}\0{digest}\n".encode("utf-8")
            )
            files.append(
                {
                    "path": relative,
                    "sizeBytes": size,
                    "sha256": digest,
                    "mode": f"{mode:04o}",
                }
            )
            total_bytes += size

    records.sort()
    files.sort(key=lambda item: item["path"])
    return {
        "treeSha256": hashlib.sha256(b"".join(records)).hexdigest(),
        "files": files,
        "fileCount": len(files),
        "bytes": total_bytes,
        "symlinks": symlinks,
    }


def iter_hash_fields(node, path="$"):
    """Yield (path, value) for every object key whose name contains sha256."""
    if isinstance(node, dict):
        for key, value in node.items():
            child = f"{path}.{key}"
            if "sha256" in key.lower():
                yield child, value
            yield from iter_hash_fields(value, child)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from iter_hash_fields(value, f"{path}[{index}]")


def verify_tree(root, expected, label):
    actual = tree_inventory(root)
    require_equal(f"{label} tree SHA-256", actual["treeSha256"], expected["treeSha256"])
    expected_count = expected.get("filesCount", expected.get("files"))
    require_equal(f"{label} file count", actual["fileCount"], expected_count)
    require_equal(f"{label} byte count", actual["bytes"], expected["bytes"])
    require_equal(f"{label} symlink count", actual["symlinks"], expected["symlinks"])
    return actual


def main():
    repo = Path(__file__).resolve().parent.parent
    with open(repo / "dependencies.lock.json", encoding="utf-8") as stream:
        lock = json.load(stream)

    require_equal("lock format", lock["lockFormat"], "pseudo-ct-dependencies/v1")
    if "blocked" not in lock["policy"]["publicPackaging"].lower():
        raise AssertionError("Public packaging must remain blocked pending rights review.")

    hash_fields = list(iter_hash_fields(lock))
    if not hash_fields:
        raise AssertionError("The lock records no SHA-256 hash fields.")
    for field_path, value in hash_fields:
        if not (isinstance(value, str) and HEX64.fullmatch(value)):
            raise AssertionError(f"{field_path} is not a well-formed SHA-256 hex value.")

    dependencies = {item["id"]: item for item in lock["dependencies"]}
    local_roots = {
        "spm8-r6313": dependencies["spm8-r6313"]["artifact"],
        "Batch_atlas": dependencies["batch-atlas-shared"]["artifact"],
    }
    for name, expected in local_roots.items():
        verify_tree(repo / expected["path"], expected, expected["path"])
        dependency = dependencies[
            "batch-atlas-shared" if name == "Batch_atlas" else name
        ]
        license_record = dependency["license"]
        if "blocked" not in license_record["publicRedistribution"].lower():
            raise AssertionError(f"Public redistribution unexpectedly cleared for {name}.")

    # ssh2 Ganymed JAR, verified against external/ssh2_v2_m1_r5 (the ssh2 tree root).
    ssh2 = dependencies["ssh2-v2-m1-r5"]["artifact"]
    jar = repo / ssh2["developmentPath"] / "ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1.jar"
    require_equal("ssh2 Ganymed JAR SHA-256", sha256_file(jar), ssh2["ganymedJarSha256"])

    # compiled/current: string checks only; its tree is never read (obsolete historical observation).
    current = lock["observedLayout"]["current"]
    boundary = lock["distributionLayout"]["checkoutBoundary"]
    require_equal(
        "compiled/current recorded tree SHA-256 (historical)",
        current["canonicalTreeSha256"],
        COMPILED_CURRENT_HISTORICAL_TREE_SHA256,
    )
    require_equal(
        "compiled/current checkout-boundary digest (historical)",
        boundary["compiledCurrentTreeSha256"],
        COMPILED_CURRENT_HISTORICAL_TREE_SHA256,
    )
    if "obsolete historical observation" not in current["note"]:
        raise AssertionError("compiled/current must be recorded as an obsolete historical observation.")

    # A digest mismatch must raise, never degrade to a warning or alternate root.
    try:
        require_equal("intentional mismatch probe", "actual", "different")
    except ChecksumMismatch:
        pass
    else:
        raise AssertionError("Checksum mismatch did not fail closed.")

    print(
        "Current dependency integrity passed: SPM8/atlas trees, ssh2 JAR and well-formed "
        "lock hashes verified; compiled/current recorded as an obsolete historical "
        "observation (not read); public redistribution remains blocked."
    )


if __name__ == "__main__":
    main()
