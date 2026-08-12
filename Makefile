.PHONY: test test-version-bump

test: test-version-bump

test-version-bump:
	@python3 ./scripts/test-check-version-bump.py
