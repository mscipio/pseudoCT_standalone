#!/usr/bin/env python3
"""Multi-release pseudoCT application driver and source-free assembler.

Build-host tool, Python 3 standard library only. For each selected release it
runs the MATLAB of that release exactly once, feeding one `build_application`
call on stdin in Build mode with an explicit output root under a staging
directory. It then assembles one new, filtered distribution directory:

    pseudoct-<version>/
      bin/pseudoct                                       (the only public launcher)
      run_pseudo_CT.m                                    (installed MATLAB wrapper, generated)
      runtimes/<LABEL>/app/run_pseudo_CT                 (compiled GUI/CLI)
      runtimes/<LABEL>/payload/mlsc_current_payload      (compiled payload)
      runtimes/<LABEL>/payload/run_mlsc_current_payload.sh (payload runner, copied from scripts/)
      runtimes/<LABEL>/payload/build_manifest.mat         (package-manifests output, per release)
      runtimes/<LABEL>/payload/resource_manifest.mat      (package-manifests output, per release)
      runtimes/<LABEL>/standalone/pseudoct_standalone    (compiled CLI/headless dispatcher)
      runtimes/<LABEL>/{app,payload,standalone}/*.ctf    (compiler sidecars, optional)
      resources/                                         (atlas/template files)
      manifest.json                                      (canonical, no timestamps; embeds catalog)
      SHA256SUMS                                         (sorted, includes manifest)

The default output directory is <repository>/dist/ (independent of the working
directory); --output overrides it. Publication is non-overwriting and takes an
exclusive lock file in the output directory (see docs/releases.md).

Usage:
  release_application.py --version V [--releases R2010b,R2014a,...]
      --matlab-root LABEL=PATH [--matlab-root LABEL=PATH ...]
      [--output DIR] [--dry-run]
  release_application.py --list-releases
  release_application.py --verify DIR

Exit status: 0 success, 1 build/validation/verification failure, 2 usage error.
The MATLAB root doubles as the builder's McrRoot: the catalog runtime evidence
(runtime/<arch>/libmwmclmcrrt.so.<mcr>, toolbox/compiler/mcrversion.ver) lives
under each MATLAB installation, so no separate MCR option is needed.
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
VERSION_RE = re.compile(r'[0-9A-Za-z][0-9A-Za-z._+-]{0,63}')  # use fullmatch
LABEL_RE = re.compile(r'R[0-9]{4}[ab]')  # same form build_application.m accepts
SHA_RE = re.compile(r'[0-9a-f]{64}')
MATLAB_FLAGS = ['-nodesktop', '-nosplash', '-nodisplay']
MANIFEST_NAME = 'manifest.json'
SUMS_NAME = 'SHA256SUMS'

# Compiled targets that build_application.m produces (app/, payload/, standalone/). The
# mcc-*.log files at the package root are never shipped.
BUILDER_REQUIRED = ('app/run_pseudo_CT', 'payload/mlsc_current_payload',
                    'standalone/pseudoct_standalone')
# Every installed release also carries the shell payload runner: a copy of
# scripts/run_mlsc_current_payload.sh that replaces any builder file of the same name.
RUNNER_REL = 'payload/run_mlsc_current_payload.sh'
RUNNER_SOURCE = os.path.join(REPO_ROOT, 'scripts', 'run_mlsc_current_payload.sh')
RUNTIME_REQUIRED = BUILDER_REQUIRED + (RUNNER_REL,)
# Per-release manifests written into the release payload directory by the dispatcher's
# package-manifests mode. They are the only files that step adds to the tree.
PACKAGE_MANIFEST_MODE = 'package-manifests'
PACKAGE_MANIFESTS = ('build_manifest.mat', 'resource_manifest.mat')
RELEASE_MANIFESTS = tuple('payload/' + name for name in PACKAGE_MANIFESTS)
# The single public launcher and the generated installed MATLAB wrapper.
LAUNCHER_REL = 'bin/pseudoct'
LAUNCHER_SOURCE = os.path.join(REPO_ROOT, 'bin', 'pseudoct')
WRAPPER_NAME = 'run_pseudo_CT.m'
# Exclusive lock file held in the output directory while a release is published.
LOCK_NAME = '.pseudoct-release.lock'
# Compiler sidecars: every *.ctf written directly inside a target's output directory is
# preserved next to that target. Sidecars are optional; their presence is recorded in the
# manifest and checked by --verify.
SIDECAR_DIRS = ('app', 'payload', 'standalone')
SIDECAR_SUFFIX = '.ctf'
# Resource names build_application.m copies from the atlas directory (local_atlas_names).
RESOURCE_REQUIRED = (
    'ch2.nii', 'new_segment_batch.mat', 'dartel_existing_template_batch.mat',
    'create_inverse_warped_batch.mat', 'Template_1.nii', 'Template_2.nii',
    'Template_3.nii', 'Template_4.nii', 'Template_5.nii', 'Template_6.nii')
RESOURCE_ATLAS_PATTERN = '*Atlas*.nii'
FORBIDDEN_PARTS = frozenset([
    'src', 'tests', 'tools', 'logs', 'log', 'cfggen', 'external', 'compiled',
    'build', '.git', '.partial'])
BUILDER_FIELDS = ('release', 'matlab_release', 'arch', 'compiler', 'source_commit',
                  'source_dirty', 'source_set_sha256', 'lock_sha256')
BUILDER_SCRIPT = os.path.join(REPO_ROOT, 'scripts', 'build_application.m')


class UsageError(Exception):
    """Invalid command line or selection; exit status 2."""


class ReleaseError(Exception):
    """Validation, build or verification failure; exit status 1."""


# ---------------------------------------------------------------- catalog

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


def parse_roots(pairs, selected, by_label):
    """LABEL=PATH for every selected release, exactly once, and no others."""
    selected_labels = [entry['label'] for entry in selected]
    roots = {}
    for pair in pairs:
        label, sep, path = pair.partition('=')
        if not sep or not path:
            raise UsageError('--matlab-root expects LABEL=PATH, got %r' % pair)
        if label not in by_label:
            raise UsageError('--matlab-root names unknown release %r' % label)
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


def check_sources():
    """The launcher and payload runner that every distribution ships must exist."""
    for path in (LAUNCHER_SOURCE, RUNNER_SOURCE):
        if not os.path.isfile(path):
            raise ReleaseError('required source missing from repository: %s'
                               % os.path.relpath(path, REPO_ROOT))


# ---------------------------------------------------------------- installed MATLAB wrapper

# Text of run_pseudo_CT.m at the root of an installed distribution. It is generated here
# (installed packages only; the repository run_pseudo_CT.m is not changed) and never
# references src/: it only calls the installed launcher.
# Every path placed in a shell command is passed through shell_word (POSIX single quotes), so
# $, backticks, quotes, spaces and parentheses in the install or temporary paths stay literal.
# No double quote character appears in this text. Delimiters are r""" because the helper
# contains ''' sequences.
WRAPPER_TEXT = r"""function report = run_pseudo_CT(varargin)
%RUN_PSEUDO_CT Entry point of the installed pseudoCT distribution (generated; do not edit).
%   run_pseudo_CT()            opens the pseudoCT application without blocking and returns [].
%   report = run_pseudo_CT(...) runs one orchestrated request with the installed launcher
%                              (bin/pseudoct run --orchestrate) and returns its report.
root = fileparts(mfilename('fullpath'));
launcher = shell_word(fullfile(root, 'bin', 'pseudoct'));
if ~isunix
    error('run_pseudo_CT:platform', 'The installed pseudoCT distribution runs on Linux (glnxa64) only.');
end
if nargin == 0
    status = system([launcher ' gui &']);
    if status ~= 0
        error('run_pseudo_CT:gui', 'The pseudoCT application could not be started (status %d).', status);
    end
    report = [];
    return
end
arguments = varargin;
request = [tempname '.mat'];
result = [tempname '.mat'];
cleanup = onCleanup(@() remove_temporary_files({request, result}));
save(request, 'arguments');
command = [launcher ' run --orchestrate ' shell_word(request) ' ' shell_word(result)];
[status, output] = system(command);
if status ~= 0
    error('run_pseudo_CT:failed', 'pseudoCT orchestration failed (status %d):\n%s', status, output);
end
if exist(result, 'file') ~= 2
    error('run_pseudo_CT:report', 'pseudoCT finished without writing a report.');
end
loaded = load(result, 'report');
report = loaded.report;
end

function q = shell_word(p)
%SHELL_WORD POSIX single-quoted shell word for the path p ('' inside p becomes '\'').
q = ['''' strrep(p, '''', '''\''''') ''''];
end

function remove_temporary_files(files)
for ii = 1:numel(files)
    if exist(files{ii}, 'file') == 2
        delete(files{ii});
    end
end
end
"""

