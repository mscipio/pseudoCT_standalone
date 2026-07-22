#!/usr/bin/env python3
"""Generate and validate deterministic provenance for the bundled SPM8 tree."""

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from collections import OrderedDict


SCHEMA = "pseudo-CT.spm-provenance/v1"
TREE_NAME = "spm8-r6313"
CHECKSUMS_NAME = "CHECKSUMS.sha256"
INVENTORY_NAME = "INVENTORY.json"
GENERATED_FILES = (CHECKSUMS_NAME, INVENTORY_NAME)
REPOSITORY_METADATA = (".git/**", ".gitignore", ".gitattributes", ".gitmodules")
IDENTITY_PATTERN = re.compile(
    r"^% Version 6313 \(SPM8\) 23-Jan-2015$", re.MULTILINE
)


class ProvenanceError(Exception):
    """Raised for any invalid or non-canonical provenance state."""


def fail(message):
    raise ProvenanceError(message)


def path_key(path):
    return path.encode("utf-8")


def relative_path(root, path):
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    if rel == "." or rel.startswith("../") or rel.startswith("/"):
        fail("path escapes provenance root: %s" % rel)
    if "\\" in rel or any(ord(ch) < 32 for ch in rel):
        fail("non-portable path: %s" % rel)
    parts = rel.split("/")
    if any(part in ("", ".", "..") for part in parts):
        fail("unsafe relative path: %s" % rel)
    return rel


def is_excluded(rel):
    if rel in GENERATED_FILES:
        return True
    if rel == ".git" or rel.startswith(".git/"):
        return True
    return rel in (".gitignore", ".gitattributes", ".gitmodules")


def regular_files(root):
    if not os.path.isdir(root) or os.path.islink(root):
        fail("tree root is not a real directory: %s" % root)
    result = []

    def walk(directory):
        try:
            entries = list(os.scandir(directory))
        except OSError as exc:
            fail("cannot read directory %s: %s" % (directory, exc))
        entries.sort(key=lambda entry: path_key(entry.name))
        for entry in entries:
            rel = relative_path(root, entry.path)
            if is_excluded(rel):
                continue
            if entry.is_symlink():
                fail("symlink is not allowed in provenance scope: %s" % rel)
            if entry.is_dir(follow_symlinks=False):
                walk(entry.path)
            elif entry.is_file(follow_symlinks=False):
                result.append((rel, entry.path))
            else:
                fail("non-regular file is not allowed in provenance scope: %s" % rel)

    walk(root)
    result.sort(key=lambda item: path_key(item[0]))
    return result


