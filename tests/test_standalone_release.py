#!/usr/bin/env python3
"""Synthetic tests for the single installed launcher bin/pseudoct.

Covers bin/pseudoct (run, headless, resolve, --list-releases; gui and --orchestrate refused)
and the runner (source scripts/run_pseudoct_pipeline.sh, installed as
runtimes/<LABEL>/run_pseudoct_pipeline.sh).

An installed package is assembled under PSEUDOCT_TEST_SCRATCH: a copy of the real
bin/pseudoct and runner, the release catalog embedded in manifest.json, and
fake compiled executables under runtimes/<LABEL>/. Each fake records its argv,
LD_LIBRARY_PATH, PSEUDOCT_INSTALL_ROOT and request/result environment, and behaves per
scenario. Fake MATLAB Runtime roots carry only the identity evidence the launcher
checks. No MATLAB, mcc, science or job is run; the licensed MATLAB is unreachable
through PATH and PSEUDOCT_MATLAB.

The launcher's fixed catalog base /usr/pubsw/common/matlab is replaced, in the test copy
only, by a synthetic directory under the scratch base, so no test depends on the real
/usr/pubsw tree. The production launcher is checked to define that base exactly once.
The resolution table (release, matlab_version, D, scenario, result) is written to
mcr-resolution-table.tsv in the scratch base.

    PSEUDOCT_TEST_SCRATCH=<executionDir> python3 -I -B -m unittest discover \
        -s tests -p 'test_standalone_release.py' -t tests -v
"""

import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(REPO, 'config', 'releases.json')
LAUNCHER_SRC = os.path.join(REPO, 'bin', 'pseudoct')
RUNNER_SRC = os.path.join(REPO, 'scripts', 'run_pseudoct_pipeline.sh')
BUILT = ('R2010b', 'R2014b')
EXECUTABLES = {
    'payload': 'pseudoct_pipeline',
    'standalone': 'pseudoct_job_manager',
}
# PATH without MATLAB: the python3 that runs the tests plus the system utilities.
SYSTEM_PATH = os.pathsep.join([os.path.dirname(sys.executable), '/usr/bin', '/bin'])
NO_MATLAB = '/nonexistent/matlab-must-not-run'
PRODUCTION_CATALOG_BASE = '/usr/pubsw/common/matlab'
BASE_LINE = 'catalog_mcr_base=' + PRODUCTION_CATALOG_BASE
# Releases whose catalog directory is checked: the R2010b default and the five named
# full-build entries. D is the first two dotted components of matlab_version.
MULTI = ('R2010b', 'R2019a', 'R2019b', 'R2022a', 'R2022b', 'R2026a')
EXPECTED_DIR = {'R2010b': '7.11', 'R2019a': '9.6', 'R2019b': '9.7',
                'R2022a': '9.12', 'R2022b': '9.13', 'R2026a': '26.1'}
RESOLUTION = []

FAKE_RECORD = r'''{
  printf 'EXE %s\n' "$0"
  printf 'ARGS %s\n' "$*"
  printf 'LD %s\n' "${LD_LIBRARY_PATH-}"
  printf 'ROOT %s\n' "${PSEUDOCT_INSTALL_ROOT-}"
  printf 'RELEASE %s\n' "${PSEUDOCT_RUNTIME_RELEASE-}"
  printf 'MCR_ROOT %s\n' "${PSEUDOCT_RUNTIME_MCR_ROOT-}"
  printf 'REQ %s\n' "${PSEUDOCT_REQUEST_MAT-}"
  printf 'RES %s\n' "${PSEUDOCT_RESULT_MAT-}"
} >> "$PSEUDOCT_FAKE_LOG"
'''

FAKE_PLAIN = '#!/bin/sh\n' + FAKE_RECORD + 'exit 0\n'

