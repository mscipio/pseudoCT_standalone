# Release archives are built with git archive; export-ignore rules in
# .gitattributes exclude maintainer/test/AI-only content automatically.
#
# git archive reads attributes from the selected tree, so the ref (tag or
# commit) must contain the committed archive policy for the exclusions to
# apply. Use a policy-bearing ref such as the current main commit or a
# future release tag created after policy adoption. Existing v2.8.0 and
# v2.8.1 tags are immutable pre-policy releases and do not carry these
# export-ignore rules.
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
