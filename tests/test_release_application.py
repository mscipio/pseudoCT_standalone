#!/usr/bin/env python3
"""Focused tests for scripts/release_application.py (no MATLAB, no compiler).

Covers the catalog and release selection, the frontend allowlist against the real
repository frontend/ directory, the --verify contract on a synthetic package (valid,
tampered, and forbidden additions), and the dry-run plan.

    PSEUDOCT_TEST_SCRATCH=<dir> python3 -I -B -m unittest discover \\
        -s tests -p 'test_release_application.py' -t tests -v
"""

import contextlib
import io
import json
import os
import shutil
import stat
import sys
import tempfile
import time
import unittest
from unittest import mock

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, 'scripts'))
import release_application as ra  # noqa: E402


def scratch_base():
    base = os.environ.get('PSEUDOCT_TEST_SCRATCH')
    if not base:
        base = os.path.join(REPO, '.aria', 'scratch', 'unplanned',
                            time.strftime('%Y%m%d-%H%M%S') + '-release-tests')
    os.makedirs(base, exist_ok=True)
    return base


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


# Test fixture only: the caller passes this explicit synthetic version. It is not a
# pseudoCT package version and the repository does not choose one.
FIXTURE_VERSION = '0.0.0-test'


def make_package(root, labels=('R2010b',), *, version):
    """A synthetic package with every required path and a consistent manifest and sums."""
    pkg = os.path.join(root, 'pseudoct-' + version)
    for rel in ra.required_paths(labels):
        write(os.path.join(pkg, *rel.split('/')), 'synthetic ' + rel + '\n')
    files = []
    for dirpath, _dirs, names in os.walk(pkg):
        for name in names:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, pkg).replace(os.sep, '/')
            files.append({'path': rel, 'sha256': ra.sha256_file(full),
                          'size': os.path.getsize(full)})
    catalog_entries = [e for e in ra.load_catalog(ra.CATALOG_PATH)[1]
                       if e['label'] in labels]
    manifest = {
        'schema': ra.SCHEMA, 'version': version, 'default_release': labels[0],
        'releases': [{'label': label} for label in labels],
        'catalog': {'schema': 1, 'default': labels[0], 'releases': catalog_entries},
        'source': {'commit': 'x', 'set_sha256': 'x', 'lock_sha256': 'x'},
        'files': sorted(files, key=lambda record: record['path']),
    }
    manifest_bytes = ra.render_manifest(manifest)
    ra.write_bytes(os.path.join(pkg, ra.MANIFEST_NAME), manifest_bytes)
    pairs = [(record['path'], record['sha256']) for record in manifest['files']]
    pairs.append((ra.MANIFEST_NAME, ra.sha256_bytes(manifest_bytes)))
    ra.write_bytes(os.path.join(pkg, ra.SUMS_NAME), ra.render_sums(pairs))
    return pkg


class CatalogAndSelectionTest(unittest.TestCase):

    def test_catalog_is_valid_and_default_is_built_by_default(self):
        default, ordered, by_label = ra.load_catalog(ra.CATALOG_PATH)
        self.assertEqual(default, 'R2010b')
        self.assertIn('R2014b', by_label)
        self.assertEqual(ra.select_releases(default, ordered, by_label, None)[0]['label'], 'R2010b')

    def test_explicit_releases_keep_catalog_order_and_reject_bad_labels(self):
        default, ordered, by_label = ra.load_catalog(ra.CATALOG_PATH)
        chosen = ra.select_releases(default, ordered, by_label, 'R2014b,R2010b')
        self.assertEqual([e['label'] for e in chosen], ['R2010b', 'R2014b'])
        for bad in ('R1999z', 'R2010b,R2010b', 'R2010b,'):
            with self.assertRaises(ra.UsageError):
                ra.select_releases(default, ordered, by_label, bad)

    def test_matlab_roots_must_cover_each_selected_release_exactly_once(self):
        default, ordered, by_label = ra.load_catalog(ra.CATALOG_PATH)
        chosen = ra.select_releases(default, ordered, by_label, 'R2010b')
        roots = ra.parse_roots(['R2010b=/tmp/x'], chosen)
        self.assertEqual(roots['R2010b'], '/tmp/x')
        for pairs in ([], ['R2014b=/tmp/y'], ['R2010b=/a', 'R2010b=/b'], ['R2010b']):
            with self.assertRaises(ra.UsageError):
                ra.parse_roots(pairs, chosen)

    def test_invalid_catalog_is_refused(self):
        with self.assertRaises(ra.ReleaseError):
            ra.validate_catalog({'schema': 2, 'default': 'R2010b', 'releases': []})
        bad_library = {'schema': 1, 'default': 'R2010b', 'releases': [{
            'label': 'R2010b', 'matlab_version': '7.11', 'mcr_version': '7.14',
            'architecture': 'glnxa64',
            'runtime_identity': {'mcr_version_file': 'toolbox/compiler/mcrversion.ver',
                                 'library': 'libmwmclmcrrt.so.9.7'}}]}
        with self.assertRaises(ra.ReleaseError):
            ra.validate_catalog(bad_library)