FAKE_STANDALONE = '#!/bin/sh\n' + FAKE_RECORD + r'''scenario=${PSEUDOCT_FAKE_SCENARIO:-ok}
case "$1" in
  prepare_validate|prepare_submit)
    printf 'synthetic request\n' > "$PSEUDOCT_CLI_REQUEST" ;;
  verify_result)
    printf 'ready\n-\nnot_required\nnot_attempted\nlocal\nnot_run\nnot_dispatched\n-\nvalidate\n-\n' > "$PSEUDOCT_CLI_SUMMARY" ;;
  headless)
    printf 'synthetic result\n' > "$PSEUDOCT_RESULT_MAT" ;;
esac
exit 0
'''

def scratch_base():
    base = os.environ.get('PSEUDOCT_TEST_SCRATCH')
    if not base:
        stamp = time.strftime('%Y%m%d-%H%M%S')
        base = os.path.join(REPO, '.aria', 'scratch', 'unplanned', stamp + '-standalone-release-tests')
    os.makedirs(base, exist_ok=True)
    return base


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as handle:
        handle.write(text)


def load_catalog():
    with open(CATALOG_PATH, encoding='utf-8') as handle:
        return json.load(handle)


CATALOG = load_catalog()
BY_LABEL = {entry['label']: entry for entry in CATALOG['releases']}
DEFAULT = CATALOG['default']


def make_runtime(path, label, version=None):
    """Fake MATLAB Runtime root holding only the identity evidence (no real library)."""
    entry = BY_LABEL[label]
    os.makedirs(os.path.join(path, 'runtime', 'glnxa64'), exist_ok=True)
    os.makedirs(os.path.join(path, 'bin', 'glnxa64'), exist_ok=True)
    os.makedirs(os.path.join(path, 'sys', 'os', 'glnxa64'), exist_ok=True)
    write(os.path.join(path, 'runtime', 'glnxa64', entry['runtime_identity']['library']),
          'synthetic runtime library\n')
    write(os.path.join(path, 'toolbox', 'compiler', 'mcrversion.ver'),
          (version or entry['mcr_version']) + '\n')
    return path


def catalog_dir(label):
    """Expected MATLAB Runtime directory name: first two dotted components of matlab_version."""
    return '.'.join(BY_LABEL[label]['matlab_version'].split('.')[:2])


def synthetic_launcher(catalog_base):
    """bin/pseudoct text with only its fixed catalog base replaced by a synthetic directory."""
    with open(LAUNCHER_SRC, encoding='utf-8') as handle:
        lines = handle.read().split('\n')
    found = [index for index, line in enumerate(lines) if line == BASE_LINE]
    if len(found) != 1:
        raise AssertionError('bin/pseudoct must define its catalog base exactly once')
    lines[found[0]] = 'catalog_mcr_base=' + shlex.quote(catalog_base)
    return '\n'.join(lines)


def install_release(pkg, label):
    """Complete installed release: the two flat executables and the runner."""
    for target, rel in EXECUTABLES.items():
        exe = os.path.join(pkg, 'runtimes', label, rel)
        write(exe, FAKE_STANDALONE if target == 'standalone' else FAKE_PLAIN)
        os.chmod(exe, 0o755)
    runner = os.path.join(pkg, 'runtimes', label, 'run_pseudoct_pipeline.sh')
    shutil.copyfile(RUNNER_SRC, runner)
    os.chmod(runner, 0o755)


def build_package(root, catalog_base):
    """Installed layout: bin/pseudoct, runtimes/<LABEL>/ (flat), manifest.json."""
    pkg = os.path.join(root, 'pseudoct-syn')
    os.makedirs(os.path.join(pkg, 'bin'), exist_ok=True)
    write(os.path.join(pkg, 'bin', 'pseudoct'), synthetic_launcher(catalog_base))
    os.chmod(os.path.join(pkg, 'bin', 'pseudoct'), 0o755)
    manifest = {
        'schema': 'pseudo-CT.release-distribution/v1',
        'version': 'syn',
        'default_release': DEFAULT,
        'catalog': CATALOG,
        'releases': [{'label': label} for label in BUILT],
        'files': [],
    }
    write(os.path.join(pkg, 'manifest.json'), json.dumps(manifest, sort_keys=True, indent=2) + '\n')
    for label in BUILT:
        install_release(pkg, label)
    return pkg


