#!/usr/bin/env python3
"""pseudoCT installed-distribution assembler (build host; Python 3 standard library only).

For each selected catalog release it runs that release's MATLAB exactly once with
one build_application call (Mode 'build') into a short staging directory. It then
assembles one distribution directory from the verified build output only:

    pseudoct-<version>/
      bin/pseudoct                                  (the public launcher, copied)
      run_pseudo_CT.m                               (MATLAB frontend, copied)
      README.md                                     (user README, copied from the repo root)
      frontend/<allowlisted files>                  (MATLAB frontend, copied verbatim)
      help/index.html, help/style.css               (help documents from docs/help/;
                                                     docs/help/assets/ is never shipped)
      external/ssh2_v2_m1_r5/<SSH2_FILES>           (Ganymed JAR and licence notices;
                                                     no loose SSH2 .m wrappers)
      runtimes/<LABEL>/pseudoct_pipeline              (compiled science pipeline)
      runtimes/<LABEL>/run_pseudoct_pipeline.sh       (runner, copied)
      runtimes/<LABEL>/pseudoct_job_manager          (compiled job manager)
      resources/                                    (atlas and template files)
      python/bin/python3, python/lib/python<X.Y>/   (private CPython runtime shared by all
                                                     releases; the launcher's only Python)
      python/licenses/                              (CPython and third-party licence texts)
      manifest.json                                 (catalog copy read by bin/pseudoct)
      SHA256SUMS                                    (inventory, includes the manifest)

No src/ tree, science source or other external/ content is shipped, except the frontend
files copied from src/ (FRONTEND_FROM_SRC) and the SSH2 JAR and licence notices (SSH2_FILES).
--verify refuses any file outside this allowlist.
Publication is non-overwriting and takes an exclusive lock file in the output directory.

Failure handling: every selected release is attempted, even after an earlier release fails.
Each release's complete MATLAB output and the mcc logs are kept under
<output>/build-logs/<version>/<release>/, with a result.txt. If any release fails, nothing is
published as pseudoct-<version>/; the staging tree (successful builds, partial packages and the
failed builds' logs) is renamed to <output>/build-workspace-<version>-INCOMPLETE/, which is marked
as incomplete. The exit status is nonzero whenever a requested release fails.

Environment (prepared privately for each MATLAB invocation):
  TMPDIR, MATLAB_PREFDIR, MCR_CACHE_ROOT    short, isolated paths (see docs/releases.md).

Bundled Python: the pinned python-build-standalone archive named in config/python-runtime.json
is read from --python-archive FILE (default external/python-build-standalone/<archive>); it is
never downloaded here and its sha256 must match the pin. Only the interpreter and its standard
library are shipped (PYTHON_STDLIB_EXCLUDED is left out), with the licence texts from
config/python-runtime-licenses/. --verify runs the shipped interpreter once to check it.

Usage:
  release_application.py --version V [--releases R2010b,R2014b,...]
      --matlab-root LABEL=PATH [--matlab-root LABEL=PATH ...] [--output DIR] [--dry-run]
      [--python-archive FILE]
  release_application.py --list-releases
  release_application.py --verify DIR

Exit status: 0 success, 1 build/validation/verification failure, 2 usage error.
The MATLAB root doubles as the builder's McrRoot (the catalog runtime evidence lives
under each MATLAB installation).
"""

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(REPO_ROOT, 'config', 'releases.json')
DEFAULT_OUTPUT = os.path.join(REPO_ROOT, 'dist')
SCHEMA = 'pseudo-CT.release-distribution/v1'
VERSION_RE = re.compile(r'[0-9A-Za-z][0-9A-Za-z._+-]{0,63}')
LABEL_RE = re.compile(r'R[0-9]{4}[ab]')
SHA_RE = re.compile(r'[0-9a-f]{64}')
MATLAB_FLAGS = ['-nodesktop', '-nosplash', '-nodisplay']
MANIFEST_NAME = 'manifest.json'
SUMS_NAME = 'SHA256SUMS'
LOCK_NAME = '.pseudoct-release.lock'
# A staged executable path longer than this is refused before MATLAB runs: earlier
# long staging paths broke the compiled CTF extraction.
MAX_STAGE_PATH = 240
# Per-version log folders: <output>/build-logs/<version>/<release>/ (kept after success and failure).
BUILD_LOG_DIR = 'build-logs'
# Do not inherit TMPDIR here: build hosts may point it into a deeply nested checkout.
MATLAB_TEMP_ROOT = '/tmp'

# The two compiled executables of every release. The first element is the build-private
# staging path that build_application.m writes under its output (payload/ and standalone/
# folders, never installed as such); the second is the flat installed name under
# runtimes/<LABEL>/. The mapping is applied only in assemble().
BUILDER_TARGETS = (('payload/pseudoct_pipeline', 'pseudoct_pipeline'),
                   ('standalone/pseudoct_job_manager', 'pseudoct_job_manager'))
BUILDER_FIELDS = ('release', 'matlab_release', 'arch', 'compiler', 'source_commit',
                  'source_dirty', 'source_set_sha256', 'lock_sha256')
BUILDER_SCRIPT = os.path.join(REPO_ROOT, 'scripts', 'build_application.m')
# Installed name of the runner; it is copied from RUNNER_SOURCE, which has no staging folder.
RUNNER_NAME = 'run_pseudoct_pipeline.sh'
RUNNER_SOURCE = os.path.join(REPO_ROOT, 'scripts', 'run_pseudoct_pipeline.sh')
# Flat installed files of one runtime directory runtimes/<LABEL>/.
RUNTIME_FILES = tuple(installed for _staged, installed in BUILDER_TARGETS) + (RUNNER_NAME,)

LAUNCHER_REL = 'bin/pseudoct'
LAUNCHER_SOURCE = os.path.join(REPO_ROOT, 'bin', 'pseudoct')
FRONTEND_ENTRY = 'run_pseudo_CT.m'
FRONTEND_ENTRY_SOURCE = os.path.join(REPO_ROOT, FRONTEND_ENTRY)
# User README, shipped at the package root from the repository root.
README_NAME = 'README.md'
README_SOURCE = os.path.join(REPO_ROOT, README_NAME)
BUNDLED_LOCK_NAME = 'dependencies.lock.json'
BUNDLED_LOCK_SOURCE = os.path.join(REPO_ROOT, BUNDLED_LOCK_NAME)
DOC_FILES = (
    'installation.md',
    'headless-cli.md',
    'releases.md',
    'scientific-notes.md',
    'THIRD_PARTY_INTEGRATION.md',
)
DOC_DIR = os.path.join(REPO_ROOT, 'docs')
FRONTEND_DIR = os.path.join(REPO_ROOT, 'frontend')
# Frontend files whose single source is frontend/ (check_sources requires the directory
# to hold exactly these files). The credential store and the password dialog are shared
# with the compiled CLI and the lifecycle, so they are shipped from src/ instead.
FRONTEND_OWN = (
    'pseudo_CT_discover_umap.m',
    'pseudo_CT_gui_args.m', 'pseudo_CT_gui_state.m', 'pseudo_CT_input_window.m',
    'pseudo_CT_launch_request.m',
    'pseudo_CT_prepare_profile_choices.m', 'pseudo_CT_prepare_routine_profile_choices.m',
    'pseudo_CT_profile_choices.m', 'pseudo_CT_profile_selector.m',
    'pseudo_CT_profile_selector_label.m', 'pseudo_CT_profile_selector_layout.m',
    'pseudo_CT_result_fields.py', 'pseudo_CT_select_file.m', 'pseudo_CT_subjects_file.m')