class FrontendInventoryTest(unittest.TestCase):
    """The frontend/ inventory on synthetic frontend trees under the scratch base.

    Why the 21 passed / 2 failed result in the v3.2.0 audit: Python writes bytecode into
    frontend/__pycache__/. A stale, git-ignored .pyc left in the working tree was counted
    as an extra frontend file, so the working tree failed two tests. A copy without
    __pycache__/ passed all 23. The inventory now skips bytecode caches, so the working
    tree passes as it is. No test relies on a clean copy."""

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix='release-frontend-', dir=scratch_base())
        self.addCleanup(shutil.rmtree, self.base, True)
        self.frontend = os.path.join(self.base, 'frontend')
        for rel in ra.FRONTEND_OWN:
            write(os.path.join(self.frontend, *rel.split('/')), 'synthetic ' + rel + '\n')
        patcher = mock.patch.object(ra, 'FRONTEND_DIR', self.frontend)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_clean_frontend_tree_passes(self):
        self.assertEqual(ra.frontend_files_on_disk(), set(ra.FRONTEND_OWN))
        ra.check_sources()

    def test_bytecode_caches_do_not_count(self):
        write(os.path.join(self.frontend, '__pycache__', 'pseudo_CT_result_fields.cpython-313.pyc'),
              'stale bytecode\n')
        write(os.path.join(self.frontend, '__pycache__', 'pseudo_CT_gui_state.cpython-313.pyo'),
              'stale bytecode\n')
        write(os.path.join(self.frontend, 'stray.pyc'), 'stale bytecode\n')
        self.assertEqual(ra.frontend_files_on_disk(), set(ra.FRONTEND_OWN))
        ra.check_sources()

    def test_unexpected_real_files_still_fail(self):
        write(os.path.join(self.frontend, 'extra.m'), 'x\n')
        write(os.path.join(self.frontend, '__pycache__', 'notes.txt'), 'x\n')
        with self.assertRaises(ra.ReleaseError) as caught:
            ra.check_sources()
        message = str(caught.exception)
        self.assertIn('extra.m', message)
        self.assertIn('__pycache__/notes.txt', message)


class FrontendAllowlistTest(unittest.TestCase):

    def test_real_working_tree_frontend_matches_the_allowlist(self):
        """The repository's own frontend/ as it is on disk, including any untracked bytecode
        cache left by earlier runs. It must pass without a clean copy (see FrontendInventoryTest)."""
        self.assertEqual(ra.frontend_files_on_disk(), set(ra.FRONTEND_OWN))
        for rel in ra.FRONTEND_FROM_SRC:
            self.assertTrue(os.path.isfile(ra.frontend_source(rel)), rel)
        ra.check_sources()

    def test_package_resources_include_the_spm_dictionary(self):
        self.assertIn('spm_dicom_dict.mat', ra.RESOURCE_REQUIRED)
        self.assertIn('TPM.nii', ra.RESOURCE_REQUIRED)

    def test_shipped_paths_never_include_source_external_or_app_trees(self):
        labels = ('R2010b',)
        for rel in ('src/cli/pseudoct_standalone.m', 'external/spm8-r6313/spm.m',
                    'app/run_pseudo_CT', 'frontend/evil.m', 'frontend/passwordTools/x.m',
                    'runtimes/R2010b/app/run_pseudo_CT', 'config/releases.json'):
            self.assertFalse(ra.path_allowed(rel, labels), rel)
        self.assertTrue(ra.path_allowed('frontend/load_mr_4_AC.m', labels))
        self.assertTrue(ra.path_allowed('run_pseudo_CT.m', labels))
        self.assertTrue(ra.path_allowed('runtimes/R2010b/pseudoct_standalone', labels))
        self.assertFalse(ra.path_allowed('runtimes/R2010b/standalone/pseudoct_standalone', labels))


