.PHONY: lint test tag

MATLAB = matlab -nodisplay -batch

lint:
	$(MATLAB) "run('scripts/run_lint.m')"

test:
	$(MATLAB) "run('scripts/run_smoke_tests.m'), exit"

tag:
	git tag v2.5
	@echo "Tagged v2.5"