FRONTEND_FROM_SRC = {
    'pseudo_CT_credentials.m': os.path.join(REPO_ROOT, 'src', 'api', 'pseudo_CT_credentials.m'),
    'pseudo_CT_password_entry_dialog.m': os.path.join(REPO_ROOT, 'src', 'gui', 'pseudo_CT_password_entry_dialog.m'),
    'passwordTools/LICENSE': os.path.join(REPO_ROOT, 'src', 'gui', 'passwordTools', 'LICENSE'),
    'passwordTools/strencrypt.m': os.path.join(REPO_ROOT, 'src', 'gui', 'passwordTools', 'strencrypt.m'),
    'passwordTools/uilogin.m': os.path.join(REPO_ROOT, 'src', 'gui', 'passwordTools', 'uilogin.m'),
    'passwordTools/uipassword.m': os.path.join(REPO_ROOT, 'src', 'gui', 'passwordTools', 'uipassword.m'),
}
# Every shipped frontend file, relative to frontend/ in the package.
FRONTEND_FILES = tuple(sorted(set(FRONTEND_OWN) | set(FRONTEND_FROM_SRC)))
# Python bytecode left in frontend/ is not an inventory entry (see frontend_files_on_disk).
# Nothing else is skipped.
FRONTEND_BYTECODE_SUFFIXES = ('.pyc', '.pyo')


def frontend_source(rel):
    """Repository file that supplies one shipped frontend file."""
    return FRONTEND_FROM_SRC.get(rel) or os.path.join(FRONTEND_DIR, *rel.split('/'))


# Help documents shipped under help/ in the package, copied from docs/help/. Exactly these
# two files: the screenshots under docs/help/assets/ are never shipped.
HELP_DIR = os.path.join(REPO_ROOT, 'docs', 'help')
HELP_FILES = ('index.html', 'style.css')
# Bundled MATLAB SSH2 transport (AMEND-1, D-A001). Paths are relative to SSH2_SOURCE_ROOT and
# are shipped at the same relative path under external/ssh2_v2_m1_r5/ in the package. Shipped:
# only the Ganymed JAR and the two licence notices (license.txt and the Ganymed LICENSE.txt).
# The top-level MATLAB wrappers (ssh2.m, ssh2_setup.m, ...) are NOT shipped as loose files: they
# are compiled into the job manager and pipeline executables (build_application.m -I/-a inputs), so
# the installed engine reaches them through the CTF, not through this package. The JAR keeps its
# package path under ssh2_v2_m1_r5/ganymed-ssh2-m1/, the location ssh2_setup derives it from; that
# this location resolves from the compiled CTF is unverified until the compiled-engine check.
# Not shipped: wrappers, examples, javadoc, Java sources, HISTORY, README, FAQ.
SSH2_ROOT_REL = 'external/ssh2_v2_m1_r5'
SSH2_SOURCE_ROOT = os.path.join(REPO_ROOT, *SSH2_ROOT_REL.split('/'))
SSH2_FILES = (
    'license.txt',
    'ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1.jar',
    'ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1-source/LICENSE.txt',
)
SSH2_JAR = os.path.join(SSH2_SOURCE_ROOT, *SSH2_FILES[1].split('/'))
# Atlas and template files build_application.m copies from the atlas directory, and
# SPM's DICOM dictionary copied unchanged from the SPM root.
RESOURCE_REQUIRED = (
    'ch2.nii', 'new_segment_batch.mat', 'dartel_existing_template_batch.mat',
    'create_inverse_warped_batch.mat', 'Template_1.nii', 'Template_2.nii',
    'Template_3.nii', 'Template_4.nii', 'Template_5.nii', 'Template_6.nii', 'TPM.nii',
    'spm_dicom_dict.mat')
RESOURCE_ATLAS_PATTERN = '*Atlas*.nii'
FORBIDDEN_PARTS = frozenset(['src', 'external', 'tests', 'scripts', 'config', 'compiled',
                             'build', 'cfggen', '.git', '.partial', 'app'])

# Private Python runtime (one copy for all releases). The pin names the upstream archive and
# its sha256; the licence texts are kept in the repository beside the pin.
PYTHON_PIN_PATH = os.path.join(REPO_ROOT, 'config', 'python-runtime.json')
PYTHON_LICENSE_DIR = os.path.join(REPO_ROOT, 'config', 'python-runtime-licenses')
PYTHON_CACHE_DIR = os.path.join(REPO_ROOT, 'external', 'python-build-standalone')
PYTHON_ROOT_REL = 'python'
PYTHON_EXE_REL = 'python/bin/python3'
PYTHON_LICENSE_REL = 'python/licenses'
PYTHON_TARGET = 'x86_64-unknown-linux-gnu'
# Top-level standard-library entries the launcher never uses (GUI toolkits, installers,
# virtual environments, build data); site-packages keeps only its README.
PYTHON_STDLIB_EXCLUDED = frozenset(['idlelib', 'tkinter', 'turtledemo', 'turtle.py', 'ensurepip',
                                    'venv', 'test', 'site-packages'])
PYTHON_STDLIB_KEPT = frozenset(['site-packages/README.txt'])
# Modules imported by bin/pseudoct and frontend/pseudo_CT_result_fields.py.
PYTHON_PROBE = ('import datetime, hashlib, json, os, re, selectors, shlex, stat, struct, '
                'subprocess, sys, tempfile\n'
                'print(json.dumps({"version": "%d.%d.%d" % sys.version_info[:3], '
                '"prefix": sys.prefix}))\n')


class UsageError(Exception):
    """Invalid command line or selection; exit status 2."""


class ReleaseError(Exception):
    """Validation, build or verification failure; exit status 1."""


# ---------------------------------------------------------------- catalog and selection

def validate_catalog(data):
    """Return (default, ordered entries, label->entry) for a catalog object."""
    if not isinstance(data, dict) or data.get('schema') != 1:
        raise ReleaseError('release catalog must be a JSON object with "schema": 1')
    entries = data.get('releases')
    if not isinstance(entries, list) or not entries:
        raise ReleaseError('catalog "releases" must be a non-empty list')
    by_label = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ReleaseError('catalog release entries must be objects')
        label = entry.get('label')
        if not isinstance(label, str) or not LABEL_RE.fullmatch(label):
            raise ReleaseError('invalid catalog release label: %r' % (label,))
        if label in by_label:
            raise ReleaseError('duplicate catalog release label: %s' % label)
        for key in ('matlab_version', 'mcr_version', 'architecture'):
            if not isinstance(entry.get(key), str) or not entry[key]:
                raise ReleaseError('%s: catalog field %s must be a non-empty string' % (label, key))
        ident = entry.get('runtime_identity')
        if not isinstance(ident, dict):
            raise ReleaseError('%s: catalog runtime_identity must be an object' % label)
        for key in ('mcr_version_file', 'library'):
            if not isinstance(ident.get(key), str) or not ident[key]:
                raise ReleaseError('%s: runtime_identity.%s must be a non-empty string' % (label, key))
        version_file = ident['mcr_version_file']
        if os.path.isabs(version_file) or '..' in version_file.split('/'):
            raise ReleaseError('%s: runtime_identity.mcr_version_file must be a relative path' % label)
        if ident['library'] != 'libmwmclmcrrt.so.' + entry['mcr_version']:
            raise ReleaseError('%s: runtime library %r does not match mcr_version %r'
                               % (label, ident['library'], entry['mcr_version']))
        by_label[label] = entry
    default = data.get('default')
    if default not in by_label:
        raise ReleaseError('catalog default %r is not a catalog release' % (default,))
    return default, list(entries), by_label