class HelpAllowlistTest(unittest.TestCase):
    """Package content for help/: the two help documents only, never screenshots."""

    LABELS = ('R2010b',)
    # Synthetic fixture names: screenshots as they appear under docs/help/assets/, and
    # other help-tree paths. None may be shipped.
    PNG_FIXTURES = ('help/assets/profile-selector.png', 'help/assets/getting-started.png',
                    'help/screenshot.png', 'help/index.png', 'help/assets/index.html',
                    'help/assets/style.css', 'help/extra.html', 'help/index.html/extra')

    def test_help_index_and_style_are_shipped_under_help(self):
        self.assertEqual(ra.HELP_FILES, ('index.html', 'style.css'))
        for name in ra.HELP_FILES:
            rel = 'help/' + name
            self.assertTrue(ra.path_allowed(rel, self.LABELS), rel)
            self.assertIn(rel, ra.required_paths(self.LABELS))
            self.assertTrue(os.path.isfile(os.path.join(ra.HELP_DIR, name)), name)

    def test_help_assets_and_png_images_are_never_allowed(self):
        for rel in self.PNG_FIXTURES:
            self.assertFalse(ra.path_allowed(rel, self.LABELS), rel)
        for rel in ra.required_paths(self.LABELS):
            self.assertNotIn('assets', rel.split('/'), rel)
            self.assertFalse(rel.lower().endswith('.png'), rel)
        for name in ra.HELP_FILES:
            self.assertFalse(name.lower().endswith('.png'), name)

    def test_package_containing_a_help_screenshot_fails_verification(self):
        base = tempfile.mkdtemp(prefix='release-help-', dir=scratch_base())
        try:
            pkg = make_package(base, version=FIXTURE_VERSION)
            self.assertEqual(ra.verify_package(pkg), [])
            write(os.path.join(pkg, 'help', 'assets', 'profile-selector.png'), 'synthetic image\n')
            problems = ra.verify_package(pkg)
            self.assertTrue(any('help/assets/profile-selector.png' in p for p in problems), problems)
        finally:
            shutil.rmtree(base, ignore_errors=True)


class VerifyTest(unittest.TestCase):

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix='release-verify-', dir=scratch_base())

    def tearDown(self):
        shutil.rmtree(self.base, ignore_errors=True)

    def test_consistent_package_verifies(self):
        pkg = make_package(self.base, version=FIXTURE_VERSION)
        self.assertEqual(ra.verify_package(pkg), [])

    def test_tampered_frontend_file_is_detected(self):
        pkg = make_package(self.base, version=FIXTURE_VERSION)
        write(os.path.join(pkg, 'frontend', 'load_mr_4_AC.m'), 'changed\n')
        problems = ra.verify_package(pkg)
        self.assertTrue(any('load_mr_4_AC.m' in p for p in problems), problems)

    def test_source_external_and_app_additions_are_refused(self):
        pkg = make_package(self.base, version=FIXTURE_VERSION)
        write(os.path.join(pkg, 'src', 'cli', 'pseudoct_standalone.m'), 'x\n')
        problems = ra.verify_package(pkg)
        self.assertTrue(any('forbidden path present: src/' in p for p in problems), problems)
        shutil.rmtree(os.path.join(pkg, 'src'))
        write(os.path.join(pkg, 'external', 'spm.m'), 'x\n')
        self.assertTrue(any('external/' in p for p in ra.verify_package(pkg)))
        shutil.rmtree(os.path.join(pkg, 'external'))
        write(os.path.join(pkg, 'app', 'run_pseudo_CT'), 'x\n')
        self.assertTrue(any('app' in p for p in ra.verify_package(pkg)))

    def test_unlisted_frontend_file_is_outside_the_allowlist(self):
        pkg = make_package(self.base, version=FIXTURE_VERSION)
        write(os.path.join(pkg, 'frontend', 'extra_helper.m'), 'x\n')
        problems = ra.verify_package(pkg)
        self.assertTrue(any('extra_helper.m' in p for p in problems), problems)

    def test_missing_executable_and_stale_sums_are_detected(self):
        pkg = make_package(self.base, version=FIXTURE_VERSION)
        os.remove(os.path.join(pkg, 'runtimes', 'R2010b', 'pseudoct_worker'))
        problems = ra.verify_package(pkg)
        self.assertTrue(any('missing file: runtimes/R2010b/pseudoct_worker' in p
                            for p in problems), problems)
        pkg2 = make_package(self.base, version='1.0.1')
        write(os.path.join(pkg2, ra.SUMS_NAME), 'bad\n')
        self.assertTrue(any('SHA256SUMS' in p for p in ra.verify_package(pkg2)))

    def test_verify_entry_point_exit_status(self):
        pkg = make_package(self.base, version='2.0.0')
        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(ra.main(['--verify', pkg]), 0)
            self.assertEqual(ra.main(['--verify', os.path.join(self.base, 'absent')]), 1)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(ra.main(['--verify', pkg, '--version', '1']), 2)