def tearDownModule():
    table = os.path.join(scratch_base(), 'mcr-resolution-table.tsv')
    with open(table, 'w', encoding='utf-8') as handle:
        handle.write('release\tmatlab_version\tD\tscenario\tresult\n')
        for row in RESOLUTION:
            handle.write('\t'.join(row) + '\n')


class StandaloneTestCase(unittest.TestCase):

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix='standalone-', dir=scratch_base())
        self.home = os.path.join(self.base, 'home')
        os.makedirs(self.home)
        self.log = os.path.join(self.base, 'fake-invocations.log')
        self.catalog_base = os.path.join(self.base, 'catalog-matlab')
        self.pkg = build_package(os.path.join(self.base, 'install'), self.catalog_base)
        self.pkg_real = os.path.realpath(self.pkg)
        self.root = {label: make_runtime(os.path.join(self.base, 'mcr', label), label)
                     for label in BUILT}
        self.root_real = {label: os.path.realpath(path) for label, path in self.root.items()}
        self.launcher = os.path.join(self.pkg, 'bin', 'pseudoct')

    def candidate(self, label):
        """Catalog location of a release in the synthetic catalog base."""
        return os.path.join(self.catalog_base, EXPECTED_DIR[label])

    def run_cmd(self, argv, env=None, cwd=None):
        base_env = {'PATH': SYSTEM_PATH, 'HOME': self.home, 'LANG': 'C', 'LC_ALL': 'C',
                    'PSEUDOCT_FAKE_LOG': self.log, 'PSEUDOCT_MATLAB': NO_MATLAB}
        base_env.update(env or {})
        proc = subprocess.run(argv, cwd=cwd or self.base, env=base_env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240)
        return proc.returncode, proc.stdout.decode('utf-8', 'replace'), proc.stderr.decode('utf-8', 'replace')

    def pseudoct(self, args, env=None, cwd=None, launcher=None):
        return self.run_cmd([launcher or self.launcher] + args, env=env, cwd=cwd)

    def invocations(self):
        """Fake calls in order: dicts keyed by EXE, ARGS, LD, ROOT, RELEASE, MCR_ROOT, REQ, RES."""
        records = []
        if not os.path.exists(self.log):
            return records
        with open(self.log, encoding='utf-8') as handle:
            for line in handle.read().splitlines():
                key, _, value = line.partition(' ')
                if key == 'EXE':
                    records.append({'EXE': value})
                elif records:
                    records[-1][key] = value
        return records

    def exe(self, label, target):
        return os.path.join(self.pkg_real, 'runtimes', label, EXECUTABLES[target])

    @staticmethod
    def ld_for(root):
        return '%s/runtime/glnxa64:%s/bin/glnxa64:%s/sys/os/glnxa64' % (root, root, root)

    def assert_single_call(self, label, target, root_real, args):
        calls = self.invocations()
        self.assertEqual(len(calls), 1, calls)
        self.assertEqual(calls[0]['EXE'], self.exe(label, target))
        self.assertEqual(calls[0].get('ARGS', ''), args)
        self.assertEqual(calls[0]['LD'], self.ld_for(root_real))
        self.assertEqual(calls[0]['ROOT'], self.pkg_real)
        self.assertEqual(calls[0]['RELEASE'], label)
        self.assertEqual(calls[0]['MCR_ROOT'], root_real)
        return calls[0]

    def subject(self):
        """Subject MR folder with an MR_PET/tmp target and a readable MPRAGE input."""
        mprage = os.path.join(self.base, 'subject', 'MR', 'mprage.nii')
        write(mprage, 'synthetic input\n')
        os.makedirs(os.path.join(self.base, 'subject', 'MR_PET', 'tmp'), exist_ok=True)
        return mprage

    # ---------------------------------------------------------------- tests

    def test_list_releases_prints_only_complete_installed_releases(self):
        rc, out, err = self.pseudoct(['--list-releases'], env={})
        self.assertEqual(rc, 0, err)
        self.assertEqual(out.splitlines(), ['R2010b\t7.14\tdefault', 'R2014b\t8.4\t-'])
        self.assertEqual(self.invocations(), [])
        os.remove(os.path.join(self.pkg, 'runtimes', 'R2014b', 'pseudoct_pipeline'))
        rc, out, _err = self.pseudoct(['--list-releases'], env={})
        self.assertEqual(rc, 0)
        self.assertEqual(out.splitlines(), ['R2010b\t7.14\tdefault'])
        rc, out, _err = self.pseudoct(['--help'], env={})
        self.assertEqual(rc, 0)
        self.assertIn('pseudoct run', out)
        self.assertNotIn('gui', out)
        self.assertNotIn('--orchestrate', out)

    def test_removed_gui_and_orchestrate_modes_are_refused_without_invocation(self):
        for args in (['gui'], ['gui', '--mcr', 'R2014b'],
                     ['run', '--orchestrate', 'request.mat', 'report.mat']):
            rc, _out, err = self.pseudoct(args, env={})
            self.assertEqual(rc, 64, err)
        self.assertEqual(self.invocations(), [])

    def test_resolve_prints_sourceable_lines_with_root_precedence(self):
        env_root = os.path.join(self.base, 'mcr-env-label')
        make_runtime(env_root, 'R2014b')
        env_plain = os.path.join(self.base, 'mcr-env-plain')
        make_runtime(env_plain, 'R2014b')
        rc, out, err = self.pseudoct(['resolve', '--mcr', 'R2014b', '--mcr-root', self.root['R2014b']],
                                     env={'PSEUDOCT_MCR_ROOT_R2014b': env_root,
                                          'PSEUDOCT_MCR_ROOT': env_plain})
        self.assertEqual(rc, 0, err)
        sourced = subprocess.run(
            ['sh', '-c', 'eval "$1"; printf "%s|%s|%s|%s|%s|%s" "$PSEUDOCT_EXE" "$PSEUDOCT_MCR_ROOT" '
                         '"$PSEUDOCT_RUNNER" "$PSEUDOCT_INSTALL_ROOT" "$PSEUDOCT_RUNTIME_RELEASE" "$PSEUDOCT_RUNTIME_MCR_ROOT"',
             'sh', out], stdout=subprocess.PIPE, check=True).stdout.decode()
        self.assertEqual(sourced, '|'.join([
            self.exe('R2014b', 'standalone'), self.root_real['R2014b'],
            os.path.join(self.pkg_real, 'runtimes', 'R2014b', 'run_pseudoct_pipeline.sh'),
            self.pkg_real, 'R2014b', self.root_real['R2014b']]))
        # Environment variables never select a root: without --mcr-root the only
        # candidate is the catalog location <base>/8.4 (R2014b), here synthetic.
        conventional = make_runtime(os.path.join(self.catalog_base, '8.4'), 'R2014b')
        rc, out, err = self.pseudoct(['resolve', '--mcr', 'R2014b'],
                                     env={'PSEUDOCT_MCR_ROOT_R2014b': env_root,
                                          'PSEUDOCT_MCR_ROOT': env_plain})
        self.assertEqual(rc, 0, err)
        for decoy in (env_root, env_plain):
            self.assertNotIn(os.path.realpath(decoy), out)
        self.assertIn("PSEUDOCT_MCR_ROOT='%s'" % os.path.realpath(conventional), out)
        self.assertEqual(self.invocations(), [])

    def test_resolve_rejects_mismatch_absent_and_unknown_releases(self):
        bad = make_runtime(os.path.join(self.base, 'mcr-bad'), 'R2014b', version='9.9')
        rc, _out, err = self.pseudoct(['resolve', '--mcr', 'R2014b', '--mcr-root', bad], env={})
        self.assertEqual(rc, 69, err)
        self.assertIn("reports MCR '9.9'", err)
        rc, _out, err = self.pseudoct(['resolve', '--mcr', 'R2019a', '--mcr-root', bad], env={})
        self.assertEqual(rc, 69, err)
        self.assertIn('incomplete', err)
        rc, _out, err = self.pseudoct(['resolve', '--mcr', 'R1999z', '--mcr-root', bad], env={})
        self.assertEqual(rc, 64, err)
        self.assertIn('unknown or missing release label', err)

    def test_headless_two_argument_contract_and_selection(self):
        self.subject()
        request = os.path.join(self.base, 'subject', 'MR_PET', 'tmp', 'request.mat')
        result = os.path.join(self.base, 'subject', 'MR_PET', 'tmp', 'result.mat')
        write(request, 'synthetic request mat\n')
        env_label = os.path.join(self.base, 'mcr-conflicting-label')
        make_runtime(env_label, 'R2014b')
        env_global = os.path.join(self.base, 'mcr-conflicting-global')
        make_runtime(env_global, 'R2014b')
        rc, _out, err = self.pseudoct(['headless', '--mcr', 'R2014b', '--mcr-root',
                                       self.root['R2014b'], request, result],
                                      env={'PSEUDOCT_MCR_ROOT_R2014b': env_label,
                                           'PSEUDOCT_MCR_ROOT': env_global})
        self.assertEqual(rc, 0, err)
        call = self.assert_single_call('R2014b', 'standalone', self.root_real['R2014b'], 'headless')
        # The exported environment binds the selected release, not the catalog default.
        self.assertEqual(call['RELEASE'], 'R2014b')
        self.assertNotEqual(call['RELEASE'], DEFAULT)
        self.assertEqual(call['MCR_ROOT'], self.root_real['R2014b'])
        self.assertEqual(call['ROOT'], self.pkg_real)
        self.assertEqual(call['REQ'], os.path.realpath(request))
        self.assertEqual(call['RES'], os.path.realpath(result))
        self.assertTrue(os.path.getsize(result) > 0)
        rc, _out, err = self.pseudoct(['headless', request], env={})
        self.assertEqual(rc, 64, err)

    def test_cli_validate_jsonl_runs_through_selected_release(self):
        mprage = self.subject()
        rc, out, err = self.pseudoct(['validate', '--mcr', 'R2010b', '--mcr-root', self.root['R2010b'],
                                      '--profile', 'local', '--mprage', mprage,
                                      '--format', 'jsonl'], env={})
        self.assertEqual(rc, 0, out + err)
        record = json.loads(out.strip().splitlines()[-1])
        self.assertEqual(record['outcome'], 'validation_succeeded')
        self.assertEqual(record['exit_code'], 0)
        calls = self.invocations()
        self.assertEqual([c.get('ARGS') for c in calls], ['prepare_validate', 'headless', 'verify_result'])
        self.assertEqual(calls[1]['LD'], self.ld_for(self.root_real['R2010b']))
        self.assertEqual(calls[1]['RELEASE'], 'R2010b')
        self.assertEqual(calls[1]['ROOT'], self.pkg_real)

    def test_repository_layout_rejects_selection_and_installed_operations(self):
        repo = os.path.join(self.base, 'repo')
        os.makedirs(os.path.join(repo, 'bin'))
        os.makedirs(os.path.join(repo, 'src'))
        launcher = os.path.join(repo, 'bin', 'pseudoct')
        shutil.copyfile(LAUNCHER_SRC, launcher)
        os.chmod(launcher, 0o755)
        mprage = self.subject()
        rc, _out, err = self.pseudoct(['validate', '--mcr', 'R2010b', '--profile', 'local',
                                       '--mprage', mprage], env={}, launcher=launcher)
        self.assertEqual(rc, 64, err)
        for args in (['resolve'], ['gui'], ['run', '--orchestrate', mprage, mprage + '.out']):
            rc, _out, err = self.pseudoct(args, env={}, launcher=launcher)
            self.assertEqual(rc, 64, err)
        self.assertEqual(self.invocations(), [])

    def test_symlinked_launcher_selects_the_package_of_its_real_location(self):
        links = os.path.join(self.base, 'links')
        os.makedirs(links)
        os.symlink(self.launcher, os.path.join(links, 'pseudoct'))
        direct_rc, direct_out, _err = self.pseudoct(['--list-releases'], env={})
        rc, out, err = self.pseudoct(['--list-releases'], env={},
                                     launcher=os.path.join(links, 'pseudoct'))
        self.assertEqual(rc, 0, err)
        self.assertEqual(direct_rc, 0)
        self.assertEqual(out, direct_out)
        self.assertEqual(out.splitlines(), ['R2010b\t7.14\tdefault', 'R2014b\t8.4\t-'])

    def test_payload_runner_execs_compiled_payload_with_its_runtime(self):
        runner = os.path.join(self.pkg, 'runtimes', 'R2010b', 'run_pseudoct_pipeline.sh')
        rc, _out, err = self.run_cmd([runner, self.root_real['R2010b'], 'job.txt', 'res.txt'],
                                     env={})
        self.assertEqual(rc, 0, err)
        calls = self.invocations()
        self.assertEqual(calls[-1]['EXE'], self.exe('R2010b', 'payload'))
        self.assertEqual(calls[-1]['ARGS'], 'job.txt res.txt')
        self.assertEqual(calls[-1]['LD'], self.ld_for(self.root_real['R2010b']))
        # Installed direct mode: the resource manifest argument is optional.
        rc, _out, err = self.run_cmd([runner, self.root_real['R2010b'], 'job.txt'], env={})
        self.assertEqual(rc, 0, err)
        self.assertEqual(self.invocations()[-1]['ARGS'], 'job.txt')
        rc, _out, err = self.run_cmd([runner, self.root_real['R2010b']], env={})
        self.assertEqual(rc, 2, err)

    def test_jvm_directories_join_the_library_path_only_when_present(self):
        # MCR 7.14 libjvm.so lives under sys/java/.../amd64/server. The launcher and the
        # payload runner append the amd64 and amd64/server directories only when present.
        label = 'R2010b'
        root = self.root_real[label]
        jre = os.path.join(root, 'sys', 'java', 'jre', 'glnxa64', 'jre', 'lib', 'amd64')
        server = os.path.join(jre, 'server')
        self.subject()  # creates the MR_PET/tmp folder that holds the request and result
        request = os.path.join(self.base, 'subject', 'MR_PET', 'tmp', 'request.mat')
        result = os.path.join(self.base, 'subject', 'MR_PET', 'tmp', 'result.mat')
        write(request, 'synthetic request mat\n')
        runner = os.path.join(self.pkg, 'runtimes', label, 'run_pseudoct_pipeline.sh')

        def launcher_ld():
            rc, _out, err = self.pseudoct(['headless', '--mcr', label, '--mcr-root', root,
                                           request, result], env={})
            self.assertEqual(rc, 0, err)
            return self.invocations()[-1]['LD']

        def runner_ld():
            rc, _out, err = self.run_cmd([runner, root, 'job.txt'], env={})
            self.assertEqual(rc, 0, err)
            return self.invocations()[-1]['LD']

        self.assertFalse(os.path.exists(server))
        self.assertEqual(launcher_ld(), self.ld_for(root))
        self.assertEqual(runner_ld(), self.ld_for(root))
        os.makedirs(server)
        expected = self.ld_for(root) + ':' + jre + ':' + server
        self.assertEqual(launcher_ld(), expected)
        self.assertEqual(runner_ld(), expected)

    def test_cli_validate_and_run_reach_the_same_packaged_standalone_engine(self):
        # The MATLAB GUI sends these same validate / run argv through the packaged
        # launcher (tests/test_frontend_launch.m); here the CLI must reach the same engine.
        mprage = self.subject()
        expected_exe = self.exe('R2010b', 'standalone')
        cases = (('validate', ['prepare_validate', 'headless', 'verify_result']),
                 ('run', ['prepare_validate', 'headless', 'verify_result',
                          'prepare_submit', 'headless', 'verify_result']))
        for action, phases in cases:
            if os.path.exists(self.log):
                os.remove(self.log)
            rc, out, err = self.pseudoct([action, '--mcr', 'R2010b', '--mcr-root', self.root['R2010b'],
                                          '--profile', 'local', '--mprage', mprage,
                                          '--format', 'jsonl'], env={})
            self.assertEqual(rc, 0, out + err)
            calls = self.invocations()
            self.assertEqual([c.get('ARGS') for c in calls], phases, action)
            for call in calls:
                self.assertEqual(call['EXE'], expected_exe, action)
                self.assertEqual(call['ROOT'], self.pkg_real, action)
                self.assertEqual(call['RELEASE'], 'R2010b', action)

    def test_incomplete_installation_fails_closed_without_source_fallback(self):
        shutil.rmtree(os.path.join(self.pkg, 'runtimes'))
        mprage = self.subject()
        rc, _out, err = self.pseudoct(['validate', '--profile', 'local', '--mprage', mprage],
                                      env={})
        self.assertEqual(rc, 69, err)
        self.assertIn('incomplete', err)
        self.assertIn('reinstall', err)
        self.assertNotIn('PSEUDOCT_LAUNCHER', err)
        self.assertNotIn('MATLAB', err)
        rc, _out, err = self.pseudoct(['--list-releases'], env={})
        self.assertEqual(rc, 69, err)
        self.assertEqual(self.invocations(), [])

    def test_installed_launcher_never_runs_a_launcher_from_the_environment(self):
        # Installed roots always use their bundled engine: a PSEUDOCT_LAUNCHER sentinel
        # must not run, and the bundled release executable is the one invoked.
        marker = os.path.join(self.base, 'alternate-launcher-ran')
        alternate = os.path.join(self.base, 'alternate-pseudoct')
        write(alternate, '#!/bin/sh\n: > "%s"\nexit 0\n' % marker)
        os.chmod(alternate, 0o755)
        mprage = self.subject()
        rc, out, err = self.pseudoct(['validate', '--mcr', 'R2010b', '--mcr-root', self.root['R2010b'],
                                      '--profile', 'local', '--mprage', mprage,
                                      '--format', 'jsonl'], env={'PSEUDOCT_LAUNCHER': alternate})
        self.assertEqual(rc, 0, out + err)
        self.assertFalse(os.path.exists(marker), 'PSEUDOCT_LAUNCHER ran in an installed root')
        self.assertEqual(self.invocations()[-1]['EXE'], self.exe('R2010b', 'standalone'))

    # ------------------------------------------- catalog MCR discovery (A-002, T010)

    def test_production_launcher_defines_the_fixed_catalog_base_once(self):
        with open(LAUNCHER_SRC, encoding='utf-8') as handle:
            self.assertEqual(handle.read().split('\n').count(BASE_LINE), 1)

    def test_each_named_release_resolves_from_its_first_two_components(self):
        for label in MULTI:
            with self.subTest(label=label):
                self.assertEqual(catalog_dir(label), EXPECTED_DIR[label])
                install_release(self.pkg, label)
                candidate = make_runtime(self.candidate(label), label)
                rc, out, err = self.pseudoct(['resolve', '--mcr', label], env={})
                self.assertEqual(rc, 0, err)
                self.assertIn("PSEUDOCT_MCR_ROOT='%s'" % os.path.realpath(candidate), out)
                RESOLUTION.append((label, BY_LABEL[label]['matlab_version'], EXPECTED_DIR[label],
                                   'candidate present, identity valid',
                                   'resolved ' + os.path.realpath(candidate)))

    def test_resolved_candidate_reaches_the_selected_engine(self):
        label = 'R2026a'
        install_release(self.pkg, label)
        candidate = make_runtime(self.candidate(label), label)
        self.subject()
        request = os.path.join(self.base, 'subject', 'MR_PET', 'tmp', 'request.mat')
        result = os.path.join(self.base, 'subject', 'MR_PET', 'tmp', 'result.mat')
        write(request, 'synthetic request mat\n')
        rc, _out, err = self.pseudoct(['headless', '--mcr', label, request, result], env={})
        self.assertEqual(rc, 0, err)
        self.assert_single_call(label, 'standalone', os.path.realpath(candidate), 'headless')

    def test_absent_candidate_fails_actionably_for_every_named_release(self):
        for label in MULTI:
            with self.subTest(label=label):
                install_release(self.pkg, label)
                rc, _out, err = self.pseudoct(['resolve', '--mcr', label], env={})
                self.assertEqual(rc, 69, err)
                self.assertIn('no MATLAB Runtime root for %s' % label, err)
                self.assertIn('%s is not a directory' % self.candidate(label), err)
                self.assertIn('--mcr-root', err)
                RESOLUTION.append((label, BY_LABEL[label]['matlab_version'], EXPECTED_DIR[label],
                                   'candidate absent', 'rc 69, names candidate and --mcr-root'))
        self.assertEqual(self.invocations(), [])

    def test_full_build_string_directory_is_never_the_candidate(self):
        label = 'R2019a'
        install_release(self.pkg, label)
        make_runtime(os.path.join(self.catalog_base, '9.6.0.1072779'), label)
        rc, _out, err = self.pseudoct(['resolve', '--mcr', label], env={})
        self.assertEqual(rc, 69, err)
        self.assertIn('%s is not a directory' % self.candidate(label), err)
        RESOLUTION.append((label, BY_LABEL[label]['matlab_version'], EXPECTED_DIR[label],
                           'full-build directory present, D absent',
                           'rc 69; full-build directory ignored'))

    def test_identity_mismatch_and_missing_library_fail_closed_for_every_release(self):
        for label in MULTI:
            with self.subTest(label=label):
                install_release(self.pkg, label)
                entry = BY_LABEL[label]
                library = entry['runtime_identity']['library']
                make_runtime(self.candidate(label), label, version='0.0')
                rc, _out, err = self.pseudoct(['resolve', '--mcr', label], env={})
                self.assertEqual(rc, 69, err)
                self.assertIn("reports MCR '0.0'", err)
                self.assertIn("%s requires '%s'" % (label, entry['mcr_version']), err)
                self.assertIn('--mcr-root', err)
                RESOLUTION.append((label, entry['matlab_version'], EXPECTED_DIR[label],
                                   'identity mismatch (mcrversion.ver 0.0)',
                                   'rc 69, names MCR and --mcr-root'))
                shutil.rmtree(self.candidate(label))
                make_runtime(self.candidate(label), label)
                os.remove(os.path.join(self.candidate(label), 'runtime', 'glnxa64', library))
                rc, _out, err = self.pseudoct(['resolve', '--mcr', label], env={})
                self.assertEqual(rc, 69, err)
                self.assertIn('runtime library %s not found' % library, err)
                self.assertIn('--mcr-root', err)
                RESOLUTION.append((label, entry['matlab_version'], EXPECTED_DIR[label],
                                   'identity library absent',
                                   'rc 69, names missing library and --mcr-root'))
                shutil.rmtree(self.candidate(label))

    def test_explicit_mcr_root_takes_precedence_over_the_candidate(self):
        label = 'R2022b'
        install_release(self.pkg, label)
        candidate = make_runtime(self.candidate(label), label)
        explicit = make_runtime(os.path.join(self.base, 'mcr-explicit-2022b'), label)
        rc, out, err = self.pseudoct(['resolve', '--mcr', label, '--mcr-root', explicit], env={})
        self.assertEqual(rc, 0, err)
        self.assertIn("PSEUDOCT_MCR_ROOT='%s'" % os.path.realpath(explicit), out)
        self.assertNotIn(os.path.realpath(candidate), out)
        RESOLUTION.append((label, BY_LABEL[label]['matlab_version'], EXPECTED_DIR[label],
                           'candidate valid, explicit --mcr-root', 'explicit root selected'))
        bad = make_runtime(os.path.join(self.base, 'mcr-explicit-bad-2022b'), label, version='9.9')
        rc, _out, err = self.pseudoct(['resolve', '--mcr', label, '--mcr-root', bad], env={})
        self.assertEqual(rc, 69, err)
        self.assertIn("reports MCR '9.9'", err)
        RESOLUTION.append((label, BY_LABEL[label]['matlab_version'], EXPECTED_DIR[label],
                           'candidate valid, explicit --mcr-root with wrong identity',
                           'rc 69; candidate not substituted'))


if __name__ == '__main__':
    unittest.main()