def load_catalog(path):
    try:
        with open(path, encoding='utf-8') as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        raise ReleaseError('cannot read release catalog %s: %s' % (path, exc))
    return validate_catalog(data)


def select_releases(default, ordered, by_label, requested):
    """Selected entries in catalog order; unknown, duplicate or empty labels fail."""
    if requested is None:
        names = [default]
    else:
        names = requested.split(',')
        seen = set()
        for name in names:
            if not name:
                raise UsageError('--releases contains an empty release label')
            if name not in by_label:
                raise UsageError('unknown release label %r; supported: %s'
                                 % (name, ', '.join(e['label'] for e in ordered)))
            if name in seen:
                raise UsageError('duplicate release label %r' % name)
            seen.add(name)
    wanted = set(names)
    return [entry for entry in ordered if entry['label'] in wanted]


def parse_roots(pairs, selected):
    """LABEL=PATH for every selected release, exactly once, and no others."""
    selected_labels = [entry['label'] for entry in selected]
    roots = {}
    for pair in pairs:
        label, sep, path = pair.partition('=')
        if not sep or not path:
            raise UsageError('--matlab-root expects LABEL=PATH, got %r' % pair)
        if label not in selected_labels:
            raise UsageError('--matlab-root given for %s, which is not selected' % label)
        if label in roots:
            raise UsageError('duplicate --matlab-root for %s' % label)
        roots[label] = os.path.abspath(path)
    missing = [label for label in selected_labels if label not in roots]
    if missing:
        raise UsageError('missing --matlab-root for: %s' % ', '.join(missing))
    return roots


def check_matlab_root(entry, root):
    """Read-only identity evidence from the catalog; MATLAB is never started here."""
    label = entry['label']
    if not os.path.isdir(root):
        raise ReleaseError('%s: MATLAB root is not a directory: %s' % (label, root))
    matlab = os.path.join(root, 'bin', 'matlab')
    if not os.path.isfile(matlab) or not os.access(matlab, os.X_OK):
        raise ReleaseError('%s: executable bin/matlab not found under %s' % (label, root))
    ident = entry['runtime_identity']
    library = os.path.join(root, 'runtime', entry['architecture'], ident['library'])
    if not os.path.exists(library):
        raise ReleaseError('%s: runtime library missing: %s' % (label, library))
    version_file = os.path.join(root, *ident['mcr_version_file'].split('/'))
    if not os.path.isfile(version_file):
        raise ReleaseError('%s: MCR version file missing: %s' % (label, version_file))
    with open(version_file, encoding='utf-8', errors='replace') as handle:
        found = handle.read().strip()
    if found != entry['mcr_version']:
        raise ReleaseError('%s: %s reports MCR %r, catalog expects %r'
                           % (label, version_file, found, entry['mcr_version']))


def frontend_files_on_disk():
    """Relative paths of the files under frontend/ that the allowlist applies to.

    Python bytecode (*.pyc, *.pyo, including those in __pycache__/) is not frontend
    content: it is generated, git ignores it, and it is never shipped. Only that bytecode
    is skipped. Every other file counts, even one inside __pycache__/, so an unexpected
    real file still fails check_sources."""
    found = set()
    for dirpath, _dirnames, filenames in os.walk(FRONTEND_DIR):
        for name in filenames:
            if name.endswith(FRONTEND_BYTECODE_SUFFIXES):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), FRONTEND_DIR)
            found.add(rel.replace(os.sep, '/'))
    return found


def check_sources():
    """Raise unless the launcher, runner, entry point, build script and copied sources exist
    and frontend/ holds exactly the FRONTEND_OWN files."""
    for path in (LAUNCHER_SOURCE, RUNNER_SOURCE, FRONTEND_ENTRY_SOURCE, README_SOURCE, BUILDER_SCRIPT, BUNDLED_LOCK_SOURCE,
                 *[os.path.join(DOC_DIR, name) for name in DOC_FILES],
                 *FRONTEND_FROM_SRC.values(), *[os.path.join(HELP_DIR, name) for name in HELP_FILES],
                 *[os.path.join(SSH2_SOURCE_ROOT, *rel.split('/')) for rel in SSH2_FILES]):
        if not os.path.isfile(path):
            raise ReleaseError('required source missing from repository: %s'
                               % os.path.relpath(path, REPO_ROOT))
    on_disk = frontend_files_on_disk()
    expected = set(FRONTEND_OWN)
    if on_disk != expected:
        raise ReleaseError('frontend/ differs from the allowlist; extra: %s; missing: %s'
                           % (sorted(on_disk - expected) or '-',
                              sorted(expected - on_disk) or '-'))


# ---------------------------------------------------------------- MATLAB build

def matlab_text(value, what):
    """Single-quoted MATLAB literal; control characters are refused."""
    if not value or any(ord(ch) < 0x20 or ord(ch) == 0x7f for ch in value):
        raise ReleaseError('%s cannot be passed to MATLAB safely: %r' % (what, value))
    return "'" + value.replace("'", "''") + "'"


def build_call(label, out_root, root):
    return ("build_application(%s, 'Mode', 'build', 'OutputRoot', %s, 'McrRoot', %s)"
            % (matlab_text(label, 'release label'),
               matlab_text(out_root, 'OutputRoot'),
               matlab_text(root, 'MATLAB root')))


def build_stdin(call):
    """Bootstrap: put the repository scripts directory on the path, run one build, and
    exit non-zero on any failure."""
    scripts = os.path.join(REPO_ROOT, 'scripts')
    return ("addpath(%s);\ntry, %s;\ncatch ME, disp(ME.message); exit(1); end\nexit(0)\n"
            % (matlab_text(scripts, 'repository scripts directory'), call))


def run_matlab(root, stdin_text, cwd, env=None):
    argv = [os.path.join(root, 'bin', 'matlab')] + MATLAB_FLAGS
    try:
        proc = subprocess.run(argv, input=stdin_text.encode('utf-8'),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=cwd,
                              env=env)
    except OSError as exc:
        raise ReleaseError('cannot start %s: %s' % (argv[0], exc))
    return proc.returncode, proc.stdout.decode('utf-8', 'replace')


def tail(text, lines=30):
    return '\n'.join(text.rstrip().splitlines()[-lines:])


def read_builder_fields(entry, pkg):
    label = entry['label']
    path = os.path.join(pkg, 'application_manifest.txt')
    if not os.path.isfile(path):
        raise ReleaseError('%s: builder manifest missing: %s' % (label, path))
    fields = {}
    with open(path, encoding='utf-8', errors='replace') as handle:
        for line in handle:
            key, sep, value = line.rstrip('\n').partition(' ')
            if sep and key:
                fields[key] = value
    for key in BUILDER_FIELDS:
        if key not in fields:
            raise ReleaseError('%s: builder manifest lacks %s' % (label, key))
    if fields['release'] != label:
        raise ReleaseError('%s: builder reports release %r' % (label, fields['release']))
    if fields['matlab_release'] != label[1:]:
        raise ReleaseError('%s: builder reports MATLAB %r' % (label, fields['matlab_release']))
    if fields['arch'] != entry['architecture']:
        raise ReleaseError('%s: builder reports architecture %r' % (label, fields['arch']))
    if fields['source_dirty'] != '0':
        raise ReleaseError('%s: builder reports a dirty source tree' % label)
    return fields


