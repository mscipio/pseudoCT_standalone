"""bin/pseudoct stdout transport: the repeated presenter table header.

Each MATLAB phase (validate, submit) is a separate process whose presenter
prints the TIME/SUBJECT table header and rule again. The launcher's embedded
transport must print the header once per invocation (state shared across
phases through a marker beside the diagnostics file) and never drop rows.
Runs the launcher's real embedded Python with /bin/cat; no MATLAB, no jobs.
"""
import pathlib
import subprocess
import sys
import tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
source = (repo / 'bin/pseudoct').read_text()
marker = "<<'PY'\nimport json\nimport os\nimport re\nimport selectors\n"
transport = 'import json\nimport os\nimport re\nimport selectors\n' + \
    source.split(marker, 1)[1].split('\nPY\n', 1)[0]
compile(transport, 'bin/pseudoct:run_headless', 'exec')

HEADER = 'TIME     SUBJECT STAGE   STATUS    MESSAGE\n'
RULE = '-' * 123 + '\n'
# Captured mlsc-current console rows (presenter-v4 run, 2026-11-05).
PHASE1 = HEADER + RULE + (
    '10:24:59 S01     [1/10]  ACTIVE    Preparing input MPRAGE\n'
    '10:25:44 S01             DONE      Input MPRAGE prepared\n')
PHASE2 = HEADER + RULE + (
    '10:25:53 S01             INFO      MLSC authentication succeeded\n'
    '10:25:56 S01             INFO      MLSC job 10582887 accepted.\n')


def run_phase(workdir, name, text, output_format='text'):
    stream = workdir / (name + '.stdout')
    stream.write_text(text)
    result = subprocess.run(
        [sys.executable, '-c', transport, '/bin/cat', str(stream), '/dev/null',
         output_format, str(workdir / ('diagnostics-' + name + '.log')),
         'stdout-filter-test', str(workdir / 'unused-index'), 'mlsc-current'],
        capture_output=True, check=True)
    assert not result.stderr, result.stderr
    return result.stdout.decode()


with tempfile.TemporaryDirectory() as tmp:
    workdir = pathlib.Path(tmp)
    first = run_phase(workdir, 'validate', PHASE1)
    second = run_phase(workdir, 'submit', PHASE2)
    assert first == PHASE1, first
    # Header and rule of the second phase are diverted; both rows are kept.
    assert second == PHASE2.split(RULE, 1)[1], second
    assert (first + second).count('TIME     SUBJECT') == 1
    assert (first + second).count(RULE) == 1
    diagnostics = (workdir / 'diagnostics-submit.log').read_text()
    assert '[stdout duplicate header] ' + HEADER in diagnostics
    assert '[stdout duplicate header] ' + RULE in diagnostics
    # A dashed line that is not directly after a repeated header is not touched.
    third = run_phase(workdir, 'extra', RULE + '10:30:00 S01             INFO      x\n')
    assert third == RULE + '10:30:00 S01             INFO      x\n', third
print('PSEUDOCT STDOUT FILTER: PASS')
