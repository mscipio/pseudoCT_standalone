#!/usr/bin/env python3
"""Synthetic tests for the single installed launcher bin/pseudoct.

Covers bin/pseudoct (run, headless, resolve, --list-releases; gui and --orchestrate refused)
and the installed payload runner scripts/run_mlsc_current_payload.sh.

An installed package is assembled under PSEUDOCT_TEST_SCRATCH: a copy of the real
bin/pseudoct and payload runner, the release catalog embedded in manifest.json, and
fake compiled executables under runtimes/<LABEL>/. Each fake records its argv,
LD_LIBRARY_PATH, PSEUDOCT_INSTALL_ROOT and request/result environment, and behaves per
scenario. Fake MATLAB Runtime roots carry only the identity evidence the launcher
checks. No MATLAB, mcc, science or job is run; the licensed MATLAB is unreachable
through PATH and PSEUDOCT_MATLAB.

    PSEUDOCT_TEST_SCRATCH=<executionDir> python3 -I -B -m unittest discover \
        -s tests -p 'test_standalone_release.py' -t tests -v
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(REPO, 'config', 'releases.json')
LAUNCHER_SRC = os.path.join(REPO, 'bin', 'pseudoct')
RUNNER_SRC = os.path.join(REPO, 'scripts', 'run_mlsc_current_payload.sh')
BUILT = ('R2010b', 'R2014b')
EXECUTABLES = {
    'payload': 'payload/mlsc_current_payload',
    'standalone': 'standalone/pseudoct_standalone',
}
# PATH without MATLAB: the python3 that runs the tests plus the system utilities.
SYSTEM_PATH = os.pathsep.join([os.path.dirname(sys.executable), '/usr/bin', '/bin'])
NO_MATLAB = '/nonexistent/matlab-must-not-run'

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


def build_package(root):
    """Installed layout: bin/pseudoct, payload runner, runtimes/<LABEL>/, manifest.json."""
    pkg = os.path.join(root, 'pseudoct-syn')
    os.makedirs(os.path.join(pkg, 'bin'), exist_ok=True)
    shutil.copyfile(LAUNCHER_SRC, os.path.join(pkg, 'bin', 'pseudoct'))
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
        for target, rel in EXECUTABLES.items():
            exe = os.path.join(pkg, 'runtimes', label, rel)
            write(exe, FAKE_STANDALONE if target == 'standalone' else FAKE_PLAIN)
            os.chmod(exe, 0o755)
        runner = os.path.join(pkg, 'runtimes', label, 'payload', 'run_mlsc_current_payload.sh')
        shutil.copyfile(RUNNER_SRC, runner)
        os.chmod(runner, 0o755)
    return pkg


class StandaloneTestCase(unittest.TestCase):

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix='standalone-', dir=scratch_base())
        self.home = os.path.join(self.base, 'home')
        os.makedirs(self.home)
        self.log = os.path.join(self.base, 'fake-invocations.log')
        self.pkg = build_package(os.path.join(self.base, 'install'))
        self.pkg_real = os.path.realpath(self.pkg)
        self.root = {label: make_runtime(os.path.join(self.base, 'mcr', label), label)
                     for label in BUILT}
        self.root_real = {label: os.path.realpath(path) for label, path in self.root.items()}
        self.launcher = os.path.join(self.pkg, 'bin', 'pseudoct')

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
        """Fake executable calls in order: dicts keyed by EXE, ARGS, LD, ROOT, REQ, RES."""
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
        os.remove(os.path.join(self.pkg, 'runtimes', 'R2014b', 'payload', 'mlsc_current_payload'))
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
            os.path.join(self.pkg_real, 'runtimes', 'R2014b', 'payload', 'run_mlsc_current_payload.sh'),
            self.pkg_real, 'R2014b', self.root_real['R2014b']]))
        for env, expected in (
                ({'PSEUDOCT_MCR_ROOT_R2014b': env_root, 'PSEUDOCT_MCR_ROOT': env_plain}, env_root),
                ({'PSEUDOCT_MCR_ROOT': env_plain}, env_plain)):
            rc, out, err = self.pseudoct(['resolve', '--mcr', 'R2014b'], env=env)
            self.assertEqual(rc, 0, err)
            self.assertIn("PSEUDOCT_MCR_ROOT='%s'" % os.path.realpath(expected), out)
            self.assertIn("PSEUDOCT_RUNTIME_MCR_ROOT='%s'" % os.path.realpath(expected), out)
        rc, _out, err = self.pseudoct(['resolve', '--mcr', 'R2014b'], env={})
        self.assertEqual(rc, 69, err)
        self.assertIn('no MATLAB Runtime root', err)
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
        rc, out, err = self.pseudoct(['run', '--mcr', 'R2010b', '--mcr-root', self.root['R2010b'],
                                      'validate', '--profile', 'local', '--mprage', mprage,
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
        rc, _out, err = self.pseudoct(['run', '--mcr', 'R2010b', 'validate', '--profile', 'local',
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
        runner = os.path.join(self.pkg, 'runtimes', 'R2010b', 'payload', 'run_mlsc_current_payload.sh')
        rc, _out, err = self.run_cmd([runner, self.root_real['R2010b'], 'phase', 'job.txt', 'res.txt'],
                                     env={})
        self.assertEqual(rc, 0, err)
        calls = self.invocations()
        self.assertEqual(calls[-1]['EXE'], self.exe('R2010b', 'payload'))
        self.assertEqual(calls[-1]['ARGS'], 'phase job.txt res.txt')
        self.assertEqual(calls[-1]['LD'], self.ld_for(self.root_real['R2010b']))
        rc, _out, err = self.run_cmd([runner, self.root_real['R2010b'], 'phase', 'job.txt'], env={})
        self.assertEqual(rc, 2, err)


if __name__ == '__main__':
    unittest.main()