def collect_resources(label, pkg):
    res_dir = os.path.join(pkg, 'resources')
    if not os.path.isdir(res_dir):
        raise ReleaseError('%s: builder resources directory missing' % label)
    digests = {}
    for name in sorted(os.listdir(res_dir)):
        full = os.path.join(res_dir, name)
        known = name in RESOURCE_REQUIRED or fnmatch.fnmatchcase(name, RESOURCE_ATLAS_PATTERN)
        if not os.path.isfile(full) or not known:
            raise ReleaseError('%s: unexpected builder resource %r' % (label, name))
        digests[name] = sha256_file(full)
    for name in RESOURCE_REQUIRED:
        if name not in digests:
            raise ReleaseError('%s: required resource missing: resources/%s' % (label, name))
    if not any(fnmatch.fnmatchcase(name, RESOURCE_ATLAS_PATTERN) for name in digests):
        raise ReleaseError('%s: no atlas resource in builder output' % label)
    return digests


def copy_file(src, dst, mode):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    os.chmod(dst, mode)


def acquire_lock(output_dir):
    """Exclusive lock in the output directory; a held or stale lock is never removed."""
    path = os.path.join(output_dir, LOCK_NAME)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise ReleaseError('another release holds %s (or a stale lock remains); remove the lock '
                           'only when no release is running' % path)
    with os.fdopen(fd, 'w') as handle:
        handle.write('%d\n' % os.getpid())
    return path


def move_aside(path):
    """Rename an existing path to the first free <path>.prev-N, so earlier diagnostics are never lost."""
    if not os.path.lexists(path):
        return None
    number = 1
    while os.path.lexists('%s.prev-%d' % (path, number)):
        number += 1
    target = '%s.prev-%d' % (path, number)
    os.rename(path, target)
    return target


def build_log_dir(output_dir, version, label):
    """<output>/build-logs/<version>/<label>/: complete MATLAB output and mcc logs of one release."""
    return os.path.join(output_dir, BUILD_LOG_DIR, version, label)


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', errors='replace') as handle:
        handle.write(text)


def copy_compiler_logs(out_root, log_dir):
    """Copy every *.log below one release's build output (the mcc diaries) into log_dir/mcc/."""
    copied = []
    for dirpath, _dirnames, filenames in os.walk(out_root):
        for name in sorted(filenames):
            if name.endswith('.log'):
                src = os.path.join(dirpath, name)
                dst = os.path.join(log_dir, 'mcc', os.path.relpath(src, out_root))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(src, dst)
                copied.append(dst)
    return copied


def render_result(rec):
    lines = ['release=%s' % rec['label'], 'status=%s' % rec['status'],
             'exit=%s' % ('-' if rec['exit'] is None else rec['exit']),
             'reason=%s' % (rec['reason'] or '-'),
             'matlab_log=%s' % rec['matlab_log']]
    lines += ['compiler_log=%s' % path for path in rec['mcc_logs']] or ['compiler_log=-']
    return '\n'.join(lines) + '\n'


def staged_executable_paths(build_root, label):
    """Build-staging paths of the compiled executables of one release, exactly as
    build_application.m writes them: <OutputRoot>/<label>/<label>.partial/<payload|standalone>/<exe>
    with OutputRoot = <build_root>/<label>. The path is resolved the way build_application.m
    canonicalises OutputRoot."""
    stage = os.path.join(os.path.realpath(build_root), label, label + '.partial')
    return [os.path.join(stage, *staged.split('/')) for staged, _installed in BUILDER_TARGETS]


def build_release(entry, root, stage_dir, build_root, log_dir, ref):
    """Build one release and return its record. A failure is recorded, never raised, so the
    other releases still run. ref holds the provenance and resource references of the first
    release that passed; every later release is only compared against them."""
    label = entry['label']
    out_root = os.path.join(build_root, label)
    rec = {'label': label, 'entry': entry, 'status': 'FAIL', 'exit': None, 'reason': '',
           'tail': '', 'matlab_log': os.path.join(log_dir, 'matlab-output.txt'),
           'mcc_logs': [], 'built': None, 'fields': None, 'digests': None}
    try:
        move_aside(log_dir)
        os.makedirs(log_dir)
        for stage_exe in staged_executable_paths(build_root, label):
            if len(stage_exe) > MAX_STAGE_PATH:
                raise ReleaseError('staged executable path is %d characters (limit %d): %s; '
                                   'choose a shorter --output'
                                   % (len(stage_exe), MAX_STAGE_PATH, stage_exe))
        os.makedirs(out_root)
        print('BUILD %s via %s' % (label, root), flush=True)
        # TemporaryDirectory owns only this freshly created, private directory. Never
        # clean up inherited environment paths or reuse preferences between builds.
        with tempfile.TemporaryDirectory(prefix='pct-%s-' % label,
                                         dir=MATLAB_TEMP_ROOT) as temp_root:
            env = os.environ.copy()
            for key, name in (('TMPDIR', 't'), ('MATLAB_PREFDIR', 'p'),
                              ('MCR_CACHE_ROOT', 'c')):
                env[key] = os.path.join(temp_root, name)
                os.mkdir(env[key])
            # R2010b keeps its existing Java loading procedure; newer compilers
            # need Ganymed on the static classpath before MATLAB starts. This is
            # independent of (and does not replace) the builder's mcc -a input.
            if label != 'R2010b':
                with open(os.path.join(env['MATLAB_PREFDIR'], 'javaclasspath.txt'),
                          'w', encoding='utf-8') as handle:
                    handle.write(SSH2_JAR + '\n')
            rc, text = run_matlab(root, build_stdin(build_call(label, out_root, root)),
                                  stage_dir, env=env)
            rec['exit'] = rc
            write_text(rec['matlab_log'], text)
            rec['mcc_logs'] = copy_compiler_logs(out_root, log_dir)
        if rc != 0:
            rec['tail'] = tail(text)
            raise ReleaseError('MATLAB build failed (exit %d)' % rc)
        built = os.path.join(out_root, label)
        fields = read_builder_fields(entry, built)
        prov = (fields['source_commit'], fields['source_set_sha256'], fields['lock_sha256'])
        if ref['source'] is not None and prov != ref['source']:
            raise ReleaseError('source provenance differs from an earlier release build')
        for staged, _installed in BUILDER_TARGETS:
            if not os.path.isfile(os.path.join(built, *staged.split('/'))):
                raise ReleaseError('required executable missing: %s' % staged)
        digests = collect_resources(label, built)
        if ref['digests'] is not None and digests != ref['digests']:
            raise ReleaseError('builder resources differ from the first release')
        if ref['source'] is None:
            ref['source'] = prov
        if ref['digests'] is None:
            ref['digests'], ref['resource_src'] = digests, built
        rec.update(status='PASS', built=built, fields=fields, digests=digests)
    except ReleaseError as exc:
        rec['reason'] = str(exc)
    except OSError as exc:
        rec['reason'] = 'I/O error: %s' % exc
    if rec['status'] == 'PASS':
        print('PASS %s' % label, flush=True)
    else:
        print('FAIL %s: %s' % (label, rec['reason']), flush=True)
        if rec['tail']:
            print('  last MATLAB output (full log: %s):\n%s' % (rec['matlab_log'], rec['tail']),
                  flush=True)
    try:
        write_text(os.path.join(log_dir, 'result.txt'), render_result(rec))
    except OSError as exc:
        print('WARNING: could not write %s: %s' % (log_dir, exc), file=sys.stderr)
    return rec


