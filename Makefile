.PHONY: test test-version-bump

test: test-version-bump

test-version-bump:
	@./scripts/test-check-version-bump.sh