def sha256_file(path):
    digest = hashlib.sha256()
    try:
        with open(path, "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        fail("cannot read %s: %s" % (path, exc))
    return digest.hexdigest()


def read_evidence(root, relative):
    path = os.path.join(root, relative.replace("/", os.sep))
    if not os.path.isfile(path) or os.path.islink(path):
        fail("identity evidence missing: %s" % relative)
    try:
        return open(path, "r", encoding="utf-8").read()
    except (OSError, UnicodeError) as exc:
        fail("cannot read identity evidence %s: %s" % (relative, exc))


def identity(root):
    contents = read_evidence(root, "Contents.m")
    if not IDENTITY_PATTERN.search(contents):
        fail("Contents.m does not evidence SPM8 revision r6313")
    readme = read_evidence(root, "README.txt")
    if "http://www.fil.ion.ucl.ac.uk/spm/" not in readme:
        fail("README.txt does not evidence the SPM source URL")
    license_text = read_evidence(root, "spm_LICENCE.man")
    if "GNU General Public Licence" not in license_text:
        fail("spm_LICENCE.man does not evidence GNU GPL licensing")
    return contents


def checksum_lines(root):
    records = []
    for rel, path in regular_files(root):
        records.append("%s  %s\n" % (sha256_file(path), rel))
    return "".join(records).encode("ascii")


def inventory_for(root, checksum_bytes):
    files = regular_files(root)
    total_bytes = 0
    for _, path in files:
        try:
            total_bytes += os.stat(path).st_size
        except OSError as exc:
            fail("cannot stat %s: %s" % (path, exc))
    identity(root)
    result = OrderedDict()
    result["schema"] = SCHEMA
    result["schema_version"] = 1
    result["identity"] = OrderedDict([
        ("product", "SPM8"),
        ("revision", "r6313"),
        ("release_date", "23-Jan-2015"),
        ("evidence", ["Contents.m:2", "README.txt:14-15"]),
    ])
    result["source"] = OrderedDict([
        ("name", "Statistical Parametric Mapping"),
        ("url", "http://www.fil.ion.ucl.ac.uk/spm/"),
        ("release_url", "http://www.fil.ion.ucl.ac.uk/spm/software/spm8/"),
        ("evidence", ["README.txt:4", "README.txt:46", "Contents.m:28-30"]),
    ])
    result["license"] = OrderedDict([
        ("name", "GNU General Public License"),
        ("version", "2 or later"),
        ("evidence", ["README.txt:100-105", "spm_LICENCE.man:5-11"]),
    ])
    result["scope"] = OrderedDict([
        ("root", TREE_NAME),
        ("file_count", len(files)),
        ("total_bytes", total_bytes),
        ("checksums", CHECKSUMS_NAME),
        ("aggregate_sha256", hashlib.sha256(checksum_bytes).hexdigest()),
        ("includes", "All regular files below the tree root after exclusions."),
        ("exclusions", OrderedDict([
            ("generated_provenance", list(GENERATED_FILES)),
            ("repository_metadata", list(REPOSITORY_METADATA)),
            ("symlinks", "Rejected rather than followed."),
        ])),
    ])
    result["generation"] = OrderedDict([
        ("tool", "scripts/generate_r6313_provenance.py"),
        ("ordering", "UTF-8 bytewise ascending portable relative paths."),
        ("paths", "Relative POSIX paths only; absolute and parent paths rejected."),
        ("hash", "SHA-256 of each file; aggregate is SHA-256 of canonical checksum bytes."),
        ("determinism", "No timestamps, host paths, filesystem order, or repository state are recorded."),
    ])
    return result


def render_inventory(inventory):
    return (json.dumps(inventory, ensure_ascii=True, indent=2, separators=(",", ": ")) + "\n").encode("ascii")


def parse_checksum_bytes(checksum_bytes):
    try:
        text = checksum_bytes.decode("ascii")
    except UnicodeDecodeError:
        fail("checksums are not ASCII")
    if not text or not text.endswith("\n"):
        fail("checksums must be non-empty and newline terminated")
    paths = []
    records = {}
    for line_number, line in enumerate(text.splitlines(), 1):
        match = re.match(r"^([0-9a-f]{64})  ([^\s]+)$", line)
        if not match:
            fail("malformed checksum line %d" % line_number)
        digest, rel = match.groups()
        if is_excluded(rel):
            fail("checksum lists excluded path: %s" % rel)
        if rel.startswith("/") or "\\" in rel or ".." in rel.split("/"):
            fail("unsafe checksum path: %s" % rel)
        if rel in records:
            fail("duplicate checksum path: %s" % rel)
        paths.append(rel)
        records[rel] = digest
    if paths != sorted(paths, key=path_key):
        fail("checksum paths are not in canonical order")
    return records


def load_inventory(root):
    path = os.path.join(root, INVENTORY_NAME)
    try:
        with open(path, "rb") as handle:
            raw = handle.read()
        value = json.loads(raw.decode("ascii"), object_pairs_hook=OrderedDict)
    except (OSError, UnicodeError, ValueError) as exc:
        fail("malformed inventory: %s" % exc)
    if not isinstance(value, dict):
        fail("inventory root must be an object")
    return value, raw


def validate(root):
    identity(root)
    checksum_path = os.path.join(root, CHECKSUMS_NAME)
    try:
        with open(checksum_path, "rb") as handle:
            checksum_bytes = handle.read()
    except OSError as exc:
        fail("checksums missing: %s" % exc)
    records = parse_checksum_bytes(checksum_bytes)
    inventory, inventory_bytes = load_inventory(root)
    expected = inventory_for(root, checksum_bytes)
    if inventory != expected or inventory_bytes != render_inventory(expected):
        fail("inventory is not the canonical record for this tree")

    actual_files = regular_files(root)
    actual_paths = [rel for rel, _ in actual_files]
    if list(records.keys()) != actual_paths:
        fail("checksum scope does not match the current tree")
    for rel, path in actual_files:
        if records[rel] != sha256_file(path):
            fail("checksum mismatch: %s" % rel)
    if hashlib.sha256(checksum_bytes).hexdigest() != expected["scope"]["aggregate_sha256"]:
        fail("checksum aggregate mismatch")
    return expected


def atomic_write(path, data):
    directory = os.path.dirname(path)
    fd, temporary = tempfile.mkstemp(prefix=".provenance-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def write_records(root):
    checksum_bytes = checksum_lines(root)
    inventory_bytes = render_inventory(inventory_for(root, checksum_bytes))
    atomic_write(os.path.join(root, CHECKSUMS_NAME), checksum_bytes)
    atomic_write(os.path.join(root, INVENTORY_NAME), inventory_bytes)
    validate(root)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tree", required=True, help="SPM8 tree to record or validate")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true", help="write deterministic records")
    action.add_argument("--validate", action="store_true", help="validate existing records")
    args = parser.parse_args(argv)
    try:
        root = os.path.abspath(args.tree)
        if os.path.basename(root) != TREE_NAME:
            fail("tree must be named %s" % TREE_NAME)
        if args.write:
            write_records(root)
        else:
            validate(root)
    except ProvenanceError as exc:
        print("PROVENANCE: %s" % exc, file=sys.stderr)
        return 1
    print("r6313 provenance valid: %s" % os.path.abspath(args.tree))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