def preserve_workspace(stage_dir, output_dir, version):
    """Keep the staging tree (successful builds, failed-build logs and any partial package) as a
    clearly marked build workspace. Nothing in it is published. Returns the kept path."""
    if not os.path.isdir(stage_dir):
        return None
    base = os.path.join(output_dir, 'build-workspace-%s-INCOMPLETE' % version)
    target, number = base, 1
    while os.path.lexists(target):
        number += 1
        target = '%s-%d' % (base, number)
    try:
        os.rename(stage_dir, target)
    except OSError as exc:
        print('WARNING: the build workspace could not be renamed and remains at %s: %s'
              % (stage_dir, exc), file=sys.stderr)
        return stage_dir
    try:
        write_text(os.path.join(target, 'BUILD_INCOMPLETE.txt'),
                   'pseudoCT %s: build incomplete. No distribution was published from this '
                   'workspace; it is kept for diagnosis only.\n' % version)
    except OSError as exc:
        print('WARNING: could not write the incomplete marker: %s' % exc, file=sys.stderr)
    return target


def summary_text(version, selected, results, published, workspace):
    lines = ['RELEASE_SUMMARY version=%s' % version]
    attempted = {rec['label'] for rec in results}
    failed = []
    for rec in results:
        exit_text = '-' if rec['exit'] is None else str(rec['exit'])
        lines.append('  %-8s %-4s exit=%s' % (rec['label'], rec['status'], exit_text))
        if rec['status'] != 'PASS':
            failed.append(rec['label'])
            lines.append('           reason: %s' % rec['reason'])
        lines.append('           matlab log: %s' % rec['matlab_log'])
        for path in rec['mcc_logs']:
            lines.append('           compiler log: %s' % path)
    for entry in selected:
        if entry['label'] not in attempted:
            failed.append(entry['label'])
            lines.append('  %-8s NOT-ATTEMPTED (assembly stopped before this release)'
                         % entry['label'])
    if published:
        lines.append('RELEASE_PASS version=%s releases=%s'
                     % (version, ','.join(entry['label'] for entry in selected)))
    else:
        if failed:
            lines.append('RELEASE_FAIL version=%s failed=%s' % (version, ','.join(failed)))
        else:
            lines.append('RELEASE_ABORTED version=%s (every release passed; assembly or '
                         'verification stopped before publication; see the error above)'
                         % version)
        lines.append('  no distribution was published; build workspace: %s'
                     % (workspace or 'not kept (see the warning above)'))
    return '\n'.join(lines) + '\n'


def report_summary(version, selected, results, published, workspace, output_dir):
    text = summary_text(version, selected, results, published, workspace)
    print(text, end='', flush=True)
    path = os.path.join(output_dir, BUILD_LOG_DIR, version, 'SUMMARY.txt')
    try:
        move_aside(path)
        write_text(path, text)
    except OSError as exc:
        print('WARNING: could not write %s: %s' % (path, exc), file=sys.stderr)


def assemble(version, selected, roots, default, catalog_entries, output_dir, python_runtime):
    """Build every selected release, then assemble, verify and publish pseudoct-<version>/ only
    when all of them passed. A failing release does not stop the others. On any failure, or on
    an error before publication, the staging tree is kept as a marked build workspace and
    nothing is published. Returns 0 when published, 1 when any release failed."""
    dest = os.path.join(output_dir, 'pseudoct-' + version)
    os.makedirs(output_dir, exist_ok=True)
    # Short staging directory inside the output directory (see MAX_STAGE_PATH). Removed after a
    # successful publication; otherwise it becomes the marked build workspace.
    stage_dir = tempfile.mkdtemp(prefix='.s', dir=output_dir)
    results = []
    published = False
    workspace = None
    try:
        pkg = os.path.join(stage_dir, 'p')
        build_root = os.path.join(stage_dir, 'b')
        os.makedirs(pkg)
        os.makedirs(build_root)
        ref = {'source': None, 'digests': None, 'resource_src': None}
        for entry in selected:
            label = entry['label']
            results.append(build_release(entry, roots[label], stage_dir, build_root,
                                         build_log_dir(output_dir, version, label), ref))
        if any(rec['status'] != 'PASS' for rec in results):
            return 1
        releases_meta = []
        for rec in results:
            entry, built, fields = rec['entry'], rec['built'], rec['fields']
            label = entry['label']
            for staged, installed in BUILDER_TARGETS:
                copy_file(os.path.join(built, *staged.split('/')),
                          os.path.join(pkg, 'runtimes', label, installed), 0o755)
            copy_file(RUNNER_SOURCE, os.path.join(pkg, 'runtimes', label, RUNNER_NAME), 0o755)
            releases_meta.append({
                'label': label,
                'matlab_version': entry['matlab_version'],
                'mcr_version': entry['mcr_version'],
                'architecture': entry['architecture'],
                'runtime_library': entry['runtime_identity']['library'],
                'compiler': fields['compiler'],
            })
        resource_digests = ref['digests']
        resource_src = ref['resource_src']
        source = ref['source']
        for name in sorted(resource_digests):
            copy_file(os.path.join(resource_src, 'resources', name),
                      os.path.join(pkg, 'resources', name), 0o644)
        copy_file(LAUNCHER_SOURCE, os.path.join(pkg, *LAUNCHER_REL.split('/')), 0o755)
        copy_file(FRONTEND_ENTRY_SOURCE, os.path.join(pkg, FRONTEND_ENTRY), 0o644)
        copy_file(README_SOURCE, os.path.join(pkg, README_NAME), 0o644)
        copy_file(BUNDLED_LOCK_SOURCE, os.path.join(pkg, BUNDLED_LOCK_NAME), 0o644)
        for name in DOC_FILES:
            copy_file(os.path.join(DOC_DIR, name),
                      os.path.join(pkg, 'docs', name), 0o644)
        for rel in FRONTEND_FILES:
            copy_file(frontend_source(rel), os.path.join(pkg, 'frontend', *rel.split('/')), 0o644)
        for name in HELP_FILES:
            copy_file(os.path.join(HELP_DIR, name), os.path.join(pkg, 'help', name), 0o644)
        for rel in SSH2_FILES:
            copy_file(os.path.join(SSH2_SOURCE_ROOT, *rel.split('/')),
                      os.path.join(pkg, *SSH2_ROOT_REL.split('/'), *rel.split('/')), 0o644)
        python_pin, python_archive = python_runtime
        shipped = stage_python(pkg, python_archive, python_pin)
        print('PYTHON %s %s: %d files under %s/'
              % (python_pin['implementation'], python_pin['version'], shipped, PYTHON_ROOT_REL))

        files, _dirs, tree_problems = walk_tree(pkg)
        if tree_problems:
            raise ReleaseError('assembled tree is not regular: %s' % '; '.join(tree_problems))
        records = [{'path': rel, 'sha256': sha256_file(os.path.join(pkg, *rel.split('/'))),
                    'size': os.path.getsize(os.path.join(pkg, *rel.split('/')))}
                   for rel in sorted(files)]
        manifest = {
            'schema': SCHEMA,
            'version': version,
            'default_release': default if default in [m['label'] for m in releases_meta] else None,
            'releases': releases_meta,
            # Catalog copy read by bin/pseudoct for release listing and selection.
            'catalog': {'schema': 1, 'default': default, 'releases': catalog_entries},
            'source': {'commit': source[0], 'set_sha256': source[1], 'lock_sha256': source[2]},
            # The private Python runtime under python/ (one copy for all releases).
            'python': python_record(python_pin),
            'files': records,
        }
        manifest_bytes = render_manifest(manifest)
        write_bytes(os.path.join(pkg, MANIFEST_NAME), manifest_bytes)
        pairs = [(rec['path'], rec['sha256']) for rec in records]
        pairs.append((MANIFEST_NAME, sha256_bytes(manifest_bytes)))
        write_bytes(os.path.join(pkg, SUMS_NAME), render_sums(pairs))

        problems = verify_package(pkg)
        if problems:
            raise ReleaseError('assembled distribution failed validation:\n  '
                               + '\n  '.join(problems))
        lock = acquire_lock(output_dir)
        try:
            if os.path.lexists(dest):
                raise ReleaseError('destination appeared during build; not overwriting: %s' % dest)
            os.rename(pkg, dest)
        finally:
            os.unlink(lock)
        published = True
        print('PUBLISHED %s' % dest)
    finally:
        if published:
            shutil.rmtree(stage_dir, ignore_errors=True)
        else:
            workspace = preserve_workspace(stage_dir, output_dir, version)
        report_summary(version, selected, results, published, workspace, output_dir)
    return 0