# ---------------------------------------------------------------- build

def matlab_text(value, what):
    """Single-quoted MATLAB literal. Inside '...' only the quote is special (doubled);
    control characters, including newlines, are refused so one value cannot start a
    new statement."""
    if not value or any(ord(ch) < 0x20 or ord(ch) == 0x7f for ch in value):
        raise ReleaseError('%s cannot be passed to MATLAB safely: %r' % (what, value))
    return "'" + value.replace("'", "''") + "'"


def build_call(label, out_root, root):
    return ("build_application(%s, 'Mode', 'build', 'OutputRoot', %s, 'McrRoot', %s)"
            % (matlab_text(label, 'release label'),
               matlab_text(out_root, 'OutputRoot'),
               matlab_text(root, 'MATLAB root')))


def build_stdin(call):
    """Bootstrap: put the repository scripts directory (holding build_application.m) on the
    MATLAB path, run the build, and exit non-zero on any failure."""
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


def collect_resources(entry, pkg):
    label = entry['label']
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


def release_sidecars(pkg, label):
    """Relative paths (e.g. 'app/run_pseudo_CT.ctf') of every *.ctf written directly inside
    a target directory of one builder package. Non-regular entries are refused."""
    found = []
    for directory in SIDECAR_DIRS:
        dir_path = os.path.join(pkg, directory)
        if not os.path.isdir(dir_path):
            continue
        for name in sorted(os.listdir(dir_path)):
            if not name.endswith(SIDECAR_SUFFIX):
                continue
            full = os.path.join(dir_path, name)
            if os.path.islink(full) or not os.path.isfile(full):
                raise ReleaseError('%s: sidecar is not a regular file: %s/%s'
                                   % (label, directory, name))
            found.append('%s/%s' % (directory, name))
    return found


