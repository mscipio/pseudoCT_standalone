#!/usr/bin/env python3
"""pseudoCT installed-distribution assembler (build host; Python 3 standard library only).

For each selected catalog release it runs that release's MATLAB exactly once with
one build_application call (Mode 'build') into a short staging directory. It then
assembles one distribution directory from the verified build output only:

    pseudoct-<version>/
      bin/pseudoct                                  (the public launcher, copied)
      run_pseudo_CT.m                               (MATLAB frontend, copied)
      frontend/<allowlisted files>                  (MATLAB frontend, copied verbatim)
      help/index.html, help/style.css               (help documents from docs/help/;
                                                     docs/help/assets/ is never shipped)
      external/ssh2_v2_m1_r5/<SSH2_FILES>           (Ganymed JAR and licence notices;
                                                     no loose SSH2 .m wrappers)
      runtimes/<LABEL>/pseudoct_pipeline              (compiled science pipeline)
      runtimes/<LABEL>/run_pseudoct_pipeline.sh       (runner, copied)
      runtimes/<LABEL>/pseudoct_job_manager          (compiled job manager)
      resources/                                    (atlas and template files)
      manifest.json                                 (catalog copy read by bin/pseudoct)
      SHA256SUMS                                    (inventory, includes the manifest)

No src/ tree, science source or other external/ content is shipped, except the frontend
files copied from src/ (FRONTEND_FROM_SRC) and the SSH2 JAR and licence notices (SSH2_FILES).
--verify refuses any file outside this allowlist.
Publication is non-overwriting and takes an exclusive lock file in the output directory.

Environment (set before running; passed through to MATLAB):
  TMPDIR, MATLAB_PREFDIR, MCR_CACHE_ROOT    keep these short (see docs/releases.md).

Usage:
  release_application.py --version V [--releases R2010b,R2014b,...]
      --matlab-root LABEL=PATH [--matlab-root LABEL=PATH ...] [--output DIR] [--dry-run]
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
FRONTEND_DIR = os.path.join(REPO_ROOT, 'frontend')
# Frontend files whose single source is frontend/ (check_sources requires the directory
# to hold exactly these files). The credential store and the password dialog are shared
# with the compiled CLI and the lifecycle, so they are shipped from src/ instead.
FRONTEND_OWN = (
    'load_mr_4_AC.fig', 'load_mr_4_AC.m', 'pseudo_CT_discover_umap.m',
    'pseudo_CT_gui_args.m', 'pseudo_CT_gui_state.m', 'pseudo_CT_launch_request.m',
    'pseudo_CT_prepare_profile_choices.m', 'pseudo_CT_prepare_routine_profile_choices.m',
    'pseudo_CT_profile_choices.m', 'pseudo_CT_profile_selector.m',
    'pseudo_CT_profile_selector_label.m', 'pseudo_CT_profile_selector_layout.m',
    'pseudo_CT_result_fields.py', 'pseudo_CT_select_file.m')
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
    for path in (LAUNCHER_SOURCE, RUNNER_SOURCE, FRONTEND_ENTRY_SOURCE, BUILDER_SCRIPT,
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


def run_matlab(root, stdin_text, cwd):
    argv = [os.path.join(root, 'bin', 'matlab')] + MATLAB_FLAGS
    try:
        proc = subprocess.run(argv, input=stdin_text.encode('utf-8'),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=cwd)
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


def assemble(version, selected, roots, default, catalog_entries, output_dir):
    """Build each selected release, assemble and verify pseudoct-<version>/, then publish it."""
    dest = os.path.join(output_dir, 'pseudoct-' + version)
    os.makedirs(output_dir, exist_ok=True)
    # Short staging directory inside the output directory; removed on exit.
    stage_dir = tempfile.mkdtemp(prefix='.s', dir=output_dir)
    try:
        pkg = os.path.join(stage_dir, 'p')
        build_root = os.path.join(stage_dir, 'b')
        os.makedirs(pkg)
        os.makedirs(build_root)
        releases_meta = []
        source = None
        resource_src = None
        resource_digests = None
        for entry in selected:
            label = entry['label']
            root = roots[label]
            out_root = os.path.join(build_root, label)
            stage_exe = os.path.join(out_root + '.partial', 'standalone', 'pseudoct_job_manager')
            if len(stage_exe) > MAX_STAGE_PATH:
                raise ReleaseError('%s: staged executable path is %d characters (limit %d); '
                                   'choose a shorter --output' % (label, len(stage_exe),
                                                                  MAX_STAGE_PATH))
            os.makedirs(out_root)
            print('BUILD %s via %s' % (label, root), flush=True)
            rc, text = run_matlab(root, build_stdin(build_call(label, out_root, root)), stage_dir)
            if rc != 0:
                raise ReleaseError('%s: MATLAB build failed (exit %d); last output:\n%s'
                                   % (label, rc, tail(text)))
            built = os.path.join(out_root, label)
            fields = read_builder_fields(entry, built)
            prov = (fields['source_commit'], fields['source_set_sha256'], fields['lock_sha256'])
            if source is None:
                source = prov
            elif prov != source:
                raise ReleaseError('%s: source provenance differs from an earlier release build'
                                   % label)
            for staged, _installed in BUILDER_TARGETS:
                if not os.path.isfile(os.path.join(built, *staged.split('/'))):
                    raise ReleaseError('%s: required executable missing: %s' % (label, staged))
            digests = collect_resources(label, built)
            if resource_digests is None:
                resource_digests, resource_src = digests, built
            elif digests != resource_digests:
                raise ReleaseError('%s: builder resources differ from the first release' % label)
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
        for name in sorted(resource_digests):
            copy_file(os.path.join(resource_src, 'resources', name),
                      os.path.join(pkg, 'resources', name), 0o644)
        copy_file(LAUNCHER_SOURCE, os.path.join(pkg, *LAUNCHER_REL.split('/')), 0o755)
        copy_file(FRONTEND_ENTRY_SOURCE, os.path.join(pkg, FRONTEND_ENTRY), 0o644)
        for rel in FRONTEND_FILES:
            copy_file(frontend_source(rel), os.path.join(pkg, 'frontend', *rel.split('/')), 0o644)
        for name in HELP_FILES:
            copy_file(os.path.join(HELP_DIR, name), os.path.join(pkg, 'help', name), 0o644)
        for rel in SSH2_FILES:
            copy_file(os.path.join(SSH2_SOURCE_ROOT, *rel.split('/')),
                      os.path.join(pkg, *SSH2_ROOT_REL.split('/'), *rel.split('/')), 0o644)

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
        print('PUBLISHED %s' % dest)
        print('RELEASE_PASS version=%s releases=%s'
              % (version, ','.join(meta['label'] for meta in releases_meta)))
    finally:
        shutil.rmtree(stage_dir, ignore_errors=True)


def print_plan(version, selected, roots, output_dir):
    dest = os.path.join(output_dir, 'pseudoct-' + version)
    print('RELEASE_APPLICATION mode=dry-run version=%s releases=%s'
          % (version, ','.join(entry['label'] for entry in selected)))
    for entry in selected:
        label = entry['label']
        print('PLAN %s: %s %s' % (label, os.path.join(roots[label], 'bin', 'matlab'),
                                  ' '.join(MATLAB_FLAGS)))
        print('PLAN %s build: build_application(%s, Mode build, OutputRoot <staging>/b)'
              % (label, label))
    print('PLAN ship: %s, %s, frontend/ (%d files), help/ (%d files), %s/ (%d files), resources/, '
          'manifest.json, SHA256SUMS'
          % (LAUNCHER_REL, FRONTEND_ENTRY, len(FRONTEND_FILES), len(HELP_FILES),
             SSH2_ROOT_REL, len(SSH2_FILES)))
    print('PLAN publish: %s (lock %s)' % (dest, os.path.join(output_dir, LOCK_NAME)))
    print('DRY_RUN_PASS (no MATLAB invoked, nothing written)')


def list_releases(default, ordered):
    print('RELEASES default=%s' % default)
    for entry in ordered:
        print('  %s  matlab %s  mcr %s  %s%s' % (
            entry['label'], entry['matlab_version'], entry['mcr_version'],
            entry['architecture'], '  (default)' if entry['label'] == default else ''))


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
    if rel in (LAUNCHER_REL, FRONTEND_ENTRY):
        return True
    if rel.startswith('frontend/') and rel[len('frontend/'):] in FRONTEND_FILES:
        return True
    if rel.startswith('help/') and rel[len('help/'):] in HELP_FILES:
        return True
    if rel.startswith(SSH2_ROOT_REL + '/') and rel[len(SSH2_ROOT_REL) + 1:] in SSH2_FILES:
        return True
    parts = rel.split('/')
    if len(parts) == 2 and parts[0] == 'resources':
        return parts[1] in RESOURCE_REQUIRED or fnmatch.fnmatchcase(parts[1], RESOURCE_ATLAS_PATTERN)
    if len(parts) >= 3 and parts[0] == 'runtimes' and parts[1] in labels:
        return '/'.join(parts[2:]) in RUNTIME_FILES
    return False


def required_paths(labels):
    paths = [LAUNCHER_REL, FRONTEND_ENTRY]
    paths += ['frontend/' + rel for rel in FRONTEND_FILES]
    paths += ['help/' + name for name in HELP_FILES]
    paths += [SSH2_ROOT_REL + '/' + rel for rel in SSH2_FILES]
    for label in sorted(labels):
        paths += ['runtimes/%s/%s' % (label, rel) for rel in RUNTIME_FILES]
    paths += ['resources/' + name for name in RESOURCE_REQUIRED]
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
    return parser


def _main(argv):
    args = build_parser().parse_args(argv)
    build_options = (args.version is not None or args.releases is not None
                     or bool(args.matlab_root) or args.output is not None or args.dry_run)
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
    dest = os.path.join(output_dir, 'pseudoct-' + args.version)
    if os.path.lexists(dest):
        raise ReleaseError('destination exists and will not be overwritten: %s' % dest)
    if args.dry_run:
        print_plan(args.version, selected, roots, output_dir)
        return 0
    assemble(args.version, selected, roots, default, ordered, output_dir)
    return 0


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