def print_plan(version, selected, roots, output_dir, python_runtime):
    dest = os.path.join(output_dir, 'pseudoct-' + version)
    print('RELEASE_APPLICATION mode=dry-run version=%s releases=%s'
          % (version, ','.join(entry['label'] for entry in selected)))
    for entry in selected:
        label = entry['label']
        print('PLAN %s: %s %s' % (label, os.path.join(roots[label], 'bin', 'matlab'),
                                  ' '.join(MATLAB_FLAGS)))
        print('PLAN %s build: build_application(%s, Mode build, OutputRoot <staging>/b)'
              % (label, label))
        temp_root = os.path.join(MATLAB_TEMP_ROOT, 'pct-%s-<random>' % label)
        print('PLAN %s environment: TMPDIR=%s/t MATLAB_PREFDIR=%s/p MCR_CACHE_ROOT=%s/c'
              % (label, temp_root, temp_root, temp_root))
        if label != 'R2010b':
            print('PLAN %s static Java classpath: %s/p/javaclasspath.txt -> %s'
                  % (label, temp_root, SSH2_JAR))
        print('PLAN %s cleanup: remove only its private environment directory on exit' % label)
    print('PLAN ship: %s, %s, %s, %s, docs/ (%d files), frontend/ (%d files), help/ (%d files), %s/ (%d files), resources/, '
          'manifest.json, SHA256SUMS'
          % (LAUNCHER_REL, FRONTEND_ENTRY, README_NAME, BUNDLED_LOCK_NAME,
             len(DOC_FILES), len(FRONTEND_FILES), len(HELP_FILES),
             SSH2_ROOT_REL, len(SSH2_FILES)))
    python_pin, python_archive = python_runtime
    if os.path.isfile(python_archive):
        state = 'present (sha256 checked at build)'
    else:
        state = 'MISSING: download %s' % python_pin['url']
    print('PLAN python: %s %s from %s [%s] -> %s/, %s/ (%d texts)'
          % (python_pin['implementation'], python_pin['version'], python_archive, state,
             PYTHON_ROOT_REL, PYTHON_LICENSE_REL, len(python_pin['licenses'])))
    print('PLAN publish: %s (lock %s)' % (dest, os.path.join(output_dir, LOCK_NAME)))
    print('DRY_RUN_PASS (no MATLAB invoked, nothing written)')


def list_releases(default, ordered):
    print('RELEASES default=%s' % default)
    for entry in ordered:
        print('  %s  matlab %s  mcr %s  %s%s' % (
            entry['label'], entry['matlab_version'], entry['mcr_version'],
            entry['architecture'], '  (default)' if entry['label'] == default else ''))


# ---------------------------------------------------------------- bundled Python runtime

def load_python_pin(path=PYTHON_PIN_PATH):
    """Return the validated Python pin; its licence texts must exist in PYTHON_LICENSE_DIR."""
    try:
        with open(path, encoding='utf-8') as handle:
            pin = json.load(handle)
    except (OSError, ValueError) as exc:
        raise ReleaseError('cannot read the Python runtime pin %s: %s' % (path, exc))
    if not isinstance(pin, dict) or pin.get('schema') != 1:
        raise ReleaseError('Python runtime pin must be a JSON object with "schema": 1')
    for key in ('version', 'release', 'archive', 'archive_sha256', 'url', 'target'):
        if not isinstance(pin.get(key), str) or not pin[key]:
            raise ReleaseError('Python runtime pin field %s must be a non-empty string' % key)
    if not re.fullmatch(r'3\.[0-9]+\.[0-9]+', pin['version']):
        raise ReleaseError('Python runtime pin version must look like 3.X.Y')
    if not SHA_RE.fullmatch(pin['archive_sha256']):
        raise ReleaseError('Python runtime pin archive_sha256 must be 64 lowercase hex digits')
    if '/' in pin['archive'] or pin['target'] != PYTHON_TARGET:
        raise ReleaseError('Python runtime pin must name a %s archive file' % PYTHON_TARGET)
    licenses = pin.get('licenses')
    if (not isinstance(licenses, list) or 'LICENSE.cpython.txt' not in licenses
            or not all(isinstance(n, str) and re.fullmatch(r'LICENSE\.[A-Za-z0-9._-]+\.txt', n)
                       for n in licenses)):
        raise ReleaseError('Python runtime pin licenses must list LICENSE.<name>.txt files, '
                           'including LICENSE.cpython.txt')
    missing = [n for n in licenses if not os.path.isfile(os.path.join(PYTHON_LICENSE_DIR, n))]
    if missing:
        raise ReleaseError('Python licence texts missing from %s: %s'
                           % (PYTHON_LICENSE_DIR, ', '.join(missing)))
    return pin


def python_series(pin):
    return '.'.join(pin['version'].split('.')[:2])


def check_python_archive(path, pin):
    """Fail unless PATH is the pinned archive (sha256). Nothing is downloaded."""
    if not os.path.isfile(path):
        raise ReleaseError('bundled Python archive is missing: %s\n  download %s\n  to that path '
                           '(or pass --python-archive FILE); expected sha256 %s'
                           % (path, pin['url'], pin['archive_sha256']))
    digest = sha256_file(path)
    if digest != pin['archive_sha256']:
        raise ReleaseError('bundled Python archive %s has sha256 %s; the pin requires %s'
                           % (path, digest, pin['archive_sha256']))


def python_member_target(name, pin):
    """Package-relative path for one archive member, or None when it is not shipped."""
    series = python_series(pin)
    if name == 'python/bin/python' + series:
        return PYTHON_EXE_REL
    prefix = 'python/lib/python%s/' % series
    if not name.startswith(prefix):
        return None
    rel = name[len(prefix):]
    first = rel.split('/')[0]
    if '__pycache__' in rel.split('/'):
        # Bytecode would be stale after copying (new source times) and rewritten in place by
        # any run without -B; the launcher always runs with -B and needs none.
        return None
    if rel in PYTHON_STDLIB_KEPT:
        return name
    if first in PYTHON_STDLIB_EXCLUDED or first.startswith('config-'):
        return None
    if rel.startswith('lib-dynload/_tkinter'):
        return None
    return name