def copy_file(src, dst, mode):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    os.chmod(dst, mode)


def run_package_manifests(entry, mcr_root, work_pkg):
    """Run runtimes/<LABEL>/standalone/pseudoct_standalone in package-manifests mode:
    arguments payload_dir resources_dir output_dir, with the release's MATLAB Runtime on
    LD_LIBRARY_PATH as the runner sets it. The output directory is the release payload
    directory. The two manifests it writes are the only files this step adds."""
    label = entry['label']
    arch = entry['architecture']
    rel_dir = os.path.join(work_pkg, 'runtimes', label)
    payload = os.path.join(rel_dir, 'payload')
    exe = os.path.join(rel_dir, 'standalone', 'pseudoct_standalone')
    resources = os.path.join(work_pkg, 'resources')
    library_path = ':'.join(os.path.join(mcr_root, *part.split('/')) for part in (
        'runtime/' + arch, 'bin/' + arch, 'sys/os/' + arch))
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = library_path
    env['PSEUDOCT_RUNTIME_RELEASE'] = label
    env['PSEUDOCT_RUNTIME_MCR_VERSION'] = entry['mcr_version']  # catalog value, not MATLAB's
    env['PSEUDOCT_INSTALL_ROOT'] = work_pkg
    argv = [exe, PACKAGE_MANIFEST_MODE, payload, resources, payload]
    try:
        proc = subprocess.run(argv, env=env, cwd=os.path.dirname(work_pkg),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except OSError as exc:
        raise ReleaseError('%s: cannot start package-manifests: %s' % (label, exc))
    if proc.returncode != 0:
        raise ReleaseError('%s: package-manifests failed (exit %d); last output:\n%s'
                           % (label, proc.returncode, tail(proc.stdout.decode('utf-8', 'replace'))))
    # The staging directory is transient: no written manifest may encode it.
    staging = os.path.dirname(work_pkg).encode('utf-8')
    for name in PACKAGE_MANIFESTS:
        path = os.path.join(payload, name)
        if os.path.islink(path) or not os.path.isfile(path) or os.path.getsize(path) == 0:
            raise ReleaseError('%s: package-manifests did not write a non-empty %s'
                               % (label, name))
        with open(path, 'rb') as handle:
            if staging in handle.read():
                raise ReleaseError('%s: %s encodes the staging directory; manifests must use '
                                   'paths relative to the package' % (label, name))


def acquire_lock(output_dir):
    """Create the release lock exclusively (O_EXCL). A held or stale lock is refused, never
    removed automatically. Returns the lock path; the caller removes it."""
    path = os.path.join(output_dir, LOCK_NAME)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise ReleaseError('another release holds %s (or a stale lock remains); remove the lock '
                           'only when no release is running' % path)
    with os.fdopen(fd, 'w') as handle:
        handle.write('%d\n' % os.getpid())
    return path


def run_build(version, selected, roots, default, catalog_entries, output_dir):
    dest = os.path.join(output_dir, 'pseudoct-' + version)
    os.makedirs(output_dir, exist_ok=True)
    work = tempfile.mkdtemp(prefix='.pseudoct-%s.tmp-' % version, dir=output_dir)
    try:
        work_pkg = os.path.join(work, 'pseudoct-' + version)
        build_root = os.path.join(work, 'build')
        os.makedirs(work_pkg)
        os.makedirs(build_root)
        releases_meta = []
        source = None
        resource_src = None
        resource_digests = None
        for entry in selected:
            label = entry['label']
            root = roots[label]
            print('BUILD %s via %s' % (label, root), flush=True)
            out_root = os.path.join(build_root, label)
            os.makedirs(out_root)
            rc, text = run_matlab(root, build_stdin(build_call(label, out_root, root)), build_root)
            if rc != 0:
                raise ReleaseError('%s: MATLAB build failed (exit %d); last output:\n%s'
                                   % (label, rc, tail(text)))
            pkg = os.path.join(out_root, label)
            fields = read_builder_fields(entry, pkg)
            prov = (fields['source_commit'], fields['source_set_sha256'], fields['lock_sha256'])
            if source is None:
                source = prov
            elif prov != source:
                raise ReleaseError('%s: source provenance differs from an earlier release build'
                                   % label)
            for rel in BUILDER_REQUIRED:
                if not os.path.isfile(os.path.join(pkg, *rel.split('/'))):
                    raise ReleaseError('%s: required artifact missing: %s' % (label, rel))
            digests = collect_resources(entry, pkg)
            if resource_digests is None:
                resource_digests, resource_src = digests, pkg
            elif digests != resource_digests:
                raise ReleaseError('%s: builder resources differ from the first release' % label)
            for rel in BUILDER_REQUIRED:
                copy_file(os.path.join(pkg, *rel.split('/')),
                          os.path.join(work_pkg, 'runtimes', label, *rel.split('/')), 0o755)
            copy_file(RUNNER_SOURCE, os.path.join(work_pkg, 'runtimes', label, *RUNNER_REL.split('/')),
                      0o755)
            for sidecar in release_sidecars(pkg, label):
                copy_file(os.path.join(pkg, *sidecar.split('/')),
                          os.path.join(work_pkg, 'runtimes', label, *sidecar.split('/')), 0o644)
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
                      os.path.join(work_pkg, 'resources', name), 0o644)
        copy_file(LAUNCHER_SOURCE, os.path.join(work_pkg, *LAUNCHER_REL.split('/')), 0o755)
        wrapper_path = os.path.join(work_pkg, WRAPPER_NAME)
        write_bytes(wrapper_path, WRAPPER_TEXT.encode('ascii'))
        os.chmod(wrapper_path, 0o644)
        # Per-release package manifests, written by each release's own dispatcher under that
        # release's MATLAB Runtime. Runs after the staged runtime and resources are in place
        # and before checksums are computed, so the .mat files are inventoried and checksummed.
        for entry in selected:
            run_package_manifests(entry, roots[entry['label']], work_pkg)

        files, _dirs, tree_problems = walk_tree(work_pkg)
        if tree_problems:
            raise ReleaseError('assembled tree is not regular: %s' % '; '.join(tree_problems))
        records = [{'path': rel, 'sha256': sha256_file(os.path.join(work_pkg, *rel.split('/'))),
                    'size': os.path.getsize(os.path.join(work_pkg, *rel.split('/')))}
                   for rel in sorted(files)]
        manifest = {
            'schema': SCHEMA,
            'version': version,
            'default_release': default if default in releases_meta_labels(releases_meta) else None,
            'releases': releases_meta,
            # Catalog copy read by the installed launcher (bin/pseudoct) for release
            # listing, the default label and selection; no config/ directory is shipped.
            'catalog': {'schema': 1, 'default': default, 'releases': catalog_entries},
            'source': {'commit': source[0], 'set_sha256': source[1], 'lock_sha256': source[2]},
            'files': records,
        }
        manifest_bytes = render_manifest(manifest)
        write_bytes(os.path.join(work_pkg, MANIFEST_NAME), manifest_bytes)
        pairs = [(rec['path'], rec['sha256']) for rec in records]
        pairs.append((MANIFEST_NAME, sha256_bytes(manifest_bytes)))
        write_bytes(os.path.join(work_pkg, SUMS_NAME), render_sums(pairs))

        problems = verify_package(work_pkg)
        if problems:
            raise ReleaseError('assembled distribution failed validation:\n  '
                               + '\n  '.join(problems))
        # Publication: exclusive lock in the output directory, destination rechecked under
        # the lock, then one rename of the fully validated staging tree (same filesystem).
        lock = acquire_lock(output_dir)
        try:
            if os.path.lexists(dest):
                raise ReleaseError('destination appeared during build; not overwriting: %s' % dest)
            os.rename(work_pkg, dest)
        finally:
            os.unlink(lock)
        print('PUBLISHED %s' % dest)
        print('RELEASE_PASS version=%s releases=%s'
              % (version, ','.join(meta['label'] for meta in releases_meta)))
    finally:
        shutil.rmtree(work, ignore_errors=True)


