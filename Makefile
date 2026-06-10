.PHONY: test test-fast test-swift test-integration

# Run all tests (including Swift compile tests)
test:
	bats test/

# Run all tests except slow Swift compile tests
test-fast:
	SKIP_SWIFT_COMPILE=1 bats test/

# Run only Swift compile smoke tests
test-swift:
	bats test/06_swift_compile.bats

# Live integration suite — requires a real logged-in macOS GUI session with
# aerospace, sketchybar, borders, jq, and bats installed. Intended for a
# dedicated / isolated test machine. See test/integration/README.md.
test-integration:
	HUB_RUN_INTEGRATION=1 bats test/integration/