def stage_python(pkg, archive_path, pin):
    """Write the interpreter, its standard library and the licence texts under pkg/python/.
    Members are copied file by file (no extraction of links or absolute paths)."""
    shipped = 0
    have_exe = False
    try:
        with tarfile.open(archive_path, 'r:gz') as tar:
            for member in tar:
                name = member.name[2:] if member.name.startswith('./') else member.name
                if name.startswith('/') or '..' in name.split('/'):
                    raise ReleaseError('unsafe path in the Python archive: %r' % member.name)
                target = python_member_target(name, pin)
                if target is None or member.isdir():
                    continue
                if not member.isfile():
                    raise ReleaseError('Python archive member to ship is not a regular file: %s'
                                       % name)
                dest = os.path.join(pkg, *target.split('/'))
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                source = tar.extractfile(member)
                with open(dest, 'wb') as handle:
                    shutil.copyfileobj(source, handle)
                os.chmod(dest, 0o755 if (member.mode & 0o111 or target == PYTHON_EXE_REL)
                         else 0o644)
                shipped += 1
                have_exe = have_exe or target == PYTHON_EXE_REL
    except (tarfile.TarError, OSError, EOFError) as exc:
        raise ReleaseError('cannot read the Python archive %s: %s' % (archive_path, exc))
    if not have_exe:
        raise ReleaseError('the Python archive has no python/bin/python%s' % python_series(pin))
    for name in pin['licenses']:
        copy_file(os.path.join(PYTHON_LICENSE_DIR, name),
                  os.path.join(pkg, *PYTHON_LICENSE_REL.split('/'), name), 0o644)
    return shipped


def python_record(pin):
    """The manifest description of the shipped runtime."""
    return {key: pin.get(key) for key in ('implementation', 'version', 'distribution', 'release',
                                          'target', 'flavor', 'glibc_minimum', 'archive',
                                          'archive_sha256')}


def python_problems(pkg, record):
    """Run the shipped interpreter once, isolated and without the caller's environment: the
    launcher's modules must import, the version must match the manifest, and the prefix must
    be the package's own python/ folder (relocatable, no system Python involved)."""
    exe = os.path.join(pkg, *PYTHON_EXE_REL.split('/'))
    if not os.access(exe, os.X_OK):
        return ['bundled Python interpreter is not executable: %s' % PYTHON_EXE_REL]
    try:
        proc = subprocess.run([exe, '-I', '-B', '-c', PYTHON_PROBE], cwd='/',
                              env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'},
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    except (OSError, subprocess.SubprocessError) as exc:
        return ['bundled Python interpreter cannot run: %s' % exc]
    if proc.returncode != 0:
        return ['bundled Python interpreter failed its module check: %s'
                % tail(proc.stderr.decode('utf-8', 'replace'), 5)]
    try:
        found = json.loads(proc.stdout.decode('utf-8'))
    except ValueError:
        return ['bundled Python interpreter printed an unexpected module-check result']
    problems = []
    if found.get('version') != record.get('version'):
        problems.append('bundled Python is %s; the manifest records %s'
                        % (found.get('version'), record.get('version')))
    if os.path.realpath(found.get('prefix') or '') != os.path.realpath(
            os.path.join(pkg, PYTHON_ROOT_REL)):
        problems.append('bundled Python prefix %s is not the package python/ folder'
                        % found.get('prefix'))
    return problems


# ---------------------------------------------------------------- hashing and canonical text

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def write_bytes(path, data):
    with open(path, 'wb') as handle:
        handle.write(data)


def render_manifest(manifest):
    return (json.dumps(manifest, sort_keys=True, indent=2, ensure_ascii=True) + '\n').encode('ascii')


def render_sums(pairs):
    return ''.join('%s  %s\n' % (sha, rel) for rel, sha in sorted(pairs)).encode('ascii')


# ---------------------------------------------------------------- verification

def walk_tree(root):
    """Return (regular file relpaths, directory relpaths, problems)."""
    files, dirs, problems = set(), set(), []
    for dirpath, dirnames, filenames in os.walk(root):
        for name in dirnames + filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).replace(os.sep, '/')
            if os.path.islink(full):
                problems.append('symbolic link not allowed: %s' % rel)
            elif name in dirnames:
                dirs.add(rel)
            elif os.path.isfile(full):
                files.add(rel)
            else:
                problems.append('special file not allowed: %s' % rel)
    return files, dirs, problems


def forbidden(rel):
    return any(part in FORBIDDEN_PARTS for part in rel.split('/'))


def path_allowed(rel, labels):
    """The shipped allowlist: launcher, entry point, frontend files, help documents, the
    release runtime files of the listed labels, and the atlas resources."""
    if rel in (LAUNCHER_REL, FRONTEND_ENTRY, README_NAME, BUNDLED_LOCK_NAME):
        return True
    if rel.startswith('docs/') and rel[len('docs/'):] in DOC_FILES:
        return True
    if rel.startswith('frontend/') and rel[len('frontend/'):] in FRONTEND_FILES:
        return True
    if rel.startswith('help/') and rel[len('help/'):] in HELP_FILES:
        return True
    if rel.startswith(SSH2_ROOT_REL + '/') and rel[len(SSH2_ROOT_REL) + 1:] in SSH2_FILES:
        return True
    if rel.startswith(PYTHON_ROOT_REL + '/'):
        # The runtime tree is checked by its manifest hashes and by python_problems.
        return True
    parts = rel.split('/')
    if len(parts) == 2 and parts[0] == 'resources':
        return parts[1] in RESOURCE_REQUIRED or fnmatch.fnmatchcase(parts[1], RESOURCE_ATLAS_PATTERN)
    if len(parts) >= 3 and parts[0] == 'runtimes' and parts[1] in labels:
        return '/'.join(parts[2:]) in RUNTIME_FILES
    return False


def required_paths(labels):
    paths = [LAUNCHER_REL, FRONTEND_ENTRY, README_NAME, BUNDLED_LOCK_NAME]
    paths += ['docs/' + name for name in DOC_FILES]
    paths += ['frontend/' + rel for rel in FRONTEND_FILES]
    paths += ['help/' + name for name in HELP_FILES]
    paths += [SSH2_ROOT_REL + '/' + rel for rel in SSH2_FILES]
    for label in sorted(labels):
        paths += ['runtimes/%s/%s' % (label, rel) for rel in RUNTIME_FILES]
    paths += ['resources/' + name for name in RESOURCE_REQUIRED]
    paths += [PYTHON_EXE_REL, PYTHON_LICENSE_REL + '/LICENSE.cpython.txt']
    return paths


def manifest_shape_problems(manifest):
    if not isinstance(manifest, dict):
        return ['%s must be a JSON object' % MANIFEST_NAME]
    problems = []
    if manifest.get('schema') != SCHEMA:
        problems.append('unexpected manifest schema')
    if not isinstance(manifest.get('version'), str) or not VERSION_RE.fullmatch(manifest['version']):
        problems.append('invalid manifest version')
    labels = []
    releases = manifest.get('releases')
    if not isinstance(releases, list) or not releases:
        problems.append('manifest releases must be a non-empty list')
    else:
        for record in releases:
            label = record.get('label') if isinstance(record, dict) else None
            if isinstance(label, str) and LABEL_RE.fullmatch(label):
                labels.append(label)
            else:
                problems.append('invalid release record: %r' % (record,))
        if len(set(labels)) != len(labels):
            problems.append('duplicate release label in manifest')
    if manifest.get('default_release') is not None and manifest.get('default_release') not in labels:
        problems.append('default_release must be null or a built release')
    if not isinstance(manifest.get('catalog'), dict):
        problems.append('manifest catalog is missing')
    python = manifest.get('python')
    if (not isinstance(python, dict) or not isinstance(python.get('version'), str)
            or not isinstance(python.get('archive_sha256'), str)):
        problems.append('manifest python runtime record is missing or invalid')
    files = manifest.get('files')
    if not isinstance(files, list):
        problems.append('manifest files must be a list')
    else:
        paths = []
        for record in files:
            ok = (isinstance(record, dict) and isinstance(record.get('path'), str)
                  and isinstance(record.get('sha256'), str) and bool(SHA_RE.fullmatch(record['sha256']))
                  and isinstance(record.get('size'), int) and not isinstance(record.get('size'), bool)
                  and record['size'] >= 0)
            if not ok:
                problems.append('invalid file record: %r' % (record,))
            else:
                paths.append(record['path'])
        if len(set(paths)) != len(paths):
            problems.append('duplicate path in manifest files')
    return problems