def releases_meta_labels(releases_meta):
    return [meta['label'] for meta in releases_meta]


def print_plan(version, selected, roots, default, output_dir):
    dest = os.path.join(output_dir, 'pseudoct-' + version)
    print('RELEASE_APPLICATION mode=dry-run version=%s releases=%s'
          % (version, ','.join(entry['label'] for entry in selected)))
    for entry in selected:
        label = entry['label']
        root = roots[label]
        print('PLAN %s: %s %s' % (label, os.path.join(root, 'bin', 'matlab'),
                                  ' '.join(MATLAB_FLAGS)))
        bootstrap = build_stdin(build_call(label, '<staging>/build/' + label, root))
        print('  stdin: %s' % bootstrap.replace('\n', ' | '))
    print('PLAN launcher: %s; wrapper: %s' % (LAUNCHER_REL, WRAPPER_NAME))
    for entry in selected:
        print('PLAN %s package-manifests: runtimes/%s/standalone/pseudoct_standalone '
              'package-manifests <payload> resources <payload>' % (entry['label'], entry['label']))
    print('PLAN default_release: %s' % (default if default in [e['label'] for e in selected]
                                        else 'null'))
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
    if rel in (LAUNCHER_REL, WRAPPER_NAME):
        return True
    parts = rel.split('/')
    if len(parts) == 2 and parts[0] == 'resources':
        return parts[1] in RESOURCE_REQUIRED or fnmatch.fnmatchcase(parts[1], RESOURCE_ATLAS_PATTERN)
    if len(parts) >= 3 and parts[0] == 'runtimes' and parts[1] in labels:
        sub = '/'.join(parts[2:])
        if sub in RUNTIME_REQUIRED or sub in RELEASE_MANIFESTS:
            return True
        return (len(parts) == 4 and parts[2] in SIDECAR_DIRS
                and parts[3].endswith(SIDECAR_SUFFIX) and len(parts[3]) > len(SIDECAR_SUFFIX))
    return False


