.PHONY: lint test tag package

MATLAB = matlab -nodisplay -batch
VERSION = $(shell cat version.txt | tr -d '[:space:]')

lint:
	$(MATLAB) "run('scripts/run_lint.m')"

test:
	$(MATLAB) "run('scripts/run_smoke_tests.m'), exit"

tag:
	@[ -n "$(VERSION)" ] || (echo "ERROR: version.txt is empty or missing" && exit 1)
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo "Tagged v$(VERSION)"

package:
	@[ -n "$(VERSION)" ] || (echo "ERROR: version.txt is empty or missing" && exit 1)
	rm -rf "pseudoCT_v$(VERSION)"
	mkdir -p "pseudoCT_v$(VERSION)"
	cp run_pseudo_CT_local.m "pseudoCT_v$(VERSION)/"
	cp run_pseudo_CT_launchpad.m "pseudoCT_v$(VERSION)/"
	cp version.txt "pseudoCT_v$(VERSION)/"
	cp -r src "pseudoCT_v$(VERSION)/"
	cp -r vers "pseudoCT_v$(VERSION)/"
	cp -r spm8-r6313 "pseudoCT_v$(VERSION)/"
	cp -r imgaussian "pseudoCT_v$(VERSION)/"
	cp -r ssh2_v2_m1_r5 "pseudoCT_v$(VERSION)/"
	cp Makefile "pseudoCT_v$(VERSION)/"
	cp -r scripts "pseudoCT_v$(VERSION)/"
	rm -f "pseudoCT_v$(VERSION)/scripts/test_auto_discover_messages.m"
	@echo "Package assembled: pseudoCT_v$(VERSION)/"