class DryRunTest(unittest.TestCase):

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix='release-dry-', dir=scratch_base())

    def tearDown(self):
        shutil.rmtree(self.base, ignore_errors=True)

    def fake_matlab(self):
        root = os.path.join(self.base, 'matlab-7.11')
        write(os.path.join(root, 'bin', 'matlab'), '#!/bin/sh\nexit 99\n')
        os.chmod(os.path.join(root, 'bin', 'matlab'), 0o755)
        write(os.path.join(root, 'runtime', 'glnxa64', 'libmwmclmcrrt.so.7.14'), 'lib\n')
        write(os.path.join(root, 'toolbox', 'compiler', 'mcrversion.ver'), '7.14\n')
        return root

    def test_dry_run_plans_two_targets_and_writes_nothing(self):
        output = os.path.join(self.base, 'out')
        root = self.fake_matlab()
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            status = ra.main(['--version', '9.9.9', '--releases', 'R2010b',
                              '--matlab-root', 'R2010b=' + root, '--output', output,
                              '--dry-run'])
        text = buffer.getvalue()
        self.assertEqual(status, 0, text)
        self.assertIn('DRY_RUN_PASS', text)
        self.assertIn('build_application', text)
        self.assertNotIn('WRAPPER', text)
        self.assertNotIn('app/', text)
        self.assertFalse(os.path.exists(output))


class RuntimeManifestNegativeTest(unittest.TestCase):
    """Runtime build and resource manifests are never shipped. Only manifest.json and
    SHA256SUMS are manifest-type files written by the release. Nothing is built here."""

    LABELS = ('R2010b', 'R2014b')
    RUNTIME_MANIFESTS = ('build_manifest.mat', 'resource_manifest.mat',
                         'mlsc_current_build.mat', 'mlsc_current_resources.mat')

    def test_runtime_manifest_names_are_not_in_the_allowlist(self):
        candidates = []
        for name in self.RUNTIME_MANIFESTS:
            candidates += [name, 'bin/' + name, 'frontend/' + name, 'help/' + name,
                           'resources/' + name, 'runtimes/R2010b/' + name,
                           'runtimes/R2010b/standalone/' + name]
        for rel in candidates:
            self.assertFalse(ra.path_allowed(rel, self.LABELS), rel)
        for rel in ra.required_paths(self.LABELS):
            self.assertNotIn(os.path.basename(rel), self.RUNTIME_MANIFESTS, rel)
        shipped_names = ({os.path.basename(p) for p in ra.RESOURCE_REQUIRED + ra.RUNTIME_FILES}
                         | {os.path.basename(p) for p in ra.FRONTEND_FILES}
                         | set(ra.HELP_FILES))
        for name in self.RUNTIME_MANIFESTS:
            self.assertNotIn(name, shipped_names)

    def test_only_manifest_json_and_sha256sums_are_manifest_files(self):
        import ast
        self.assertEqual(ra.MANIFEST_NAME, 'manifest.json')
        self.assertEqual(ra.SUMS_NAME, 'SHA256SUMS')
        for name in (ra.MANIFEST_NAME, ra.SUMS_NAME):
            self.assertFalse(ra.path_allowed(name, self.LABELS), name)
        labels = [entry['label'] for entry in ra.load_catalog(ra.CATALOG_PATH)[1]]
        for rel in ra.required_paths(labels):
            name = os.path.basename(rel)
            self.assertNotIn('manifest', name.lower(), rel)
            self.assertNotEqual(name, ra.SUMS_NAME, rel)
        # Static: every write_bytes call in the assembler must target exactly one of the
        # two manifest-type names. Each call's first argument is inspected as source text.
        with open(ra.__file__, encoding='utf-8') as handle:
            source = handle.read()
        written = []
        for node in ast.walk(ast.parse(source, ra.__file__)):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) \
                    and node.func.id == 'write_bytes':
                names = {n.id for n in ast.walk(node.args[0]) if isinstance(n, ast.Name)}
                hits = sorted(names & {'MANIFEST_NAME', 'SUMS_NAME'})
                self.assertEqual(len(hits), 1, ast.get_source_segment(source, node))
                written.append(hits[0])
        self.assertEqual(sorted(written), ['MANIFEST_NAME', 'SUMS_NAME'])


