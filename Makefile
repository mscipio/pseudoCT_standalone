.PHONY: lint test tag package

MATLAB = matlab -nodisplay -batch
VERSION = $(shell head -n 1 version.txt | tr -d '[:space:]')

lint:
	$(MATLAB) "run('scripts/run_lint.m')"

test:
	$(MATLAB) "run('scripts/run_smoke_tests.m'), exit"

tag:
	@[ -n "$(VERSION)" ] || (echo "ERROR: version.txt is empty or missing" && exit 1)
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo "Tagged v$(VERSION)"

DIST_DIR = dist
PKG_DIR  = $(DIST_DIR)/pseudoCT_v$(VERSION)

package:
	@[ -n "$(VERSION)" ] || (echo "ERROR: version.txt is empty or missing" && exit 1)
	rm -rf "$(PKG_DIR)"
	mkdir -p "$(PKG_DIR)"
	cp run_pseudo_CT_local.m "$(PKG_DIR)/"
	cp run_pseudo_CT_launchpad.m "$(PKG_DIR)/"
	cp version.txt "$(PKG_DIR)/"
	cp -r src "$(PKG_DIR)/"
	cp -r vers "$(PKG_DIR)/"
	cp -r spm8-r6313 "$(PKG_DIR)/"
	cp -r imgaussian "$(PKG_DIR)/"
	cp -r ssh2_v2_m1_r5 "$(PKG_DIR)/"
	cp Makefile "$(PKG_DIR)/"
	cp -r scripts "$(PKG_DIR)/"
	rm -f "$(PKG_DIR)/scripts/test_auto_discover_messages.m"
	cd "$(DIST_DIR)" && tar -czf "pseudoCT_v$(VERSION).tar.gz" "pseudoCT_v$(VERSION)"
	@echo "Package assembled: $(PKG_DIR)/"
	@echo "Archive created:   $(DIST_DIR)/pseudoCT_v$(VERSION).tar.gz"
