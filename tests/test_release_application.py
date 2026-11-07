#!/usr/bin/env python3
"""Synthetic tests for scripts/release_application.py (release driver and assembler).

Fake MATLAB roots are shell scripts that record each invocation and create the
compiled outputs build_application would produce. No MATLAB, mcc or scientific
job is run. Fixtures and outputs live under PSEUDOCT_TEST_SCRATCH (the allocated
scratch execution directory) or .aria/scratch/unplanned/ when that variable is
unset. Nothing is written into the repository tree. Run from the repository root:

    python3 -I -B -m unittest discover -s tests -p test_release_application.py -t tests -v
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DRIVER = os.path.join(REPO, 'scripts', 'release_application.py')
VERSION = '1.0.0-syn'
DIST = 'pseudoct-' + VERSION
SYNTHETIC_ATLAS = 'Synthetic_Atlas.nii'

FAKE_MATLAB = r'''#!/bin/sh
# Test fixture standing in for <MATLAB root>/bin/matlab. It records one
# invocation, reads the build command from stdin and writes synthetic outputs.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CMD=$(cat)
{
  printf 'INVOKE %s\n' "$*"
  printf 'STDIN %s\n' "$CMD"
} >> "$ROOT/invocations.log"
REL=$(printf '%s\n' "$CMD" | sed -n "s/.*build_application('\(R[0-9][0-9][0-9][0-9][ab]\)'.*/\1/p")
OUT=$(printf '%s\n' "$CMD" | sed -n "s/.*'OutputRoot', '\([^']*\)'.*/\1/p")
MREL=$(printf '%s' "$REL" | sed 's/^R//')
if [ -e "$ROOT/FAIL_BUILD" ]; then echo "fake MATLAB: build failed on purpose"; exit 1; fi
PKG="$OUT/$REL"
mkdir -p "$PKG/app" "$PKG/payload" "$PKG/standalone" "$PKG/resources" "$PKG/src/cli" "$PKG/tests" "$PKG/cfggen"
echo "synthetic compiled application $REL" > "$PKG/app/run_pseudo_CT"
echo "synthetic compiler sidecar $REL" > "$PKG/app/run_pseudo_CT.ctf"
echo "synthetic mcc log" > "$PKG/mcc-app.log"
if [ ! -e "$ROOT/SKIP_STANDALONE" ]; then
cat > "$PKG/standalone/pseudoct_standalone" <<DISPATCH
#!/bin/sh
# Synthetic dispatcher: package-manifests records argv and environment, then writes
# two placeholder manifests into its output directory (fourth argument).
case "\$1" in
  package-manifests)
    [ ! -e "$ROOT/FAIL_MANIFEST" ] || exit 1
    {
      printf 'ARGV %s\n' "\$*"
      printf 'LD %s\n' "\${LD_LIBRARY_PATH-}"
      printf 'RELEASE %s\n' "\${PSEUDOCT_RUNTIME_RELEASE-}"
      printf 'ROOT %s\n' "\${PSEUDOCT_INSTALL_ROOT-}"
      printf 'MCR %s\n' "\${PSEUDOCT_RUNTIME_MCR_VERSION-}"
    } >> "$ROOT/package-manifest-calls.log"
    if [ -e "$ROOT/EMBED_STAGING" ]; then
      printf 'staged at %s\n' "\$4" > "\$4/build_manifest.mat"
    else
      printf 'synthetic build manifest\n' > "\$4/build_manifest.mat"
    fi
    printf 'synthetic resource manifest\n' > "\$4/resource_manifest.mat"
    ;;
esac
exit 0
DISPATCH
chmod 755 "$PKG/standalone/pseudoct_standalone"
fi
echo "synthetic compiler sidecar standalone $REL" > "$PKG/standalone/pseudoct_standalone.ctf"
echo "synthetic exclusion list" > "$PKG/app/mccExcludedFiles.log"
echo "interpreted source must not ship" > "$PKG/src/cli/pseudoct_headless_cli_r2010b.m"
echo "test must not ship" > "$PKG/tests/test_unit.py"
echo "generated helper must not ship" > "$PKG/cfggen/cfg_mlbatch_appcfg_1.m"
echo "synthetic compiled payload $REL" > "$PKG/payload/mlsc_current_payload"
for n in ch2.nii new_segment_batch.mat dartel_existing_template_batch.mat create_inverse_warped_batch.mat Template_1.nii Template_2.nii Template_3.nii Template_4.nii Template_5.nii Template_6.nii Synthetic_Atlas.nii; do
  echo "synthetic resource $n" > "$PKG/resources/$n"
done
cat > "$PKG/application_manifest.txt" <<EOF
schema pseudo-CT.application-package/v1
release $REL
matlab_version synthetic
matlab_release $MREL
compiler MATLAB Compiler synthetic
arch glnxa64
source_commit 0123456789abcdef0123456789abcdef01234567
source_dirty 0
source_set_sha256 1111111111111111111111111111111111111111111111111111111111111111
lock_sha256 2222222222222222222222222222222222222222222222222222222222222222
mcr_root $ROOT
mcc_app mcc -m /abs/run_pseudo_CT.m -d /abs/stage/app
build_timestamp_utc 2026-01-01T00:00:00Z
file_count 3
inventory_file SHA256SUMS
EOF
echo "synthetic builder inventory" > "$PKG/SHA256SUMS"
exit 0
'''

LABEL_A = 'R2010b'
LABEL_B = 'R2014a'


def scratch_base():
    base = os.environ.get('PSEUDOCT_TEST_SCRATCH')
    if not base:
        stamp = time.strftime('%Y%m%d-%H%M%S')
        base = os.path.join(REPO, '.aria', 'scratch', 'unplanned', stamp + '-release-application-tests')
    os.makedirs(base, exist_ok=True)
    return base


# PATH for shell checks: the python3 running the tests plus the system utilities.
SYSTEM_PATH = os.pathsep.join([os.path.dirname(sys.executable), '/usr/bin', '/bin'])


def shell_word(path):
    """The quoting rule of the generated wrapper's shell_word, evaluated in Python:
    close the single quote, emit an escaped quote, reopen."""
    return "'" + path.replace("'", "'\\''") + "'"


def read_bytes(path):
    with open(path, 'rb') as handle:
        return handle.read()


def load_driver():
    spec = importlib.util.spec_from_file_location('release_application', DRIVER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


DRV = load_driver()
DEFAULT_LABEL, ORDERED, BY_LABEL = DRV.load_catalog(DRV.CATALOG_PATH)


class ReleaseApplicationTests(unittest.TestCase):

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix='release-app-', dir=scratch_base())
        self.output = os.path.join(self.base, 'out')
        self.roots = {label: self.make_root(label) for label in (LABEL_A, LABEL_B)}

    def make_root(self, label):
        entry = BY_LABEL[label]
        root = os.path.join(self.base, 'matlab', label)
        os.makedirs(os.path.join(root, 'bin'))
        os.makedirs(os.path.join(root, 'runtime', entry['architecture']))
        os.makedirs(os.path.join(root, 'toolbox', 'compiler'))
        matlab = os.path.join(root, 'bin', 'matlab')
        with open(matlab, 'w') as handle:
            handle.write(FAKE_MATLAB)
        os.chmod(matlab, 0o755)
        with open(os.path.join(root, 'runtime', entry['architecture'],
                               entry['runtime_identity']['library']), 'w') as handle:
            handle.write('synthetic runtime library\n')
        with open(os.path.join(root, 'toolbox', 'compiler', 'mcrversion.ver'), 'w') as handle:
            handle.write(entry['mcr_version'] + '\n')
        return root

    def run_driver(self, args, cwd=REPO):
        proc = subprocess.run([sys.executable, '-I', DRIVER] + args, cwd=cwd,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return proc.returncode, proc.stdout.decode('utf-8'), proc.stderr.decode('utf-8')

    def build_args(self, output=None, labels=(LABEL_A, LABEL_B)):
        args = ['--output', output or self.output, '--version', VERSION,
                '--releases', ','.join(labels)]
        for label in labels:
            args += ['--matlab-root', '%s=%s' % (label, self.roots[label])]
        return args

    def build(self, output=None, labels=(LABEL_A, LABEL_B)):
        return self.run_driver(self.build_args(output, labels))

    def invocations(self, label):
        path = os.path.join(self.roots[label], 'invocations.log')
        if not os.path.exists(path):
            return []
        with open(path) as handle:
            return [line for line in handle.read().splitlines() if line.startswith('INVOKE ')]

    def published(self, output=None):
        return os.path.join(output or self.output, DIST)

    def walk_files(self, root):
        found = set()
        for dirpath, _dirs, filenames in os.walk(root):
            for name in filenames:
                full = os.path.join(dirpath, name)
                found.add(os.path.relpath(full, root).replace(os.sep, '/'))
        return found

    def expected_inventory(self):
        rels = {'bin/pseudoct', 'run_pseudo_CT.m', 'manifest.json', 'SHA256SUMS'}
        for label in (LABEL_A, LABEL_B):
            rels |= {'runtimes/%s/app/run_pseudo_CT' % label,
                     'runtimes/%s/app/run_pseudo_CT.ctf' % label,
                     'runtimes/%s/payload/mlsc_current_payload' % label,
                     'runtimes/%s/payload/run_mlsc_current_payload.sh' % label,
                     'runtimes/%s/payload/build_manifest.mat' % label,
                     'runtimes/%s/payload/resource_manifest.mat' % label,
                     'runtimes/%s/standalone/pseudoct_standalone' % label,
                     'runtimes/%s/standalone/pseudoct_standalone.ctf' % label}
        rels |= {'resources/' + name for name in DRV.RESOURCE_REQUIRED + (SYNTHETIC_ATLAS,)}
        return rels

    # ---------------------------------------------------------------- tests

    def test_list_releases_needs_no_matlab(self):
        rc, out, _err = self.run_driver(['--list-releases'])
        self.assertEqual(rc, 0, out)
        self.assertIn('RELEASES default=R2010b', out)
        self.assertIn('R2010b  matlab 7.11  mcr 7.14  glnxa64  (default)', out)
        self.assertTrue(all(self.invocations(label) == [] for label in self.roots))

    def test_default_output_is_repository_dist_regardless_of_cwd(self):
        args = ['--version', VERSION, '--dry-run', '--matlab-root',
                '%s=%s' % (LABEL_A, self.roots[LABEL_A])]
        rc, out, err = self.run_driver(args, cwd=self.base)
        self.assertEqual(rc, 0, err)
        self.assertIn('PLAN publish: ' + os.path.join(REPO, 'dist', DIST), out)
        self.assertEqual(self.invocations(LABEL_A), [])

    def test_build_publishes_single_launcher_layout(self):
        rc, out, err = self.build()
        self.assertEqual(rc, 0, err + out)
        pkg = self.published()
        self.assertEqual(self.walk_files(pkg), self.expected_inventory())
        self.assertEqual(read_bytes(os.path.join(pkg, 'bin', 'pseudoct')),
                         read_bytes(DRV.LAUNCHER_SOURCE))
        for label in (LABEL_A, LABEL_B):
            self.assertEqual(read_bytes(os.path.join(pkg, 'runtimes', label, 'payload',
                                                     'run_mlsc_current_payload.sh')),
                             read_bytes(DRV.RUNNER_SOURCE))
        with open(os.path.join(pkg, 'manifest.json'), encoding='utf-8') as handle:
            manifest = handle.read()
        self.assertIn('"default": "R2010b"', manifest)
        self.assertIn('"catalog"', manifest)
        vrc, vout, verr = self.run_driver(['--verify', pkg])
        self.assertEqual(vrc, 0, vout + verr)
        self.assertIn('VERIFY_PASS', vout)

    def package_manifest_calls(self, label):
        path = os.path.join(self.roots[label], 'package-manifest-calls.log')
        if not os.path.exists(path):
            return []
        records = []
        with open(path) as handle:
            for line in handle.read().splitlines():
                key, _, value = line.partition(' ')
                if key == 'ARGV':
                    records.append({})
                records[-1][key] = value
        return records

    def test_package_manifests_run_once_per_release_and_are_checksummed(self):
        rc, _out, err = self.build()
        self.assertEqual(rc, 0, err)
        pkg = self.published()
        with open(os.path.join(pkg, 'manifest.json'), encoding='utf-8') as handle:
            listed = {record['path']: record['sha256'] for record in json.load(handle)['files']}
        with open(os.path.join(pkg, 'SHA256SUMS'), encoding='ascii') as handle:
            sums = set(handle.read().splitlines())
        for label in (LABEL_A, LABEL_B):
            root = self.roots[label]
            calls = self.package_manifest_calls(label)
            self.assertEqual(len(calls), 1, calls)
            argv = calls[0]['ARGV'].split(' ')
            self.assertEqual(argv[0], 'package-manifests')
            self.assertTrue(argv[1].endswith('/runtimes/%s/payload' % label), argv)
            self.assertTrue(argv[2].endswith('/resources'), argv)
            self.assertEqual(argv[3], argv[1])
            self.assertEqual(calls[0]['LD'], '%s/runtime/glnxa64:%s/bin/glnxa64:%s/sys/os/glnxa64'
                             % (root, root, root))
            self.assertEqual(calls[0]['RELEASE'], label)
            self.assertEqual(calls[0]['MCR'], BY_LABEL[label]['mcr_version'])
            if label == LABEL_A:
                self.assertEqual(calls[0]['MCR'], '7.14')
            for name in DRV.PACKAGE_MANIFESTS:
                rel = 'runtimes/%s/payload/%s' % (label, name)
                full = os.path.join(pkg, *rel.split('/'))
                self.assertTrue(os.path.isfile(full) and os.path.getsize(full) > 0, rel)
                digest = DRV.sha256_file(full)
                self.assertEqual(listed.get(rel), digest, rel)
                self.assertIn('%s  %s' % (digest, rel), sums)

    def test_package_manifest_failure_publishes_nothing(self):
        open(os.path.join(self.roots[LABEL_B], 'FAIL_MANIFEST'), 'w').close()
        rc, _out, err = self.build()
        self.assertEqual(rc, 1, err)
        self.assertIn('package-manifests failed', err)
        self.assertFalse(os.path.exists(self.published()))
        self.assertEqual(os.listdir(self.output), [])

    def test_published_tree_encodes_no_staging_path(self):
        rc, _out, err = self.build()
        self.assertEqual(rc, 0, err)
        pkg = self.published()
        needles = [self.output.encode('utf-8'), ('.pseudoct-%s.tmp-' % VERSION).encode('ascii')]
        for rel in sorted(self.walk_files(pkg)):
            with open(os.path.join(pkg, *rel.split('/')), 'rb') as handle:
                data = handle.read()
            for needle in needles:
                self.assertNotIn(needle, data, rel)

    def test_manifest_embedding_the_staging_path_publishes_nothing(self):
        open(os.path.join(self.roots[LABEL_B], 'EMBED_STAGING'), 'w').close()
        rc, _out, err = self.build()
        self.assertEqual(rc, 1, err)
        self.assertIn('encodes the staging directory', err)
        self.assertFalse(os.path.exists(self.published()))
        self.assertEqual(os.listdir(self.output), [])

    def test_wrapper_quotes_every_shell_path_and_contains_no_double_quote(self):
        text = DRV.WRAPPER_TEXT
        self.assertNotIn('"', text)
        self.assertIn(r"q = ['''' strrep(p, '''', '''\''''') '''']", text)
        self.assertIn('launcher = shell_word(fullfile(root', text)
        self.assertIn('shell_word(request) \' \' shell_word(result)', text)

    def test_shell_word_rule_round_trips_hostile_paths(self):
        hostile = '$HOME/`id`/$(id) "dq" it\'s a path'
        proc = subprocess.run(['sh', '-c', 'printf %s ' + shell_word(hostile)],
                              env={'PATH': SYSTEM_PATH, 'HOME': '/nonexistent-home'},
                              stdout=subprocess.PIPE, check=True)
        self.assertEqual(proc.stdout.decode('utf-8'), hostile)

    def test_wrapper_command_reaches_the_launcher_with_hostile_paths(self):
        hostile_dir = os.path.join(self.base, 'inst $HOME `id` $(echo nope) "dq" it\'s sp')
        os.makedirs(os.path.join(hostile_dir, 'bin'))
        launcher = os.path.join(hostile_dir, 'bin', 'pseudoct')
        with open(launcher, 'w') as handle:
            handle.write('#!/bin/sh\nfor a in "$@"; do printf "%s\\n" "$a"; done '
                         '> "$PSEUDOCT_FAKE_ARGV"\n')
        os.chmod(launcher, 0o755)
        request = os.path.join(hostile_dir, 'req $(id).mat')
        result = os.path.join(hostile_dir, 'res `id`.mat')
        argv_file = os.path.join(self.base, 'argv.txt')
        command = (shell_word(launcher) + ' run --orchestrate ' + shell_word(request)
                   + ' ' + shell_word(result))
        subprocess.run(['sh', '-c', command],
                       env={'PATH': SYSTEM_PATH, 'HOME': '/nonexistent-home',
                            'PSEUDOCT_FAKE_ARGV': argv_file}, check=True)
        with open(argv_file, encoding='utf-8') as handle:
            self.assertEqual(handle.read().splitlines(),
                             ['run', '--orchestrate', request, result])

    def test_generated_wrapper_has_gui_branch_and_no_src_reference(self):
        rc, _out, err = self.build()
        self.assertEqual(rc, 0, err)
        with open(os.path.join(self.published(), 'run_pseudo_CT.m'), encoding='ascii') as handle:
            text = handle.read()
        self.assertTrue(text.startswith('function report = run_pseudo_CT(varargin)'))
        self.assertIn('nargin == 0', text)
        self.assertIn("' gui &'", text)
        self.assertIn("run --orchestrate", text)
        self.assertNotIn('src', text)
        self.assertNotIn('addpath', text)

    def test_existing_destination_is_refused_and_not_overwritten(self):
        os.makedirs(self.published())
        marker = os.path.join(self.published(), 'keep.txt')
        with open(marker, 'w') as handle:
            handle.write('earlier release\n')
        rc, _out, err = self.build()
        self.assertEqual(rc, 1, err)
        self.assertIn('not be overwritten', err)
        self.assertTrue(os.path.isfile(marker))
        self.assertEqual(self.invocations(LABEL_A), [])

    def test_publication_lock_is_exclusive_and_not_removed_when_foreign(self):
        os.makedirs(self.output)
        lock = os.path.join(self.output, DRV.LOCK_NAME)
        with open(lock, 'w') as handle:
            handle.write('999999\n')
        rc, _out, err = self.build()
        self.assertEqual(rc, 1, err)
        self.assertIn('holds', err)
        self.assertFalse(os.path.exists(self.published()))
        self.assertTrue(os.path.isfile(lock))

    def test_failed_or_incomplete_build_publishes_nothing_and_releases_no_lock(self):
        open(os.path.join(self.roots[LABEL_B], 'FAIL_BUILD'), 'w').close()
        rc, _out, err = self.build()
        self.assertEqual(rc, 1, err)
        self.assertFalse(os.path.exists(self.published()))
        self.assertEqual(sorted(os.listdir(self.output)), [])
        os.remove(os.path.join(self.roots[LABEL_B], 'FAIL_BUILD'))
        open(os.path.join(self.roots[LABEL_B], 'SKIP_STANDALONE'), 'w').close()
        rc, _out, err = self.build()
        self.assertEqual(rc, 1, err)
        self.assertIn('pseudoct_standalone', err)
        self.assertFalse(os.path.exists(self.published()))
        self.assertEqual(sorted(os.listdir(self.output)), [])

    def test_verify_detects_corruption_and_forbidden_content(self):
        rc, _out, err = self.build()
        self.assertEqual(rc, 0, err)
        pkg = self.published()
        launcher = os.path.join(pkg, 'bin', 'pseudoct')
        with open(launcher, 'rb') as handle:
            original = handle.read()
        with open(launcher, 'ab') as handle:
            handle.write(b'# tampered\n')
        rc, _out, err = self.run_driver(['--verify', pkg])
        self.assertEqual(rc, 1)
        self.assertIn('sha256 mismatch: bin/pseudoct', err)
        with open(launcher, 'wb') as handle:
            handle.write(original)
        os.makedirs(os.path.join(pkg, 'src'))
        with open(os.path.join(pkg, 'src', 'x.m'), 'w') as handle:
            handle.write('% forbidden\n')
        rc, _out, err = self.run_driver(['--verify', pkg])
        self.assertEqual(rc, 1)
        self.assertIn('forbidden path present: src/x.m', err)


if __name__ == '__main__':
    unittest.main()