def verify_package(pkg):
    """Return a list of problems; an empty list means the distribution is valid."""
    pkg = os.path.abspath(pkg)
    if not os.path.isdir(pkg):
        return ['not a directory: %s' % pkg]
    manifest_path = os.path.join(pkg, MANIFEST_NAME)
    if not os.path.isfile(manifest_path):
        return ['%s is missing' % MANIFEST_NAME]
    with open(manifest_path, 'rb') as handle:
        raw = handle.read()
    try:
        manifest = json.loads(raw.decode('utf-8'))
    except ValueError as exc:
        return ['%s is not valid JSON: %s' % (MANIFEST_NAME, exc)]
    shape = manifest_shape_problems(manifest)
    if shape:
        return shape
    problems = []
    if raw != render_manifest(manifest):
        problems.append('%s is not in canonical form' % MANIFEST_NAME)
    labels = set(record['label'] for record in manifest['releases'])
    listed = {record['path']: record for record in manifest['files']}
    files, dirs, tree_problems = walk_tree(pkg)
    problems.extend(tree_problems)
    expected_dirs = set()
    for rel in listed:
        parts = rel.split('/')
        for depth in range(1, len(parts)):
            expected_dirs.add('/'.join(parts[:depth]))
    for rel in sorted(dirs - expected_dirs):
        problems.append('unexpected directory: %s' % rel)
    for rel in sorted(files - set(listed) - {MANIFEST_NAME, SUMS_NAME}):
        if forbidden(rel):
            problems.append('forbidden path present: %s' % rel)
        else:
            problems.append('extra file not listed in manifest: %s' % rel)
    for rel in sorted(listed):
        if not path_allowed(rel, labels):
            problems.append('path outside the distribution allowlist: %s' % rel)
        if rel not in files:
            problems.append('missing file: %s' % rel)
            continue
        full = os.path.join(pkg, *rel.split('/'))
        if os.path.getsize(full) != listed[rel]['size']:
            problems.append('size mismatch: %s' % rel)
        if sha256_file(full) != listed[rel]['sha256']:
            problems.append('sha256 mismatch: %s' % rel)
    for rel in required_paths(labels):
        if rel not in listed:
            problems.append('required artifact not in manifest: %s' % rel)
    sums_path = os.path.join(pkg, SUMS_NAME)
    if not os.path.isfile(sums_path):
        problems.append('%s is missing' % SUMS_NAME)
    else:
        pairs = [(rel, sha256_file(os.path.join(pkg, *rel.split('/'))))
                 for rel in files if rel != SUMS_NAME]
        with open(sums_path, 'rb') as handle:
            if handle.read() != render_sums(pairs):
                problems.append('%s does not match the tree (checksum or inventory)' % SUMS_NAME)
    if PYTHON_EXE_REL in files:
        problems.extend(python_problems(pkg, manifest['python']))
    return problems


# ---------------------------------------------------------------- command line

def build_parser():
    parser = argparse.ArgumentParser(
        description='Assemble the pseudoCT installed distribution from verified builds.')
    parser.add_argument('--version', help='distribution version for build mode')
    parser.add_argument('--releases', help='comma-separated catalog labels (default: catalog default)')
    parser.add_argument('--matlab-root', action='append', default=[], metavar='LABEL=PATH',
                        help='MATLAB installation root for one selected release (repeatable)')
    parser.add_argument('--output', help='parent directory for pseudoct-<version>/ (default: dist/)')
    parser.add_argument('--dry-run', action='store_true',
                        help='print the planned steps; never start MATLAB or write output')
    parser.add_argument('--list-releases', action='store_true', help='print the catalog and exit')
    parser.add_argument('--verify', metavar='DIR', help='check an assembled distribution and exit')
    parser.add_argument('--python-archive', metavar='FILE',
                        help='pinned python-build-standalone archive (default: '
                             'external/python-build-standalone/<archive named in '
                             'config/python-runtime.json>)')
    return parser


def _main(argv):
    args = build_parser().parse_args(argv)
    build_options = (args.version is not None or args.releases is not None
                     or bool(args.matlab_root) or args.output is not None or args.dry_run
                     or args.python_archive is not None)
    if args.list_releases and (args.verify is not None or build_options):
        raise UsageError('--list-releases takes no other options')
    if args.verify is not None and build_options:
        raise UsageError('--verify takes no other options')
    if args.list_releases:
        default, ordered, _by_label = load_catalog(CATALOG_PATH)
        list_releases(default, ordered)
        return 0
    if args.verify is not None:
        problems = verify_package(args.verify)
        if problems:
            print('VERIFY_FAIL %s' % args.verify, file=sys.stderr)
            for problem in problems:
                print('  - %s' % problem, file=sys.stderr)
            return 1
        print('VERIFY_PASS %s' % args.verify)
        return 0

    if args.version is None:
        raise UsageError('--version is required, for example --version <VERSION>')
    if not VERSION_RE.fullmatch(args.version):
        raise UsageError('--version must match ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$')
    default, ordered, by_label = load_catalog(CATALOG_PATH)
    selected = select_releases(default, ordered, by_label, args.releases)
    roots = parse_roots(args.matlab_root, selected)
    output_dir = os.path.abspath(args.output if args.output is not None else DEFAULT_OUTPUT)
    for entry in selected:
        matlab_text(roots[entry['label']], '%s MATLAB root' % entry['label'])
        check_matlab_root(entry, roots[entry['label']])
    check_sources()
    python_pin = load_python_pin()
    python_archive = os.path.abspath(args.python_archive if args.python_archive is not None
                                     else os.path.join(PYTHON_CACHE_DIR, python_pin['archive']))
    dest = os.path.join(output_dir, 'pseudoct-' + args.version)
    if os.path.lexists(dest):
        raise ReleaseError('destination exists and will not be overwritten: %s' % dest)
    if args.dry_run:
        print_plan(args.version, selected, roots, output_dir, (python_pin, python_archive))
        return 0
    # Checked before any MATLAB build, so a missing or wrong archive fails immediately.
    check_python_archive(python_archive, python_pin)
    return assemble(args.version, selected, roots, default, ordered, output_dir,
                    (python_pin, python_archive))


def main(argv=None):
    """Run the command line (argv defaults to sys.argv[1:]) and return the exit status."""
    try:
        return _main(sys.argv[1:] if argv is None else argv)
    except UsageError as exc:
        print('release_application: usage error: %s' % exc, file=sys.stderr)
        return 2
    except (ReleaseError, OSError) as exc:
        print('release_application: error: %s' % exc, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
