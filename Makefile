# Release archives are built with git archive; export-ignore rules in
# .gitattributes exclude maintainer/test/AI-only content automatically.
#
#   git archive --format=tar.gz --prefix=pseudoCT_v$(VERSION)/ \
#     -o dist/pseudoCT_v$(VERSION).tar.gz <tag-or-commit>

.PHONY: lint test tag

MATLAB = matlab -nodisplay -batch
VERSION = $(shell head -n 1 CHANGELOG.md | tr -d '[:space:]')

lint:
	$(MATLAB) "run('scripts/run_lint.m')"

test:
	$(MATLAB) "run('scripts/run_smoke_tests.m'), exit"

tag:
	@[ -n "$(VERSION)" ] || (echo "ERROR: CHANGELOG.md is empty or missing" && exit 1)
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo "Tagged v$(VERSION)"
