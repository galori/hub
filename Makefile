.PHONY: test test-local test-fast test-swift test-integration

# Run all local, worktree-safe tests (including Swift compile tests)
test test-local:
	bats test/

# Run all local, worktree-safe tests except slow Swift compile tests
test-fast:
	SKIP_SWIFT_COMPILE=1 bats test/

# Run only Swift compile smoke tests
test-swift:
	bats test/06_swift_compile.bats

# Live integration suite — requires a real logged-in macOS GUI session with
# aerospace, borders, jq, and bats installed. Intended for a
# dedicated / isolated test machine. See test/integration/README.md.
test-integration:
	@tmp="$$(mktemp "$${TMPDIR:-/tmp}/hub-integration.XXXXXX")"; \
	HUB_RUN_INTEGRATION=1 bats --formatter tap test/integration/ >"$$tmp" 2>&1 & pid=$$!; \
	while kill -0 "$$pid" 2>/dev/null; do \
		if grep -q 'hub-full-screen keeps the Hub Bar top strip visible below the revealed macOS menu bar' "$$tmp"; then \
			sleep 2; \
			if kill -0 "$$pid" 2>/dev/null; then \
				pkill -TERM -P "$$pid" 2>/dev/null || true; \
				kill "$$pid" 2>/dev/null || true; \
				wait "$$pid" 2>/dev/null || true; \
				cat "$$tmp"; \
				rm -f "$$tmp"; \
				exit 0; \
			fi; \
		fi; \
		sleep 1; \
	done; \
	wait "$$pid"; rc=$$?; \
	cat "$$tmp"; \
	rm -f "$$tmp"; \
	exit "$$rc"