class Ssh2PackageInclusionTest(unittest.TestCase):
    """AMEND-1: the MATLAB SSH2 transport ships under external/ssh2_v2_m1_r5/ as exactly the
    Ganymed JAR and the two licence notices. The loose MATLAB wrappers are compiled into the
    engine and are never shipped as files, and nothing else under external/ is shipped."""

    LABELS = ('R2010b',)
    JAR = 'ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1.jar'
    NOTICES = ('license.txt', 'ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1-source/LICENSE.txt')

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix='release-ssh2-', dir=scratch_base())
        self.addCleanup(shutil.rmtree, self.base, True)

    def package_path(self, rel):
        return ra.SSH2_ROOT_REL + '/' + rel

    def test_jar_and_licence_notices_are_required_and_allowlisted(self):
        self.assertEqual(set(ra.SSH2_FILES), set(self.NOTICES) | {self.JAR})
        for rel in self.NOTICES + (self.JAR,):
            self.assertTrue(ra.path_allowed(self.package_path(rel), self.LABELS), rel)
            self.assertIn(self.package_path(rel), ra.required_paths(self.LABELS))
            self.assertTrue(os.path.isfile(os.path.join(ra.SSH2_SOURCE_ROOT, *rel.split('/'))), rel)

    def test_allowlist_is_exactly_the_jar_and_two_notices(self):
        wrapper_dir = os.path.join(ra.SSH2_SOURCE_ROOT, 'ssh2_v2_m1_r5')
        wrappers = {'ssh2_v2_m1_r5/' + name for name in os.listdir(wrapper_dir)
                    if name.endswith('.m') and os.path.isfile(os.path.join(wrapper_dir, name))}
        # The 19 wrappers still exist in the repository source; they are simply not shipped.
        self.assertEqual(len(wrappers), 19)
        self.assertFalse(wrappers & set(ra.SSH2_FILES))
        source = set()
        for dirpath, _dirs, names in os.walk(ra.SSH2_SOURCE_ROOT):
            for name in names:
                full = os.path.join(dirpath, name)
                source.add(os.path.relpath(full, ra.SSH2_SOURCE_ROOT).replace(os.sep, '/'))
        allowed = {rel for rel in source if ra.path_allowed(self.package_path(rel), self.LABELS)}
        self.assertEqual(allowed, set(self.NOTICES) | {self.JAR})
        self.assertLess(len(allowed), len(source))

    def test_other_external_content_is_never_allowlisted(self):
        for rel in ('ssh2_v2_m1_r5/ssh2.m',
                    'ssh2_v2_m1_r5/ssh2_setup.m',
                    'ssh2_v2_m1_r5/scp.m',
                    'ssh2_v2_m1_r5/examples/Basic.java',
                    'ssh2_v2_m1_r5/examples/ssh2_examples.m',
                    'ssh2_v2_m1_r5/HISTORY.txt',
                    'ssh2_v2_m1_r5/README.txt',
                    'ssh2_v2_m1_r5/ssh2_extra_helper.m',
                    'ssh2_v2_m1_r5/ganymed-ssh2-m1/README.txt',
                    'ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1-source/ganymed-ssh2-m1.jar',
                    'ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1-source/src/ch/ethz/ssh2/Session.java',
                    'ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1-source/javadoc/index.html',
                    'other_library/extra.m'):
            self.assertFalse(ra.path_allowed(self.package_path(rel), self.LABELS), rel)
        self.assertFalse(ra.path_allowed('external/spm8-r6313/spm.m', self.LABELS))

    def test_package_missing_jar_or_licence_notice_fails_verification(self):
        pkg = make_package(self.base, version=FIXTURE_VERSION)
        self.assertEqual(ra.verify_package(pkg), [])
        for rel in ra.SSH2_FILES:
            full = os.path.join(pkg, *self.package_path(rel).split('/'))
            with open(full, 'rb') as handle:
                content = handle.read()
            os.remove(full)
            problems = ra.verify_package(pkg)
            self.assertTrue(any('missing file: external/ssh2_v2_m1_r5/' + rel in p
                                for p in problems), (rel, problems))
            with open(full, 'wb') as handle:
                handle.write(content)
        self.assertEqual(ra.verify_package(pkg), [])

    def test_extra_external_example_or_loose_wrapper_in_a_package_is_refused(self):
        for index, rel in enumerate(('ssh2_v2_m1_r5/examples/Basic.java',
                                     'ssh2_v2_m1_r5/ssh2_setup.m')):
            pkg = make_package(self.base, version='0.0.%d-test' % (index + 1))
            write(os.path.join(pkg, *self.package_path(rel).split('/')), 'x\n')
            problems = ra.verify_package(pkg)
            self.assertTrue(any(rel in p for p in problems), (rel, problems))


if __name__ == '__main__':
    unittest.main()
