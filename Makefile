.PHONY: lint test tag package

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

DIST_DIR = dist
PKG_DIR  = $(DIST_DIR)/pseudoCT_v$(VERSION)

package:
	@[ -n "$(VERSION)" ] || (echo "ERROR: CHANGELOG.md is empty or missing" && exit 1)
	rm -rf "$(PKG_DIR)"
	mkdir -p "$(PKG_DIR)"
	cp run_pseudo_CT.m "$(PKG_DIR)/"
	cp CHANGELOG.md "$(PKG_DIR)/"
	cp README.md "$(PKG_DIR)/"
	cp -r src "$(PKG_DIR)/"
	cp -r vers "$(PKG_DIR)/"
	cp -r imgaussian "$(PKG_DIR)/"
	cp -r ssh2_v2_m1_r5 "$(PKG_DIR)/"
	cp -r docs "$(PKG_DIR)/"
	cd "$(DIST_DIR)" && tar -czf "pseudoCT_v$(VERSION).tar.gz" "pseudoCT_v$(VERSION)"
	@echo "Package assembled: $(PKG_DIR)/"
	@echo "Archive created:   $(DIST_DIR)/pseudoCT_v$(VERSION).tar.gz"
