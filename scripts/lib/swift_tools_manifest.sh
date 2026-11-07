# Canonical list of Swift tools that ship as prebuilt binaries in
# lib/prebuilt/. Each entry is "key|src|extras" (paths relative to lib/,
# extras is a comma-separated list and may be empty). This is the single source of truth for
# scripts/build-swift-prebuilt.sh and scripts/check-swift-prebuilt.sh — keep
# it in sync with the compile_swift/build_http_handler/build_hub_app calls in
# scripts/hub.

SWIFT_TOOLS_MANIFEST=(
    "new_workspace_dialog|new_workspace_dialog.swift|theme.swift"
    "confirm_dialog|confirm_dialog.swift|theme.swift"
    "rename_dialog|rename_dialog.swift|theme.swift"
    "dashboard_dialog|dashboard_dialog.swift|theme.swift"
    "output_window|output_window.swift|theme.swift"
    "progress_banner|progress_banner.swift|theme.swift"
    "app_switcher|app_switcher.swift|theme.swift"
    "command_palette|command_palette.swift|theme.swift"
    "log_viewer|log_viewer.swift|theme.swift"
    "hub_bar|hub_bar.swift|theme.swift,hotkey_protocol.swift"
    "hub_hotkeyd|hub_hotkeyd.swift|hotkey_protocol.swift,hotkey_gesture.swift,hotkey_recovery_policy.swift"
    "browser_ctl|browser_ctl.swift|"
    "spatial_order|spatial_order.swift|"
    "float_nudge|float_nudge.swift|"
    "http_handler|http_handler.swift|theme.swift"
    "hub_toggle_app|hub_toggle_app.swift|"
)
