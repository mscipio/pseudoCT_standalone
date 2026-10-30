#!/usr/bin/env python3
"""Fail-closed integrity checks for the locally staged dependency lock."""

import hashlib
import json
import os
import stat
from pathlib import Path


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
    """Return sha256-tree-v1 and every local file record without following links."""
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

    dependencies = {item["id"]: item for item in lock["dependencies"]}
    local_roots = {
        "spm8-r6313": dependencies["spm8-r6313"]["artifact"],
        "spm8-dan": dependencies["spm8-dan"]["artifact"],
        "Batch_atlas": dependencies["batch-atlas-shared"]["artifact"],
    }
    for name, expected in local_roots.items():
        verify_tree(repo / expected["path"], expected, expected["path"])
        license_record = dependencies[
            "batch-atlas-shared" if name == "Batch_atlas" else name
        ]["license"]
        if "blocked" not in license_record["publicRedistribution"].lower():
            raise AssertionError(f"Public redistribution unexpectedly cleared for {name}.")

    legacy = lock["artifacts"]["legacyV2Candidate"]["localStaging"]
    actual_legacy = verify_tree(repo / legacy["path"], legacy, legacy["path"])
    legacy_license = lock["artifacts"]["legacyV2Candidate"]["license"]
    if "blocked" not in legacy_license["publicRedistribution"].lower():
        raise AssertionError("Legacy package public redistribution unexpectedly cleared.")
    expected_files = legacy["files"]
    actual_files = [
        {
            "path": f'{legacy["path"]}{item["path"]}',
            "sizeBytes": item["sizeBytes"],
            "sha256": item["sha256"],
        }
        for item in actual_legacy["files"]
    ]
    actual_files.sort(key=lambda item: item["path"])
    if actual_files != expected_files:
        raise ChecksumMismatch("legacy staged path/size/SHA-256 inventory mismatch")

    # The legacy-specific atlas is distinct from the shared atlas; derive its
    # tree digest from the already-verified complete legacy inventory.
    legacy_atlas = dependencies["batch-atlas-legacy-deployment"]["artifact"]
    atlas_files = [
        item for item in actual_legacy["files"] if item["path"].startswith("Batch_atlas/")
    ]
    atlas_records = []
    for item in atlas_files:
        relative = item["path"][len("Batch_atlas/"):]
        atlas_records.append(
            f'F\0{relative}\0{item["mode"]}\0{item["sha256"]}\n'.encode("utf-8")
        )
    atlas_records.sort()
    require_equal(
        "legacy Batch_atlas tree SHA-256",
        hashlib.sha256(b"".join(atlas_records)).hexdigest(),
        legacy_atlas["treeSha256"],
    )
    require_equal("legacy Batch_atlas file count", len(atlas_files), legacy_atlas["files"])
    require_equal(
        "legacy Batch_atlas bytes",
        sum(item["sizeBytes"] for item in atlas_files),
        legacy_atlas["bytes"],
    )

    # The existing current payload is immutable in this task and stays pinned.
    current = lock["observedLayout"]["current"]
    actual_current = tree_inventory(repo / current["availableArtifactPath"])
    require_equal(
        "compiled/current tree SHA-256",
        actual_current["treeSha256"],
        current["canonicalTreeSha256"],
    )

    # A digest mismatch must raise, never degrade to a warning or alternate root.
    try:
        require_equal("intentional mismatch probe", "actual", "different")
    except ChecksumMismatch:
        pass
    else:
        raise AssertionError("Checksum mismatch did not fail closed.")

    print(
        "Dependency lock integrity passed: local SPM8/atlas trees and all "
        f"{len(expected_files)} legacy staged files matched; public redistribution remains blocked."
    )


if __name__ == "__main__":
    main()
