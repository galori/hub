.PHONY: test test-fast test-swift

# Run all tests (including Swift compile tests)
test:
	bats test/

# Run all tests except slow Swift compile tests
test-fast:
	SKIP_SWIFT_COMPILE=1 bats test/

# Run only Swift compile smoke tests
test-swift:
	bats test/06_swift_compile.bats
