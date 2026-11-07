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


def make_package(root, labels=('R2010b',), version='1.0.0'):
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


class FrontendAllowlistTest(unittest.TestCase):

    def test_repository_frontend_matches_the_allowlist_exactly(self):
        self.assertEqual(ra.frontend_files_on_disk(), set(ra.FRONTEND_OWN))
        for rel in ra.FRONTEND_FROM_SRC:
            self.assertTrue(os.path.isfile(ra.frontend_source(rel)), rel)
        ra.check_sources()

    def test_shipped_paths_never_include_source_external_or_app_trees(self):
        labels = ('R2010b',)
        for rel in ('src/cli/pseudoct_standalone.m', 'external/spm8-r6313/spm.m',
                    'app/run_pseudo_CT', 'frontend/evil.m', 'frontend/passwordTools/x.m',
                    'runtimes/R2010b/app/run_pseudo_CT', 'config/releases.json'):
            self.assertFalse(ra.path_allowed(rel, labels), rel)
        self.assertTrue(ra.path_allowed('frontend/load_mr_4_AC.m', labels))
        self.assertTrue(ra.path_allowed('run_pseudo_CT.m', labels))
        self.assertTrue(ra.path_allowed('runtimes/R2010b/standalone/pseudoct_standalone', labels))


class VerifyTest(unittest.TestCase):

    def setUp(self):
        self.base = tempfile.mkdtemp(prefix='release-verify-', dir=scratch_base())

    def tearDown(self):
        shutil.rmtree(self.base, ignore_errors=True)

    def test_consistent_package_verifies(self):
        pkg = make_package(self.base)
        self.assertEqual(ra.verify_package(pkg), [])

    def test_tampered_frontend_file_is_detected(self):
        pkg = make_package(self.base)
        write(os.path.join(pkg, 'frontend', 'load_mr_4_AC.m'), 'changed\n')
        problems = ra.verify_package(pkg)
        self.assertTrue(any('load_mr_4_AC.m' in p for p in problems), problems)

    def test_source_external_and_app_additions_are_refused(self):
        pkg = make_package(self.base)
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
        pkg = make_package(self.base)
        write(os.path.join(pkg, 'frontend', 'extra_helper.m'), 'x\n')
        problems = ra.verify_package(pkg)
        self.assertTrue(any('extra_helper.m' in p for p in problems), problems)

    def test_missing_executable_and_stale_sums_are_detected(self):
        pkg = make_package(self.base)
        os.remove(os.path.join(pkg, 'runtimes', 'R2010b', 'payload', 'mlsc_current_payload'))
        problems = ra.verify_package(pkg)
        self.assertTrue(any('missing file: runtimes/R2010b/payload/mlsc_current_payload' in p
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


if __name__ == '__main__':
    unittest.main()
