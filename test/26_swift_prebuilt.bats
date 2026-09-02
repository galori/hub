#!/usr/bin/env bats
# Unit tests for the prebuilt-Swift-binary fallback: `hub install` must be
# able to install working Swift tools without Xcode/Command Line Tools by
# using the binaries committed under lib/prebuilt/, only falling back to a
# real swiftc build when HUB_SHOULD_BUILD_SWIFT=1 is set.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    # Overwrite the default no-op swiftc stub with one that records
    # invocations, so tests can assert the prebuilt path never shells out.
    make_stub_recording swiftc "" 0
    # shellcheck disable=SC1090
    source "$REPO_DIR/scripts/hub"
}

teardown() {
    teardown_stubs
}

@test "try_install_prebuilt_swift installs the committed binary when the fingerprint matches" {
    local bin="$HUB_TEST_DIR/browser_ctl_out"
    run try_install_prebuilt_swift "browser_ctl" "$bin" "$LIB_DIR/browser_ctl.swift"

    [[ "$status" -eq 0 ]]
    [[ -x "$bin" ]]
    # Real universal binary, not a stub: runs without invoking swiftc.
    run "$bin"
    [[ ! -f "$STUB_CALLS" ]] || ! grep -q '^swiftc' "$STUB_CALLS"
}

@test "try_install_prebuilt_swift refuses a binary whose source has changed" {
    local tampered="$HUB_TEST_DIR/browser_ctl_tampered.swift"
    cp "$LIB_DIR/browser_ctl.swift" "$tampered"
    printf '\n// tampered\n' >> "$tampered"

    local bin="$HUB_TEST_DIR/browser_ctl_out"
    run try_install_prebuilt_swift "browser_ctl" "$bin" "$tampered"

    [[ "$status" -ne 0 ]]
    [[ ! -e "$bin" ]]
}

@test "try_install_prebuilt_swift fails when no prebuilt binary exists for the key" {
    local bin="$HUB_TEST_DIR/nonexistent_out"
    run try_install_prebuilt_swift "does_not_exist_tool" "$bin" "$LIB_DIR/browser_ctl.swift"

    [[ "$status" -ne 0 ]]
    [[ ! -e "$bin" ]]
}

@test "swift_local_build_allowed denies local compilation by default" {
    unset HUB_SHOULD_BUILD_SWIFT
    run swift_local_build_allowed "some_tool"

    [[ "$status" -ne 0 ]]
}

@test "swift_local_build_allowed permits local compilation when opted in" {
    export HUB_SHOULD_BUILD_SWIFT=1
    run swift_local_build_allowed "some_tool"

    [[ "$status" -eq 0 ]]
}

@test "compile_swift installs from prebuilt without invoking swiftc" {
    local bin="$HUB_CONFIG_DIR/browser_ctl"
    compile_swift "browser_ctl" "$LIB_DIR/browser_ctl.swift" "$bin"

    [[ -x "$bin" ]]
    [[ ! -f "$STUB_CALLS" ]] || ! grep -q '^swiftc' "$STUB_CALLS"
}

@test "compile_swift skips with a warning when source changed and build is not opted in" {
    unset HUB_SHOULD_BUILD_SWIFT
    local tampered_src="$HUB_TEST_DIR/browser_ctl.swift"
    cp "$LIB_DIR/browser_ctl.swift" "$tampered_src"
    printf '\n// tampered\n' >> "$tampered_src"

    local bin="$HUB_CONFIG_DIR/browser_ctl"
    run compile_swift "browser_ctl" "$tampered_src" "$bin"

    [[ ! -e "$bin" ]]
    [[ "$output" == *"HUB_SHOULD_BUILD_SWIFT=1"* ]]
}

@test "check-swift-prebuilt.sh passes against the committed lib/prebuilt binaries" {
    run "$REPO_DIR/scripts/check-swift-prebuilt.sh"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"match their sources"* ]]
}
