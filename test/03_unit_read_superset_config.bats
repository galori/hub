#!/usr/bin/env bats
# Unit tests for read_superset_config

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export REPO_ROOT="$HOME/repo"
    mkdir -p "$REPO_ROOT/.superset"
}

teardown() {
    teardown_stubs
}

write_config() {
    echo "$1" > "$REPO_ROOT/.superset/config.json"
}

run_read() {
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; read_superset_config '$REPO_ROOT' '$1'"
}

@test "read_superset_config returns setup command" {
    write_config '{"setup": ["scripts/setup.sh"]}'
    result="$(run_read setup)"
    [[ "$result" == "scripts/setup.sh" ]]
}

@test "read_superset_config returns teardown command" {
    write_config '{"teardown": ["scripts/teardown.sh"]}'
    result="$(run_read teardown)"
    [[ "$result" == "scripts/teardown.sh" ]]
}

@test "read_superset_config returns empty when key missing" {
    write_config '{"setup": ["scripts/setup.sh"]}'
    result="$(run_read teardown)"
    [[ -z "$result" ]]
}

@test "read_superset_config returns non-zero when config.json missing" {
    rm -f "$REPO_ROOT/.superset/config.json"
    run bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; read_superset_config '$REPO_ROOT' setup"
    [[ "$status" -ne 0 ]]
}

@test "read_superset_config returns empty for null value" {
    write_config '{"setup": null}'
    result="$(run_read setup)"
    [[ -z "$result" ]]
}