def required_paths(labels):
    paths = [LAUNCHER_REL, WRAPPER_NAME]
    for label in sorted(labels):
        paths += ['runtimes/%s/%s' % (label, rel) for rel in RUNTIME_REQUIRED + RELEASE_MANIFESTS]
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
    default = manifest.get('default_release')
    if default is not None and default not in labels:
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
        description='Build and assemble the multi-release pseudoCT application distribution.')
    parser.add_argument('--version', help='required distribution version for build mode')
    parser.add_argument('--releases', help='comma-separated catalog labels (default: catalog default)')
    parser.add_argument('--matlab-root', action='append', default=[], metavar='LABEL=PATH',
                        help='MATLAB installation root for one selected release (repeatable)')
    parser.add_argument('--output', help='parent directory for pseudoct-<version>/ (default: dist/)')
    parser.add_argument('--dry-run', action='store_true',
                        help='print planned invocations; never start MATLAB or write output')
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
        raise UsageError('--version is required, for example --version 1.0.0')
    if not VERSION_RE.fullmatch(args.version):
        raise UsageError('--version must match ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$')
    default, ordered, by_label = load_catalog(CATALOG_PATH)
    selected = select_releases(default, ordered, by_label, args.releases)
    roots = parse_roots(args.matlab_root, selected, by_label)
    output_dir = os.path.abspath(args.output if args.output is not None else DEFAULT_OUTPUT)
    matlab_text(output_dir, 'output directory')
    for entry in selected:
        matlab_text(roots[entry['label']], '%s MATLAB root' % entry['label'])
        check_matlab_root(entry, roots[entry['label']])
    check_sources()
    if not os.path.isfile(BUILDER_SCRIPT):
        raise ReleaseError('builder script missing: %s' % BUILDER_SCRIPT)
    dest = os.path.join(output_dir, 'pseudoct-' + args.version)
    if os.path.lexists(dest):
        raise ReleaseError('destination exists and will not be overwritten: %s' % dest)
    if args.dry_run:
        print_plan(args.version, selected, roots, default, output_dir)
        return 0
    run_build(args.version, selected, roots, default, ordered, output_dir)
    return 0


def main(argv=None):
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
