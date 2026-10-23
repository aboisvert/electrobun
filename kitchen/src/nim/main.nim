## Electrobun Kitchen Sink - Nim main process.
## Electrobun Kitchen Sink - Nim main process.
import std/[json, os, ospaths, strutils, strformat, times, monotimes, locks, atomics, parseutils, math, tables, syncio, options, typedthreads]
import electrobun

const appVersion = "1.18.1"
const defaultSecretKey = "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32"
const visibleTestWindowDelayMs = 1000
const shortWaitMs = 150
const mediumWaitMs = 500
const longWaitMs = 1200
const testHarnessUrl = "views://test-harness/index.html"
const trayTemplateIconUrl = "views://assets/electrobun-logo-32-template.png"

const availableRenderersNative* = @["native"]
const availableRenderersCef* = @["native", "cef"]

type
  BuildConfigPayload* = object
    defaultRenderer*: string
    availableRenderers*: seq[string]
    mainProcess*: string
    cefVersion*: Option[string]
    nimVersion*: Option[string]


type
  UpdateInfo* = object
    status*: string
    currentVersion*: string
    newVersion*: Option[string]
    error*: Option[string]


type
  TestInfo* = object
    id*: string
    name*: string
    category*: string
    description*: string
    instructions*: seq[string]
    interactive*: bool


type
  TestResult* = object
    testId*: string
    name*: string
    status*: string
    duration*: uint64
    error*: Option[string]


type
  TestKind* = enum
    smoke,
    app_packaged_mode_reflects_build_channel,
    window_create_close,
    window_creation_with_url,
    window_hidden_option,
    window_inactive_show_api,
    window_page_zoom,
    window_set_title,
    window_minimize_unminimize,
    window_fullscreen_toggle,
    window_fullscreen_toggle_hidden_titlebar,
    window_omitted_position_centers_on_primary_display,
    window_set_position,
    window_set_size,
    window_set_frame,
    window_get_frame,
    window_get_position,
    window_get_size,
    window_maximize_unmaximize,
    window_always_on_top,
    window_visible_on_all_workspaces,
    window_focus,
    window_close_event,
    window_will_close_veto,
    window_resize_event,
    window_get_by_id,
    window_inset_titlebar_style,
    window_traffic_light_position_api,
    webview_create,
    webview_page_zoom,
    webview_spell_check,
    appdata_protocol_allow,
    appdata_protocol_deny,
    webview_tag_playground_integration,
    webview_tag_playground_interactive,
    wgpu_tag_playground_integration,
    wgpu_tag_playground_interactive,
    navigation_load_url,
    navigation_load_html,
    navigation_dom_ready_event,
    navigation_did_navigate_event,
    navigation_did_commit_navigation_event,
    navigation_execute_javascript,
    tray_visibility_toggle_and_bounds,
    session_from_partition,
    session_default_session,
    session_cookies_api_exists,
    application_menu_playground,
    context_menu_playground,
    dialog_show_message_box_info,
    dialog_file_dialog_playground,
    global_shortcuts_playground,
    global_shortcut_is_registered_api,
    global_shortcut_unregister_all_api,
    lifecycle_before_quit_cancel,
    quit_shutdown_playground,
    wgpu_adapter_context_device,
    dock_icon_visibility_contract,
    utils_clipboard_round_trip,
    utils_clipboard_available_formats,
    utils_clipboard_clear,
    utils_show_notification,
    utils_open_external_exists,
    utils_open_path_exists,
    utils_show_item_in_folder_exists,
    utils_quit_exists,
    utils_paths_object_exists,
    utils_paths_home_matches,
    utils_paths_temp_matches,
    utils_paths_os_directories,
    utils_paths_app_scoped_directories,
    utils_paths_stable_across_calls,
    utils_move_to_trash,
    screen_primary_display,
    screen_all_displays,
    screen_cursor_screen_point,
    screen_capture_region,
    screen_bounds_vs_workarea


type
  NimTest* = object
    id*: string
    name*: string
    category*: string
    description*: string
    instructions*: seq[string]
    interactive*: bool
    mirrors_bun_test_name*: string
    kind*: TestKind


proc testToInfo(self: NimTest): TestInfo =
  TestInfo(
    id: self.id,
    name: self.name,
    category: self.category,
    description: self.description,
    instructions: self.instructions,
    interactive: self.interactive,
  )

const nimTests* = @[
  NimTest(
    id: "nim-smoke-test",
    name: "Nim host smoke test",
    category: "Nim Native",
    description: "Verify the Nim main process and view RPC bridge are running.",
    kind: smoke
  ),
  NimTest(
    id: "nim-app-packaged-mode-reflects-build-channel",
    name: "App packaged mode reflects build channel",
    category: "Runtime",
    description: "Verify packaged mode is derived from the authoritative build channel metadata.",
    mirrors_bun_test_name: "App packaged mode reflects build channel",
    kind: app_packaged_mode_reflects_build_channel
  ),
  NimTest(
    id: "nim-window-create-close",
    name: "Window create/close (Nim)",
    category: "BrowserWindow",
    description: "Create a native window through the Nim SDK and close it again.",
    kind: window_create_close
  ),
  NimTest(
    id: "nim-window-creation-with-url",
    name: "Window creation with URL (Nim)",
    category: "BrowserWindow",
    description: "Create a native window and attach a BrowserView loading the test harness URL.",
    mirrors_bun_test_name: "Window creation with URL",
    kind: window_creation_with_url
  ),
  NimTest(
    id: "nim-window-hidden-option",
    name: "Window hidden option (Nim)",
    category: "BrowserWindow",
    description: "Verify native visibility across hidden creation, show, and hide through the Nim SDK.",
    mirrors_bun_test_name: "Window hidden option",
    kind: window_hidden_option
  ),
  NimTest(
    id: "nim-window-inactive-show-api",
    name: "Window inactive show API (Nim)",
    category: "BrowserWindow",
    description: "Show a native window without activation, then activate it explicitly.",
    mirrors_bun_test_name: "Window inactive show API",
    kind: window_inactive_show_api
  ),
  NimTest(
    id: "nim-window-page-zoom",
    name: "Window page zoom API (Nim)",
    category: "BrowserWindow",
    description: "Set and read the primary BrowserWindow page zoom in Nim mode.",
    mirrors_bun_test_name: "Window page zoom API",
    kind: window_page_zoom
  ),
  NimTest(
    id: "nim-window-set-title",
    name: "Window setTitle (Nim)",
    category: "BrowserWindow",
    description: "Update a native window title through the Nim SDK.",
    mirrors_bun_test_name: "Window setTitle",
    kind: window_set_title
  ),
  NimTest(
    id: "nim-window-minimize-unminimize",
    name: "Window minimize/unminimize (Nim)",
    category: "BrowserWindow",
    description: "Toggle native window minimized state through the Nim SDK.",
    mirrors_bun_test_name: "Window minimize/unminimize",
    kind: window_minimize_unminimize
  ),
  NimTest(
    id: "nim-window-fullscreen-toggle",
    name: "Window fullscreen toggle (Nim)",
    category: "BrowserWindow",
    description: "Toggle native window fullscreen state through the Nim SDK.",
    mirrors_bun_test_name: "Window fullscreen toggle",
    kind: window_fullscreen_toggle
  ),
  NimTest(
    id: "nim-window-fullscreen-toggle-hidden-titlebar",
    name: "Window fullscreen toggle with hidden titlebar (Nim)",
    category: "BrowserWindow",
    description: "Toggle fullscreen for a hidden-titlebar window in Nim mode on macOS.",
    mirrors_bun_test_name: "Window fullscreen toggle with hidden titlebar",
    kind: window_fullscreen_toggle_hidden_titlebar
  ),
  NimTest(
    id: "nim-window-omitted-position-centers-on-primary-display",
    name: "Window omitted position centers on primary display (Nim)",
    category: "BrowserWindow",
    description: "Create a hidden centered window and compare its frame to the primary display work area.",
    mirrors_bun_test_name: "Window omitted position centers on primary display",
    kind: window_omitted_position_centers_on_primary_display
  ),
  NimTest(
    id: "nim-window-set-position",
    name: "Window setPosition (Nim)",
    category: "BrowserWindow",
    description: "Move a native window and read the new frame back from core.",
    mirrors_bun_test_name: "Window setPosition",
    kind: window_set_position
  ),
  NimTest(
    id: "nim-window-set-size",
    name: "Window setSize (Nim)",
    category: "BrowserWindow",
    description: "Grow and shrink a native-renderer window through core.",
    mirrors_bun_test_name: "Window setSize",
    kind: window_set_size
  ),
  NimTest(
    id: "nim-window-set-frame",
    name: "Window setFrame (Nim)",
    category: "BrowserWindow",
    description: "Create a window, update its frame, and read the new size back from core.",
    mirrors_bun_test_name: "Window setFrame",
    kind: window_set_frame
  ),
  NimTest(
    id: "nim-window-get-frame",
    name: "Window getFrame (Nim)",
    category: "BrowserWindow",
    description: "Read the current native window frame through the Nim SDK.",
    mirrors_bun_test_name: "Window getFrame",
    kind: window_get_frame
  ),
  NimTest(
    id: "nim-window-get-position",
    name: "Window getPosition (Nim)",
    category: "BrowserWindow",
    description: "Read the current native window position through the Nim SDK.",
    mirrors_bun_test_name: "Window getPosition",
    kind: window_get_position
  ),
  NimTest(
    id: "nim-window-get-size",
    name: "Window getSize (Nim)",
    category: "BrowserWindow",
    description: "Read the current native window size through the Nim SDK.",
    mirrors_bun_test_name: "Window getSize",
    kind: window_get_size
  ),
  NimTest(
    id: "nim-window-maximize-unmaximize",
    name: "Window maximize/unmaximize (Nim)",
    category: "BrowserWindow",
    description: "Toggle native window maximized state through the Nim SDK.",
    mirrors_bun_test_name: "Window maximize/unmaximize",
    kind: window_maximize_unmaximize
  ),
  NimTest(
    id: "nim-window-always-on-top",
    name: "Window alwaysOnTop (Nim)",
    category: "BrowserWindow",
    description: "Toggle native always-on-top state through the Nim SDK.",
    mirrors_bun_test_name: "Window alwaysOnTop",
    kind: window_always_on_top
  ),
  NimTest(
    id: "nim-window-visible-on-all-workspaces",
    name: "Window visibleOnAllWorkspaces (macOS) (Nim)",
    category: "BrowserWindow",
    description: "Toggle visible-on-all-workspaces in Nim mode on macOS.",
    mirrors_bun_test_name: "Window visibleOnAllWorkspaces (macOS)",
    kind: window_visible_on_all_workspaces
  ),
  NimTest(
    id: "nim-window-focus",
    name: "Window focus (Nim)",
    category: "BrowserWindow",
    description: "Focus multiple native windows through the Nim SDK.",
    mirrors_bun_test_name: "Window focus",
    kind: window_focus
  ),
  NimTest(
    id: "nim-window-close-event",
    name: "Window close event (Nim)",
    category: "BrowserWindow",
    description: "Verify a per-window close callback fires in Nim mode.",
    mirrors_bun_test_name: "Window close event",
    kind: window_close_event
  ),
  NimTest(
    id: "nim-window-will-close-veto",
    name: "Window will-close can veto user close (Nim)",
    category: "BrowserWindow",
    description: "Verify a native user-close request can be vetoed before destruction.",
    mirrors_bun_test_name: "Window will-close can veto user close",
    kind: window_will_close_veto
  ),
  NimTest(
    id: "nim-window-resize-event",
    name: "Window resize event (Nim)",
    category: "BrowserWindow",
    description: "Verify a per-window resize callback fires in Nim mode.",
    mirrors_bun_test_name: "Window resize event",
    kind: window_resize_event
  ),
  NimTest(
    id: "nim-window-get-by-id",
    name: "BrowserWindow.getById (Nim)",
    category: "BrowserWindow",
    description: "Verify the Nim window registry can retrieve a tracked window by id.",
    mirrors_bun_test_name: "BrowserWindow.getById",
    kind: window_get_by_id
  ),
  NimTest(
    id: "nim-window-inset-titlebar-style",
    name: "Window with inset titlebar style (Nim)",
    category: "BrowserWindow",
    description: "Create a native window with hiddenInset titlebar style in Nim mode.",
    mirrors_bun_test_name: "Window with inset titlebar style",
    kind: window_inset_titlebar_style
  ),
  NimTest(
    id: "nim-window-traffic-light-position-api",
    name: "Window traffic light position API (Nim)",
    category: "BrowserWindow",
    description: "Create a hiddenInset window with traffic light offsets and move them at runtime.",
    mirrors_bun_test_name: "Window traffic light position API",
    kind: window_traffic_light_position_api
  ),
  NimTest(
    id: "nim-webview-create",
    name: "BrowserView create (Nim)",
    category: "BrowserView",
    description: "Create a secondary native webview through the Nim SDK.",
    kind: webview_create
  ),
  NimTest(
    id: "nim-webview-page-zoom",
    name: "BrowserView page zoom API (Nim)",
    category: "BrowserWindow",
    description: "Set and read BrowserView page zoom in Nim mode.",
    mirrors_bun_test_name: "BrowserView page zoom API",
    kind: webview_page_zoom
  ),
  NimTest(
    id: "nim-webview-spell-check",
    name: "BrowserView spell check capability (Nim)",
    category: "BrowserWindow",
    description: "Report native WKWebView spell-check support through the Nim SDK.",
    mirrors_bun_test_name: "BrowserView spell check capability",
    kind: webview_spell_check
  ),
  NimTest(
    id: "nim-appdata-protocol-allows-access",
    name: "appdata protocol allows access",
    category: "Protocols",
    description: "Read exact appdata file contents in a CEF-requested webview.",
    mirrors_bun_test_name: "appdata protocol allows access",
    kind: appdata_protocol_allow
  ),
  NimTest(
    id: "nim-appdata-protocol-denies-access",
    name: "appdata protocol denies access",
    category: "Protocols",
    description: "Block appdata file access in a CEF-requested webview.",
    mirrors_bun_test_name: "appdata protocol denies access",
    kind: appdata_protocol_deny
  ),
  NimTest(
    id: "nim-webview-tag-playground-integration",
    name: "Webview Tag playground integration (Nim)",
    category: "Webview Tag",
    description: "Load the real webview-tag playground in CEF mode and verify nested electrobun-webview tags initialize through the Nim host bridge.",
    kind: webview_tag_playground_integration
  ),
  NimTest(
    id: "nim-webview-tag-playground",
    name: "Webview Tag playground (Nim)",
    category: "Webview Tag (Interactive)",
    description: "Open the real webview-tag playground and keep it open for manual interaction until the window is closed.",
    interactive: true,
    mirrors_bun_test_name: "Webview Tag playground",
    kind: webview_tag_playground_interactive
  ),
  NimTest(
    id: "nim-wgpu-tag-playground-integration",
    name: "WGPU Tag playground integration (Nim)",
    category: "WGPU Tag",
    description: "Load the real WGPU tag playground in Nim mode and verify electrobun-wgpu initializes through the Nim host bridge.",
    kind: wgpu_tag_playground_integration
  ),
  NimTest(
    id: "nim-wgpu-tag-playground",
    name: "WGPU Tag playground (Nim)",
    category: "WGPU Tag (Interactive)",
    description: "Open the real WGPU tag playground and keep it open for manual interaction until the window is closed.",
    interactive: true,
    mirrors_bun_test_name: "WGPU Tag playground",
    kind: wgpu_tag_playground_interactive
  ),
  NimTest(
    id: "nim-navigation-load-url",
    name: "loadURL (Nim)",
    category: "Navigation",
    description: "Load a new internal URL into a BrowserView in Nim mode.",
    mirrors_bun_test_name: "loadURL",
    kind: navigation_load_url
  ),
  NimTest(
    id: "nim-navigation-load-html",
    name: "loadHTML (Nim)",
    category: "Navigation",
    description: "Load inline HTML into a BrowserView in Nim mode.",
    mirrors_bun_test_name: "loadHTML",
    kind: navigation_load_html
  ),
  NimTest(
    id: "nim-navigation-dom-ready-event",
    name: "dom-ready event (Nim)",
    category: "Navigation",
    description: "Verify dom-ready is emitted for BrowserView navigation in Nim mode.",
    mirrors_bun_test_name: "dom-ready event",
    kind: navigation_dom_ready_event
  ),
  NimTest(
    id: "nim-navigation-did-navigate-event",
    name: "did-navigate event (Nim)",
    category: "Navigation",
    description: "Verify did-navigate is emitted for BrowserView navigation in Nim mode.",
    mirrors_bun_test_name: "did-navigate event",
    kind: navigation_did_navigate_event
  ),
  NimTest(
    id: "nim-navigation-did-commit-navigation-event",
    name: "did-commit-navigation event (Nim)",
    category: "Navigation",
    description: "Verify did-commit-navigation crosses the Nim callback boundary before load completion.",
    mirrors_bun_test_name: "did-commit-navigation event",
    kind: navigation_did_commit_navigation_event
  ),
  NimTest(
    id: "nim-navigation-execute-javascript",
    name: "executeJavascript (fire and forget) (Nim)",
    category: "Navigation",
    description: "Execute JavaScript in a BrowserView without waiting for a response.",
    mirrors_bun_test_name: "executeJavascript (fire and forget)",
    kind: navigation_execute_javascript
  ),
  NimTest(
    id: "nim-tray-visibility-toggle-bounds",
    name: "Tray visibility toggle and bounds (Nim)",
    category: "Tray",
    description: "Create a tray item, toggle visibility, and read bounds in Nim mode.",
    mirrors_bun_test_name: "Tray visibility toggle and bounds",
    kind: tray_visibility_toggle_and_bounds
  ),
  NimTest(
    id: "nim-session-from-partition",
    name: "Session.fromPartition (Nim)",
    category: "Session",
    description: "Create an Nim session wrapper for a persistent partition.",
    mirrors_bun_test_name: "Session.fromPartition",
    kind: session_from_partition
  ),
  NimTest(
    id: "nim-session-default-session",
    name: "Session.defaultSession (Nim)",
    category: "Session",
    description: "Create the default Nim session wrapper.",
    mirrors_bun_test_name: "Session.defaultSession",
    kind: session_default_session
  ),
  NimTest(
    id: "nim-session-cookies-api-exists",
    name: "cookies API exists (Nim)",
    category: "Session",
    description: "Exercise the Nim session cookie helpers without mutating user state.",
    mirrors_bun_test_name: "cookies API exists",
    kind: session_cookies_api_exists
  ),
  NimTest(
    id: "nim-application-menu-playground",
    name: "Application menu playground (Nim)",
    category: "Menus (Interactive)",
    description: "Open the real application-menu playground in Nim mode and keep it open for manual interaction.",
    interactive: true,
    mirrors_bun_test_name: "Application menu playground",
    kind: application_menu_playground
  ),
  NimTest(
    id: "nim-context-menu-playground",
    name: "Context menu playground (Nim)",
    category: "Menus (Interactive)",
    description: "Open the real context-menu playground in Nim mode and keep it open for manual interaction.",
    interactive: true,
    mirrors_bun_test_name: "Context menu playground",
    kind: context_menu_playground
  ),
  NimTest(
    id: "nim-dialog-show-message-box-info",
    name: "showMessageBox - info dialog (Nim)",
    category: "Dialogs (Interactive)",
    description: "Show a native info dialog through the Nim SDK and pass after the user clicks a button.",
    interactive: true,
    mirrors_bun_test_name: "showMessageBox - info dialog",
    kind: dialog_show_message_box_info
  ),
  NimTest(
    id: "nim-dialog-file-dialog-playground",
    name: "File dialog playground (Nim)",
    category: "Dialogs (Interactive)",
    description: "Open the real file-dialog playground in Nim mode and keep it open for manual interaction.",
    interactive: true,
    mirrors_bun_test_name: "File dialog playground",
    kind: dialog_file_dialog_playground
  ),
  NimTest(
    id: "nim-global-shortcuts-playground",
    name: "Global shortcuts playground (Nim)",
    category: "Shortcuts (Interactive)",
    description: "Open the real shortcuts playground in Nim mode and keep it open for manual interaction.",
    interactive: true,
    mirrors_bun_test_name: "Global shortcuts playground",
    kind: global_shortcuts_playground
  ),
  NimTest(
    id: "nim-global-shortcut-is-registered-api",
    name: "GlobalShortcut.isRegistered API (Nim)",
    category: "Shortcuts",
    description: "Verify Nim global shortcut registration state tracking.",
    mirrors_bun_test_name: "GlobalShortcut.isRegistered API",
    kind: global_shortcut_is_registered_api
  ),
  NimTest(
    id: "nim-global-shortcut-unregister-all-api",
    name: "GlobalShortcut.unregisterAll API (Nim)",
    category: "Shortcuts",
    description: "Verify Nim global shortcut unregisterAll clears registered accelerators.",
    mirrors_bun_test_name: "GlobalShortcut.unregisterAll API",
    kind: global_shortcut_unregister_all_api
  ),
  NimTest(
    id: "nim-lifecycle-before-quit-cancel",
    name: "before-quit event can cancel quit (Nim)",
    category: "App Lifecycle",
    description: "Verify an Nim before-quit handler can run and cancel shutdown.",
    mirrors_bun_test_name: "before-quit event can cancel quit",
    kind: lifecycle_before_quit_cancel
  ),
  NimTest(
    id: "nim-quit-shutdown-playground",
    name: "Quit/Shutdown playground (Nim)",
    category: "Quit (Interactive)",
    description: "Open the real quit-test playground in Nim mode and keep it open for manual interaction.",
    interactive: true,
    mirrors_bun_test_name: "Quit/Shutdown playground",
    kind: quit_shutdown_playground
  ),
  NimTest(
    id: "nim-wgpu-adapter-context-device",
    name: "WebGPU adapter: context/device init (Nim)",
    category: "WebGPU",
    description: "Create a native WGPU view, then build a direct Nim WGPU context and device pointer pair.",
    kind: wgpu_adapter_context_device
  ),
  NimTest(
    id: "nim-dock-icon-visibility-contract",
    name: "Dock icon visibility contract (Nim)",
    category: "Utils",
    description: "Exercise dock icon visibility controls from the Nim SDK.",
    mirrors_bun_test_name: "Dock icon visibility contract",
    kind: dock_icon_visibility_contract
  ),
  NimTest(
    id: "nim-utils-clipboard-round-trip",
    name: "clipboardWriteText and clipboardReadText (Nim)",
    category: "Utils",
    description: "Write and read clipboard text through the Nim SDK.",
    mirrors_bun_test_name: "clipboardWriteText and clipboardReadText",
    kind: utils_clipboard_round_trip
  ),
  NimTest(
    id: "nim-utils-clipboard-available-formats",
    name: "clipboardAvailableFormats (Nim)",
    category: "Utils",
    description: "Read clipboard formats through the Nim SDK.",
    mirrors_bun_test_name: "clipboardAvailableFormats",
    kind: utils_clipboard_available_formats
  ),
  NimTest(
    id: "nim-utils-clipboard-clear",
    name: "clipboardClear (Nim)",
    category: "Utils",
    description: "Clear clipboard text through the Nim SDK.",
    mirrors_bun_test_name: "clipboardClear",
    kind: utils_clipboard_clear
  ),
  NimTest(
    id: "nim-utils-show-notification",
    name: "showNotification (Nim)",
    category: "Utils",
    description: "Send a desktop notification through the Nim SDK.",
    mirrors_bun_test_name: "showNotification",
    kind: utils_show_notification
  ),
  NimTest(
    id: "nim-utils-open-external-exists",
    name: "openExternal (Nim)",
    category: "Utils",
    description: "Verify the Nim SDK exposes openExternal without invoking side effects.",
    mirrors_bun_test_name: "openExternal",
    kind: utils_open_external_exists
  ),
  NimTest(
    id: "nim-utils-open-path-exists",
    name: "openPath (Nim)",
    category: "Utils",
    description: "Verify the Nim SDK exposes openPath without invoking side effects.",
    mirrors_bun_test_name: "openPath",
    kind: utils_open_path_exists
  ),
  NimTest(
    id: "nim-utils-show-item-in-folder-exists",
    name: "showItemInFolder (Nim)",
    category: "Utils",
    description: "Verify the Nim SDK exposes showItemInFolder without invoking side effects.",
    mirrors_bun_test_name: "showItemInFolder",
    kind: utils_show_item_in_folder_exists
  ),
  NimTest(
    id: "nim-utils-quit-function-exists",
    name: "quit function exists (Nim)",
    category: "Utils",
    description: "Verify the Nim SDK exposes a quit helper without invoking it.",
    mirrors_bun_test_name: "quit function exists",
    kind: utils_quit_exists
  ),
  NimTest(
    id: "nim-utils-paths-object-exists",
    name: "paths object exists (Nim)",
    category: "Utils",
    description: "Resolve the Nim SDK paths object and verify it is populated.",
    mirrors_bun_test_name: "paths object exists",
    kind: utils_paths_object_exists
  ),
  NimTest(
    id: "nim-utils-paths-home-matches",
    name: "paths.home matches os.homedir() (Nim)",
    category: "Utils",
    description: "Verify Nim SDK paths.home matches the process home directory.",
    mirrors_bun_test_name: "paths.home matches os.homedir()",
    kind: utils_paths_home_matches
  ),
  NimTest(
    id: "nim-utils-paths-temp-matches",
    name: "paths.temp matches os.tmpdir() (Nim)",
    category: "Utils",
    description: "Verify Nim SDK paths.temp matches the process temp directory.",
    mirrors_bun_test_name: "paths.temp matches os.tmpdir()",
    kind: utils_paths_temp_matches
  ),
  NimTest(
    id: "nim-utils-paths-os-directories",
    name: "paths OS directories return non-empty strings (Nim)",
    category: "Utils",
    description: "Verify the Nim SDK resolves non-empty OS-level directories.",
    mirrors_bun_test_name: "paths OS directories return non-empty strings",
    kind: utils_paths_os_directories
  ),
  NimTest(
    id: "nim-utils-paths-app-scoped-directories",
    name: "paths app-scoped directories return non-empty strings (Nim)",
    category: "Utils",
    description: "Verify the Nim SDK resolves non-empty app-scoped data/cache/log directories.",
    mirrors_bun_test_name: "paths app-scoped directories return non-empty strings",
    kind: utils_paths_app_scoped_directories
  ),
  NimTest(
    id: "nim-utils-paths-stable-across-calls",
    name: "paths getters are stable across calls (Nim)",
    category: "Utils",
    description: "Verify repeated Nim SDK path resolution returns the same string values.",
    mirrors_bun_test_name: "paths getters are stable across calls",
    kind: utils_paths_stable_across_calls
  ),
  NimTest(
    id: "nim-utils-move-to-trash",
    name: "moveToTrash (Nim)",
    category: "Utils",
    description: "Move a temporary file to trash through the Nim SDK.",
    mirrors_bun_test_name: "moveToTrash",
    kind: utils_move_to_trash
  ),
  NimTest(
    id: "nim-screen-primary-display",
    name: "getPrimaryDisplay (Nim)",
    category: "Screen",
    description: "Read the primary display through the Nim SDK.",
    mirrors_bun_test_name: "getPrimaryDisplay",
    kind: screen_primary_display
  ),
  NimTest(
    id: "nim-screen-all-displays",
    name: "getAllDisplays (Nim)",
    category: "Screen",
    description: "Read all connected displays through the Nim SDK.",
    mirrors_bun_test_name: "getAllDisplays",
    kind: screen_all_displays
  ),
  NimTest(
    id: "nim-screen-cursor-screen-point",
    name: "getCursorScreenPoint (Nim)",
    category: "Screen",
    description: "Read the current cursor position through the Nim SDK.",
    mirrors_bun_test_name: "getCursorScreenPoint",
    kind: screen_cursor_screen_point
  ),
  NimTest(
    id: "nim-screen-capture-region",
    name: "captureRegion (Nim)",
    category: "Screen",
    description: "Capture a small screen region as row-major RGBA pixels through the Nim SDK.",
    mirrors_bun_test_name: "captureRegion",
    kind: screen_capture_region
  ),
  NimTest(
    id: "nim-screen-bounds-vs-workarea",
    name: "Display bounds vs workArea (Nim)",
    category: "Screen",
    description: "Verify primary display workArea fits within bounds in Nim mode.",
    mirrors_bun_test_name: "Display bounds vs workArea",
    kind: screen_bounds_vs_workarea
  )
]

type
  ChildWebviewState* = object
    renderer*: Renderer

type
  AppState* = object
    allocator*: string
    core*: Core
    bundlePaths*: BundlePaths
    appInfo*: AppInfo
    defaultRenderer*: Renderer
    cefAvailable*: bool
    cefVersion*: Option[string]
    childWebviews*: Table[uint32, ChildWebviewState]
    topLevelWebviewWindows*: Table[uint32, uint32]
    testRunnerWindowId*: uint32
    testRunnerWebviewId*: uint32
    searchQuery*: Option[string]
    autoRunTestName*: Option[string]
    autoRunAll*: bool
    autoRunTriggered*: bool
    applicationMenuTargetWebviewId*: uint32
    contextMenuTargetWebviewId*: uint32
    shortcutTargetWebviewId*: uint32
    quitTargetWebviewId*: uint32
    beforeQuitShouldCancel*: bool
    menuDataCounter*: uint32
    menuDataRegistry*: Table[string, string]
    mutex*: Lock

var gCallbackStateLock = Lock()
var gState: ptr AppState
var hostQueueRunning: Atomic[bool]

proc appStateDeinit*(self: var AppState) =
  self.mutex.acquire()
  defer:
    self.mutex.release()
  self.searchQuery = none(string)
  self.autoRunTestName = none(string)
  self.cefVersion = none(string)
  self.menuDataRegistry.clear()
  self.childWebviews.clear()
  self.topLevelWebviewWindows.clear()

type
  CreateUiContext* = object
    state*: ptr AppState


type
  SingleTestJob* = object
    webviewId*: uint32
    requestId*: Option[uint64]
    nimTest*: NimTest


type
  AllTestsJob* = object
    webviewId*: uint32
    requestId*: Option[uint64]
    interactiveOnly*: bool

proc appState(): ptr AppState =
  if gState == nil:
    raiseAssert("electrobun kitchen nim state not initialized")
  return gState

proc errName(err: EbError): string =
  case err
  of ebNone: "None"
  of ebMissingCoreSymbol: "MissingCoreSymbol"
  of ebLibraryLoadFailed: "LibraryLoadFailed"
  of ebElectrobunCoreFailure: "ElectrobunCoreFailure"
  of ebInvalidScreenCaptureRegion: "InvalidScreenCaptureRegion"
  of ebAllocationFailed: "AllocationFailed"
  of ebInvalidExePath: "InvalidExePath"
  of ebInvalidRectJson: "InvalidRectJson"
  of ebInvalidJson: "InvalidJson"
  of ebFileReadFailed: "FileReadFailed"
  of ebEnvVarNotFound: "EnvVarNotFound"
  else: "UnknownError"

proc testRunnerHostBridge(webviewId: uint32; message: cstring) {.cdecl.}

template webviewBridgeHandler*(fn: untyped): WebviewPostMessageHandler =
  cast[WebviewPostMessageHandler](fn)

template webviewEventHandler*(fn: untyped): WebviewEventHandler =
  cast[WebviewEventHandler](fn)

template statusItemHandler*(fn: untyped): StatusItemHandler =
  cast[StatusItemHandler](fn)

template cHandler*(T: typedesc; fn: untyped): T =
  cast[T](fn)

proc drainHostMessageQueue() =
  while hostQueueRunning.load(moAcquire):
    let state = gState
    if state.isNil:
      sleep(10)
      continue
    var drainedAny = false
    while hostQueueRunning.load(moAcquire):
      var webviewId: uint32 = 0
      let message = state.core.popNextQueuedHostMessage(webviewId)
      if message.isNil:
        break
      testRunnerHostBridge(webviewId, message)
      state.core.freeCoreString(message)
      drainedAny = true
    if not drainedAny:
      sleep(10)

proc configureRuntimeBuildConfig(state: var AppState): string =
  let buildJsonPath = joinPath(state.bundlePaths.resourcesDir, "build.json")
  let buildJson = try:
    readFile(buildJsonPath)
  except IOError:
    return "BuildJsonReadFailed"
  let parsed = try:
    parseJson(buildJson)
  except JsonParsingError:
    return "BuildJsonParseFailed"
  if parsed.kind != JObject:
    return ""
  if "defaultRenderer" in parsed and parsed["defaultRenderer"].kind == JString and
      parsed["defaultRenderer"].getStr() == "cef":
    state.defaultRenderer = rCef
  if "availableRenderers" in parsed and parsed["availableRenderers"].kind == JArray:
    for rendererValue in parsed["availableRenderers"]:
      if rendererValue.kind == JString and rendererValue.getStr() == "cef":
        state.cefAvailable = true
        break
  if "cefVersion" in parsed and parsed["cefVersion"].kind == JString:
    state.cefVersion = some(parsed["cefVersion"].getStr())
  return ""

proc buildConfigPayload(): BuildConfigPayload =
  let state = appState()
  let renderers = if state.cefAvailable: availableRenderersCef else: availableRenderersNative
  BuildConfigPayload(
    defaultRenderer: rendererName(state.defaultRenderer),
    availableRenderers: renderers,
    mainProcess: "nim",
    cefVersion: state.cefVersion,
    nimVersion: some(NimVersion),
  )

proc updateInfoPayload(): UpdateInfo =
  UpdateInfo(status: "no-update", currentVersion: appVersion, newVersion: none(string), error: none(string))

type
  RpcErrorPacket* = object
    packetType*: string
    id*: uint64
    success*: bool
    error*: string



type
  EmptyPayload* = object


type
  TestStartedPayload* = object
    testId*: string
    name*: string


type
  TestLogPayload* = object
    testId*: string
    message*: string


type
  TestCompletedPayload* = object
    testId*: string
    result*: TestResult


type
  AllCompletedPayload* = object
    results*: seq[TestResult]


type
  SearchPreferencesPayload* = object
    searchQuery*: string


type
  SuccessPayload* = object
    success*: bool


type
  RegisteredPayload* = object
    registered*: bool


type
  SuccessMessagePayload* = object
    success*: bool
    message*: string


type
  ActionPayload* = object
    action*: string


type
  ActionDataPayload* = object
    action*: string
    data*: JsonNode


type
  AcceleratorPayload* = object
    accelerator*: string


type
  MessagePayload* = object
    message*: string


proc sendRpcMessage*[T](webviewId: uint32; messageId: string; payload: T) =
  let packet = %*{"type": "message", "id": messageId, "payload": payload}
  let err = appState().core.sendHostMessageToWebviewJson(webviewId, packet)
  if err != ebNone:
    stderr.writeLine(fmt"[kitchen nim] failed to send RPC message '{messageId}': {errName(err)}")

proc sendRpcResponseSuccess*[T](webviewId: uint32; requestId: uint64; payload: T) =
  let packet = %*{"type": "response", "id": requestId, "success": true, "payload": payload}
  let err = appState().core.sendHostMessageToWebviewJson(webviewId, packet)
  if err != ebNone:
    stderr.writeLine(fmt"[kitchen nim] failed to send RPC response #{requestId}: {errName(err)}")

proc sendRpcResponseError(webviewId: uint32; requestId: uint64; errorMessage: string) =
  let packet = %*{"type": "response", "id": requestId, "success": false, "error": errorMessage}
  let err = appState().core.sendHostMessageToWebviewJson(webviewId, packet)
  if err != ebNone:
    stderr.writeLine(fmt"[kitchen nim] failed to send RPC error #{requestId}: {errName(err)}")

proc sendBuildConfig(webviewId: uint32) =
  sendRpcMessage(webviewId, "buildConfig", buildConfigPayload())

proc sendUpdateStatus(webviewId: uint32) =
  sendRpcMessage(webviewId, "updateStatus", updateInfoPayload())

proc sendInitialUiState(webviewId: uint32) =
  sendBuildConfig(webviewId)
  sendUpdateStatus(webviewId)

proc sendTestLog(webviewId: uint32; testId: string; message: string) =
  sendRpcMessage(webviewId, "testLog", TestLogPayload(testId: testId, message: message))

proc findTestById(testId: string): (NimTest, bool) =
  for nimTest in nimTests:
    if nimTest.id == testId:
      return (nimTest, true)
  return (default(NimTest), false)

proc findTestByName(testName: string): (NimTest, bool) =
  for nimTest in nimTests:
    if nimTest.name == testName:
      return (nimTest, true)
  return (default(NimTest), false)

proc getSearchQuery(): string =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  if state.searchQuery.isSome:
    return state.searchQuery.get()
  return ""

proc setSearchQuery(next: string) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.searchQuery = some(next)

proc getJsonStringField(obj: JsonNode; key: string): (string, bool) =
  if key notin obj:
    return ("", false)
  let value = obj[key]
  if value.kind != JString:
    return ("", false)
  return (value.getStr(), true)

proc getJsonBoolField(obj: JsonNode; key: string; defaultValue: bool): bool =
  if key notin obj:
    return defaultValue
  let value = obj[key]
  if value.kind != JBool:
    return defaultValue
  return value.getBool()

proc getJsonF64Field(obj: JsonNode; key: string; defaultValue: float64): float64 =
  if key notin obj:
    return defaultValue
  let value = obj[key]
  case value.kind
  of JFloat: value.getFloat()
  of JInt: value.getFloat()
  else: defaultValue

proc getJsonU32Field(obj: JsonNode; key: string; defaultValue: uint32): uint32 =
  if key notin obj:
    return defaultValue
  let value = obj[key]
  if value.kind == JInt and value.getInt() >= 0:
    return uint32(value.getInt())
  return defaultValue

proc rectFromJsonObject(obj: JsonNode): Rect =
  Rect(
    x: getJsonF64Field(obj, "x", 0),
    y: getJsonF64Field(obj, "y", 0),
    width: getJsonF64Field(obj, "width", 0),
    height: getJsonF64Field(obj, "height", 0),
  )

proc milliTimestamp(): int64 =
  int64(epochTime() * 1000.0)

type
  WindowWithWebview* = object
    windowId*: uint32
    webviewId*: uint32


type
  CallbackState* = object
    mutex*: Lock
    window_close_count*: uint32
    window_should_close_count*: uint32
    window_resize_count*: uint32
    window_focus_count*: uint32
    last_resize_width*: float64
    last_resize_height*: float64
    webview_will_navigate_count*: uint32
    webview_did_navigate_count*: uint32
    webview_did_commit_navigation_count*: uint32
    webview_dom_ready_count*: uint32
    webview_tag_init_count*: uint32
    wgpu_tag_init_count*: uint32
    wgpu_tag_ready_count*: uint32
    before_quit_count*: uint32
    reopen_count*: uint32
    url_open_count*: uint32
    last_open_url*: array[1024, uint8]
    last_open_url_len*: int
    last_webview_detail*: array[1024, uint8]
    last_webview_detail_len*: int


var gCallbackState: CallbackState

# Slow Windows-VM CEF fires OnLoadStart/OnLoadEnd ~3x later than
# Linux/macOS CEF, so scale every hard-coded sleep budget in the Odin
# harness with the same factor the JS/Rust/Go harnesses use.
proc slowPlatformScale(): uint64 =
  when defined(windows):
    3'u64
  else:
    1'u64

proc sleepMs(ms: uint64) =
  sleep(int(ms * slowPlatformScale()))

proc approxEq(a: float64, b: float64, tolerance: float64): bool =
  return abs(a - b) <= tolerance

proc resetCallbackState() =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.window_close_count = 0
  gCallbackState.window_should_close_count = 0
  gCallbackState.window_resize_count = 0
  gCallbackState.window_focus_count = 0
  gCallbackState.last_resize_width = 0
  gCallbackState.last_resize_height = 0
  gCallbackState.webview_will_navigate_count = 0
  gCallbackState.webview_did_navigate_count = 0
  gCallbackState.webview_did_commit_navigation_count = 0
  gCallbackState.webview_dom_ready_count = 0
  gCallbackState.webview_tag_init_count = 0
  gCallbackState.wgpu_tag_init_count = 0
  gCallbackState.wgpu_tag_ready_count = 0
  gCallbackState.before_quit_count = 0
  gCallbackState.reopen_count = 0
  gCallbackState.url_open_count = 0
  gCallbackState.last_open_url_len = 0
  gCallbackState.last_webview_detail_len = 0

proc getWindowCloseCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.window_close_count

proc getWindowShouldCloseCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.window_should_close_count

proc getWindowResizeCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.window_resize_count

proc getWindowFocusCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.window_focus_count

proc getLastResizeSize(): Rect =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return Rect(
    width: gCallbackState.last_resize_width,
    height: gCallbackState.last_resize_height,
  )

proc getWebviewWillNavigateCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.webview_will_navigate_count

proc getWebviewDidNavigateCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.webview_did_navigate_count

proc getWebviewDidCommitNavigationCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.webview_did_commit_navigation_count

proc getWebviewDomReadyCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.webview_dom_ready_count

proc getWebviewTagInitCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.webview_tag_init_count

proc getWgpuTagInitCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.wgpu_tag_init_count

proc getWgpuTagReadyCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.wgpu_tag_ready_count

proc getBeforeQuitCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.before_quit_count

proc getReopenCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.reopen_count

proc getUrlOpenCount(): uint32 =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return gCallbackState.url_open_count

proc bytesToString(data: array[1024, uint8]; len: int): string =
  if len <= 0:
    return ""
  result = newString(len)
  copyMem(result[0].addr, addr data[0], len)

proc getLastOpenUrl(): string =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  return bytesToString(gCallbackState.last_open_url, gCallbackState.last_open_url_len)

proc lastWebviewDetailContains(needle: string): bool =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  let detail = bytesToString(gCallbackState.last_webview_detail, gCallbackState.last_webview_detail_len)
  return needle in detail

proc observedWindowClose(_: uint32) {.cdecl.} =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.window_close_count += 1

proc observedWindowShouldClose(windowId: uint32) {.cdecl.} =
  gCallbackStateLock.acquire()
  gCallbackState.window_should_close_count += 1
  let shouldAllow = gCallbackState.window_should_close_count > 1
  gCallbackStateLock.release()
  if shouldAllow:
    discard appState().core.closeWindow(windowId)

proc observedWindowResize(_: uint32; _: float64; _: float64; width: float64; height: float64) {.cdecl.} =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.window_resize_count += 1
  gCallbackState.last_resize_width = width
  gCallbackState.last_resize_height = height

proc observedWindowFocus(_: uint32) {.cdecl.} =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.window_focus_count += 1

proc recordObservedWebviewEvent(eventNameSlice: string; detailSlice: string) =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  if eventNameSlice == "will-navigate":
    gCallbackState.webview_will_navigate_count += 1
  elif eventNameSlice == "did-navigate":
    gCallbackState.webview_did_navigate_count += 1
  elif eventNameSlice == "did-commit-navigation":
    gCallbackState.webview_did_commit_navigation_count += 1
  elif eventNameSlice == "dom-ready":
    gCallbackState.webview_dom_ready_count += 1
  let copyLen = min(detailSlice.len, gCallbackState.last_webview_detail.len - 1)
  if copyLen > 0:
    copyMem(addr gCallbackState.last_webview_detail[0], unsafeAddr detailSlice[0], copyLen)
  gCallbackState.last_webview_detail_len = copyLen
  if copyLen < gCallbackState.last_webview_detail.len:
    gCallbackState.last_webview_detail[copyLen] = 0

proc recordWebviewTagInit() =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.webview_tag_init_count += 1

proc recordWgpuTagInit() =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.wgpu_tag_init_count += 1

proc recordWgpuTagReady() =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.wgpu_tag_ready_count += 1

proc recordBeforeQuit() =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.before_quit_count += 1

proc recordReopen() =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.reopen_count += 1

proc recordUrlOpen(url: string) =
  gCallbackStateLock.acquire()
  defer:
    gCallbackStateLock.release()
  gCallbackState.url_open_count += 1
  let copyLen = min(url.len, gCallbackState.last_open_url.len - 1)
  if copyLen > 0:
    copyMem(addr gCallbackState.last_open_url[0], unsafeAddr url[0], copyLen)
  gCallbackState.last_open_url_len = copyLen
  if copyLen < gCallbackState.last_open_url.len:
    gCallbackState.last_open_url[copyLen] = 0

proc observedWebviewEvent(_: uint32; eventName: cstring; detail: cstring) {.cdecl.} =
  recordObservedWebviewEvent($eventName, $detail)

proc observedWebviewBridge(_: uint32; message: cstring) {.cdecl.} =
  let messageSlice = $message
  if messageSlice.len == 0:
    return
  let parsed =
    try:
      parseJson(messageSlice)
    except JsonParsingError:
      return
  if parsed.kind != JObject:
    return
  let (idString, idIsString) = getJsonStringField(parsed, "id")
  let (typeString, typeIsString) = getJsonStringField(parsed, "type")
  if not idIsString or not typeIsString:
    return
  if idString != "webviewEvent" or typeString != "message":
    return
  if "payload" notin parsed:
    return
  let payloadObj = parsed["payload"]
  if payloadObj.kind != JObject:
    return
  let (eventName, hasEventName) = getJsonStringField(payloadObj, "eventName")
  let (detail, hasDetail) = getJsonStringField(payloadObj, "detail")
  if not hasEventName or not hasDetail:
    return
  recordObservedWebviewEvent(eventName, detail)

proc childWebviewRenderer(webviewId: uint32): Renderer =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  if webviewId in state.childWebviews:
    return state.childWebviews[webviewId].renderer
  rNative

proc rememberChildWebview(webviewId: uint32; renderer: Renderer) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.childWebviews[webviewId] = ChildWebviewState(renderer: renderer)

proc forgetChildWebview(webviewId: uint32) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.childWebviews.del(webviewId)
  
const electrobunMenuDelimiter = "|EB|"

proc rememberTopLevelWebview(webviewId: uint32; windowId: uint32) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.topLevelWebviewWindows[webviewId] = windowId

proc forgetTopLevelWebview(webviewId: uint32) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.topLevelWebviewWindows.del(webviewId)

proc windowIdForTopLevelWebview(webviewId: uint32): (uint32, bool) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  if webviewId in state.topLevelWebviewWindows:
    return (state.topLevelWebviewWindows[webviewId], true)
  (0'u32, false)

proc clearChildWebviews() =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.childWebviews.clear()

proc activePlaygroundRenderer(state: ptr AppState): Renderer =
  if state[].cefAvailable and state[].defaultRenderer == rCef:
    rCef
  else:
    rNative

proc defaultMenuRoleLabel(role: string): (string, bool) =
  case role
  of "about": ("About", true)
  of "quit": ("Quit", true)
  of "hide": ("Hide", true)
  of "hideOthers": ("Hide Others", true)
  of "showAll": ("Show All", true)
  of "minimize": ("Minimize", true)
  of "zoom": ("Zoom", true)
  of "close": ("Close", true)
  of "bringAllToFront": ("Bring All To Front", true)
  of "cycleThroughWindows": ("Cycle Through Windows", true)
  of "enterFullScreen": ("Enter Full Screen", true)
  of "exitFullScreen": ("Exit Full Screen", true)
  of "toggleFullScreen": ("Toggle Full Screen", true)
  of "undo": ("Undo", true)
  of "redo": ("Redo", true)
  of "cut": ("Cut", true)
  of "copy": ("Copy", true)
  of "paste": ("Paste", true)
  of "pasteAndMatchStyle": ("Paste and Match Style", true)
  of "delete": ("Delete", true)
  of "selectAll": ("Select All", true)
  of "startSpeaking": ("Start Speaking", true)
  of "stopSpeaking": ("Stop Speaking", true)
  of "showHelp": ("Show Help", true)
  else: ("", false)

proc setApplicationMenuTargetWebview(webviewId: uint32) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.applicationMenuTargetWebviewId = webviewId

proc applicationMenuTargetWebview(): uint32 =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.applicationMenuTargetWebviewId

proc setContextMenuTargetWebview(webviewId: uint32) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.contextMenuTargetWebviewId = webviewId

proc contextMenuTargetWebview(): uint32 =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.contextMenuTargetWebviewId

proc setShortcutTargetWebview(webviewId: uint32) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.shortcutTargetWebviewId = webviewId

proc shortcutTargetWebview(): uint32 =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.shortcutTargetWebviewId

proc setQuitTargetWebview(webviewId: uint32) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.quitTargetWebviewId = webviewId

proc quitTargetWebview(): uint32 =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.quitTargetWebviewId

proc setBeforeQuitShouldCancel(cancel: bool) =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.beforeQuitShouldCancel = cancel

proc getBeforeQuitShouldCancel(): bool =
  let state = appState()
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.beforeQuitShouldCancel

proc storeMenuData(value: JsonNode): (string, bool) =
  let state = appState()
  let dataJson = $value
  state.mutex.acquire()
  defer:
    state.mutex.release()
  state.menuDataCounter += 1
  let dataId = &"menuData_{state.menuDataCounter}"
  state.menuDataRegistry[dataId] = dataJson
  (dataId, true)

proc appendJsonString(b: var string; value: string) =
  b.add($(%value))

proc writeMarshaledValue(b: var string; value: JsonNode): bool =
  b.add($value)
  true

proc writeMenuValue(b: var string; value: JsonNode): bool
proc writeMenuObject(b: var string; obj: JsonNode): bool

proc writeMenuValue(b: var string; value: JsonNode): bool =
  case value.kind
  of JArray:
    b.add('[')
    for i in 0 ..< value.len:
      if i > 0:
        b.add(',')
      if not writeMenuValue(b, value[i]):
        return false
    b.add(']')
    true
  of JObject:
    writeMenuObject(b, value)
  else:
    writeMarshaledValue(b, value)

proc writeMenuObject(b: var string; obj: JsonNode): bool =
  var encodedAction = ""
  var hasEncodedAction = false
  if "action" in obj and obj["action"].kind == JString:
    let actionString = obj["action"].getStr()
    if "data" in obj:
      let (dataId, stored) = storeMenuData(obj["data"])
      if not stored:
        return false
      encodedAction = fmt"{electrobunMenuDelimiter}{dataId}|{actionString}"
      hasEncodedAction = true
  b.add('{')
  var first = true
  for key, val in obj.pairs:
    if not first:
      b.add(',')
    var first = false
    appendJsonString(b, key)
    b.add(':')
    if key == "submenu":
      if not writeMenuValue(b, val):
        return false
    elif key == "action" and hasEncodedAction:
      appendJsonString(b, encodedAction)
    elif not writeMarshaledValue(b, val):
      return false
  if "enabled" notin obj:
    if not first:
      b.add(',')
    var first = false
    b.add("\"enabled\":true")
  if "checked" notin obj:
    if not first:
      b.add(',')
    var first = false
    b.add("\"checked\":false")
  if "hidden" notin obj:
    if not first:
      b.add(',')
    var first = false
    b.add("\"hidden\":false")
  if "type" notin obj:
    var typeName = "normal"
    if "submenu" in obj:
      typeName = "submenu"
    elif "label" in obj and obj["label"].kind == JString:
      let labelString = obj["label"].getStr()
      if labelString.len == 0 or labelString == "-":
        typeName = "divider"
    if not first:
      b.add(',')
    var first = false
    b.add("\"type\":")
    appendJsonString(b, typeName)
  if "label" notin obj and "role" in obj and obj["role"].kind == JString:
    let (label, labelFound) = defaultMenuRoleLabel(obj["role"].getStr())
    if labelFound:
      if not first:
        b.add(',')
      first = false
      b.add("\"label\":")
      appendJsonString(b, label)
  b.add('}')
  true

proc prepareMenuJson(menuValue: JsonNode): (string, bool) =
  var b = ""
  if not writeMenuValue(b, menuValue):
    return ("", false)
  (b, true)

proc sendMenuClick(webviewId: uint32; messageId: string; encodedAction: string) =
  if webviewId == 0:
    return
  if not encodedAction.startsWith(electrobunMenuDelimiter):
    sendRpcMessage(webviewId, messageId, ActionPayload(action: encodedAction))
    return
  let remainder = encodedAction[electrobunMenuDelimiter.len .. ^1]
  let separatorIndex = remainder.find('|')
  if separatorIndex < 0:
    sendRpcMessage(webviewId, messageId, ActionPayload(action: encodedAction))
    return
  let dataId = remainder[0 ..< separatorIndex]
  let action = remainder[separatorIndex + 1 .. ^1]
  var removedValue = ""
  block:
    let state = appState()
    state.mutex.acquire()
    if dataId in state.menuDataRegistry:
      removedValue = state.menuDataRegistry[dataId]
      state.menuDataRegistry.del(dataId)
    state.mutex.release()
  if removedValue.len > 0:
    let parsed =
      try:
        parseJson(removedValue)
      except JsonParsingError:
        sendRpcMessage(webviewId, messageId, ActionPayload(action: action))
        return
    sendRpcMessage(webviewId, messageId, ActionDataPayload(action: action, data: parsed))
    return
  sendRpcMessage(webviewId, messageId, ActionPayload(action: action))

proc applicationMenuHandler(_: uint32; encodedAction: cstring) {.cdecl.} =
  sendMenuClick(applicationMenuTargetWebview(), "menuClicked", $encodedAction)

proc contextMenuHandler(_: uint32; encodedAction: cstring) {.cdecl.} =
  sendMenuClick(contextMenuTargetWebview(), "contextMenuClicked", $encodedAction)

proc shortcutTriggeredHandler(accelerator: cstring) {.cdecl.} =
  let webviewId = shortcutTargetWebview()
  if webviewId == 0:
    return
  sendRpcMessage(webviewId, "shortcutTriggered", AcceleratorPayload(accelerator: $accelerator))

proc quitRequestedHandler() {.cdecl.} =
  recordBeforeQuit()
  let webviewId = quitTargetWebview()
  if webviewId != 0:
    sendRpcMessage(
      webviewId,
      "beforeQuitFired",
      MessagePayload(message: "beforeQuit handler fired! Waiting 2 seconds for cleanup..."),
    )
  sleepMs(2000)
  if webviewId != 0:
    let doneMessage =
      if getBeforeQuitShouldCancel():
        "beforeQuit cleanup complete (2s elapsed). Quit cancelled in Nim mode."
      else:
        "beforeQuit cleanup complete (2s elapsed). Quitting now."
    sendRpcMessage(webviewId, "beforeQuitDone", MessagePayload(message: doneMessage))
  if not getBeforeQuitShouldCancel():
    appState().core.quitGracefully(0)

proc urlOpenHandler(url: cstring) {.cdecl.} =
  recordUrlOpen($url)

proc appReopenHandler() {.cdecl.} =
  when defined(macosx):
    discard appState().core.setDockIconVisible(true)
  recordReopen()

proc expandTildePathAlloc(path: string): (string, bool) =
  if path.len == 0 or path[0] != '~':
    return (path, true)
  let home = getEnv("HOME")
  if home.len == 0:
    return ("", false)
  if path.len == 1:
    return (home, true)
  if path.len >= 2 and path[1] == '/':
    return (home / path[2 .. ^1], true)
  (path, true)

proc sendInternalBridgeResponse*[T](hostWebviewId: uint32; requestId: string; success: bool; payload: T) =
  let packet = %*{"type": "response", "id": requestId, "success": success, "payload": payload}
  let err = appState().core.sendInternalMessageToWebviewJson(hostWebviewId, packet)
  if err != ebNone:
    stderr.writeLine(fmt"[kitchen nim] failed to send internal bridge response '{requestId}': {errName(err)}")

proc sendInternalBridgeError(hostWebviewId: uint32; requestId: string; message: string) =
  sendInternalBridgeResponse(hostWebviewId, requestId, false, message)

proc createChildWebviewFromInternalBridge(hostWebviewId: uint32; paramsObj: JsonNode): (uint32, string) =
  var (rendererString, hasRenderer) = getJsonStringField(paramsObj, "renderer")
  if not hasRenderer:
    var rendererString = "native"
  let renderer = if rendererString == "cef": rCef else: rNative
  let (url, hasUrl) = getJsonStringField(paramsObj, "url")
  let (html, hasHtml) = getJsonStringField(paramsObj, "html")
  var (preload, hasPreload) = getJsonStringField(paramsObj, "preload")
  if not hasPreload:
    var preload = ""
  var (partition, hasPartition) = getJsonStringField(paramsObj, "partition")
  if not hasPartition:
    var partition = "persist:default"
  let windowId = getJsonU32Field(paramsObj, "windowId", 0)
  let sandbox = getJsonBoolField(paramsObj, "sandbox", false)
  let transparent = getJsonBoolField(paramsObj, "transparent", false)
  let passthrough = getJsonBoolField(paramsObj, "passthrough", false)
  let spellCheck = getJsonBoolField(paramsObj, "spellCheck", false)
  if "frame" notin paramsObj:
    return (0'u32, "MissingFrame")
  let frameValue = paramsObj["frame"]
  if frameValue.kind != JObject:
    return (0'u32, "InvalidFrame")
  let frame = rectFromJsonObject(frameValue)
  let effectiveUrl =
    if hasUrl:
      url
    elif not hasHtml:
      "https://dev"
    else:
      ""
  var options = defaultWebviewOptions(windowId)
  options.hostWebviewId = hostWebviewId
  options.renderer = renderer
  options.url = effectiveUrl
  options.frame = frame
  options.autoResize = false
  options.partition = partition
  options.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: noopWebviewEvent,
    eventBridge: noopWebviewPostMessage,
    hostBridge: noopWebviewPostMessage,
    internalBridge: noopWebviewPostMessage,
  )
  options.secretKey = defaultSecretKey
  options.preload = preload
  options.sandbox = sandbox
  options.startTransparent = transparent
  options.startPassthrough = passthrough
  options.spellCheck = spellCheck
  let (webviewId, createErr) = appState().core.createWebview(options)
  if createErr != ebNone:
    return (0'u32, errName(createErr))
  rememberChildWebview(webviewId, renderer)
  recordWebviewTagInit()
  if hasHtml:
    if renderer == rCef:
      var err = appState().core.setWebviewHTMLContent(webviewId, html)
      if err != ebNone:
        return (0'u32, errName(err))
      err = appState().core.loadURLInWebview(webviewId, "views://internal/index.html")
      if err != ebNone:
        return (0'u32, errName(err))
    else:
      let err = appState().core.loadHTMLInWebview(webviewId, html)
      if err != ebNone:
        return (0'u32, errName(err))
  (webviewId, "")

proc createWgpuViewFromInternalBridge(paramsObj: JsonNode): (uint32, string) =
  let windowId = getJsonU32Field(paramsObj, "windowId", 0)
  let transparent = getJsonBoolField(paramsObj, "transparent", false)
  let passthrough = getJsonBoolField(paramsObj, "passthrough", false)
  if "frame" notin paramsObj:
    return (0'u32, "MissingFrame")
  let frameValue = paramsObj["frame"]
  if frameValue.kind != JObject:
    return (0'u32, "InvalidFrame")
  let frame = rectFromJsonObject(frameValue)
  var options = defaultWGPUViewOptions(windowId)
  options.frame = frame
  options.autoResize = false
  options.startTransparent = transparent
  options.startPassthrough = passthrough
  let (wgpuViewId, createErr) = appState().core.createWGPUView(options)
  if createErr != ebNone:
    return (0'u32, errName(createErr))
  recordWgpuTagInit()
  (wgpuViewId, "")

proc handleInternalBridgeRequest(hostWebviewId: uint32; requestId: string; bridgeMethod: string; paramsObj: JsonNode) =
  if bridgeMethod == "webviewTagInit":
    let (webviewId, errName) = createChildWebviewFromInternalBridge(hostWebviewId, paramsObj)
    if errName != "":
      sendInternalBridgeError(hostWebviewId, requestId, errName)
      return
    sendInternalBridgeResponse(hostWebviewId, requestId, true, webviewId)
    return
  if bridgeMethod == "webviewTagCanGoBack":
    sendInternalBridgeResponse(
      hostWebviewId,
      requestId,
      true,
      appState().core.canWebviewGoBack(getJsonU32Field(paramsObj, "id", 0)),
    )
    return
  if bridgeMethod == "webviewTagCanGoForward":
    sendInternalBridgeResponse(
      hostWebviewId,
      requestId,
      true,
      appState().core.canWebviewGoForward(getJsonU32Field(paramsObj, "id", 0)),
    )
    return
  if bridgeMethod == "webviewTagSetSpellCheck":
    let (supported, err) = appState().core.setWebviewSpellCheck(
      getJsonU32Field(paramsObj, "id", 0),
      getJsonBoolField(paramsObj, "enabled", false),
    )
    if err != ebNone:
      sendInternalBridgeError(hostWebviewId, requestId, errName(err))
      return
    sendInternalBridgeResponse(hostWebviewId, requestId, true, supported)
    return
  if bridgeMethod == "wgpuTagInit":
    let (wgpuViewId, errName) = createWgpuViewFromInternalBridge(paramsObj)
    if errName != "":
      sendInternalBridgeError(hostWebviewId, requestId, errName)
      return
    sendInternalBridgeResponse(hostWebviewId, requestId, true, wgpuViewId)
    return
  sendInternalBridgeError(hostWebviewId, requestId, "Unsupported internal bridge request")
  
proc frameAndMasksFromParams(paramsObj: JsonNode): (Rect, string, bool) =
  if "frame" notin paramsObj:
    return (default(Rect), "[]", false)
  let frameValue = paramsObj["frame"]
  if frameValue.kind != JObject:
    return (default(Rect), "[]", false)
  var (masks, hasMasks) = getJsonStringField(paramsObj, "masks")
  if not hasMasks:
    var masks = "[]"
  (rectFromJsonObject(frameValue), masks, true)

proc handleInternalBridgeMessage(messageId: string; paramsObj: JsonNode) =
  let webviewId = getJsonU32Field(paramsObj, "id", 0)
  if webviewId == 0:
    return
  let core = appState().core
  case messageId
  of "webviewTagResize":
    let (frame, masks, ok) = frameAndMasksFromParams(paramsObj)
    if ok:
      discard core.resizeWebview(webviewId, frame, masks)
  of "webviewTagUpdateSrc":
    let (url, hasUrl) = getJsonStringField(paramsObj, "url")
    if hasUrl:
      discard core.loadURLInWebview(webviewId, url)
  of "webviewTagUpdateHtml":
    let (html, hasHtml) = getJsonStringField(paramsObj, "html")
    if hasHtml:
      if childWebviewRenderer(webviewId) == rCef:
        discard core.setWebviewHTMLContent(webviewId, html)
        discard core.loadURLInWebview(webviewId, "views://internal/index.html")
      else:
        discard core.loadHTMLInWebview(webviewId, html)
  of "webviewTagGoBack":
    discard core.webviewGoBack(webviewId)
  of "webviewTagGoForward":
    discard core.webviewGoForward(webviewId)
  of "webviewTagReload":
    discard core.reloadWebview(webviewId)
  of "webviewTagRemove":
    discard core.removeWebview(webviewId)
    forgetChildWebview(webviewId)
  of "webviewTagSetTransparent":
    discard core.setWebviewTransparent(webviewId, getJsonBoolField(paramsObj, "transparent", false))
  of "webviewTagSetPassthrough":
    discard core.setWebviewPassthrough(webviewId, getJsonBoolField(paramsObj, "enablePassthrough", false))
  of "webviewTagSetHidden":
    discard core.setWebviewHidden(webviewId, getJsonBoolField(paramsObj, "hidden", false))
  of "webviewTagSetNavigationRules":
    if "rules" in paramsObj:
      discard core.setWebviewNavigationRules(webviewId, $paramsObj["rules"])
  of "webviewTagFindInPage":
    let (searchText, hasSearchText) = getJsonStringField(paramsObj, "searchText")
    if hasSearchText:
      discard core.webviewFindInPage(
        webviewId,
        searchText,
        getJsonBoolField(paramsObj, "forward", true),
        getJsonBoolField(paramsObj, "matchCase", false),
      )
  of "webviewTagStopFind":
    discard core.webviewStopFind(webviewId)
  of "webviewTagOpenDevTools":
    discard core.openWebviewDevTools(webviewId)
  of "webviewTagCloseDevTools":
    discard core.closeWebviewDevTools(webviewId)
  of "webviewTagToggleDevTools":
    discard core.toggleWebviewDevTools(webviewId)
  of "webviewTagExecuteJavascript":
    let (js, hasJs) = getJsonStringField(paramsObj, "js")
    if hasJs:
      discard core.evaluateJavaScriptWithNoCompletion(webviewId, js)
  of "wgpuTagResize":
    let (frame, masks, ok) = frameAndMasksFromParams(paramsObj)
    if ok:
      discard core.resizeWGPUView(webviewId, frame, masks)
  of "wgpuTagSetTransparent":
    discard core.setWGPUViewTransparent(webviewId, getJsonBoolField(paramsObj, "transparent", false))
  of "wgpuTagSetPassthrough":
    discard core.setWGPUViewPassthrough(webviewId, getJsonBoolField(paramsObj, "passthrough", false))
  of "wgpuTagSetHidden":
    discard core.setWGPUViewHidden(webviewId, getJsonBoolField(paramsObj, "hidden", false))
  of "wgpuTagRemove":
    discard core.removeWGPUView(webviewId)
  of "wgpuTagRunTest":
    discard core.runWGPUViewTest(webviewId)
  else:
    discard

proc playgroundInternalBridge(hostWebviewId: uint32; message: cstring) {.cdecl.} =
  let messageSlice = $message
  if messageSlice.len == 0:
    return
  let parsed =
    try:
      parseJson(messageSlice)
    except JsonParsingError as e:
      stderr.writeLine("[kitchen nim] failed to parse internal bridge packet: ", e.msg)
      return
  if parsed.kind == JObject:
    let (idString, idOk) = getJsonStringField(parsed, "id")
    let (typeString, typeOk) = getJsonStringField(parsed, "type")
    if idOk and typeOk and idString == "webviewEvent" and typeString == "message":
      if "payload" in parsed and parsed["payload"].kind == JObject:
        let payloadObj = parsed["payload"]
        let (eventName, hasEventName) = getJsonStringField(payloadObj, "eventName")
        let (detail, hasDetail) = getJsonStringField(payloadObj, "detail")
        if hasEventName and hasDetail:
          recordObservedWebviewEvent(eventName, detail)
    return
  if parsed.kind != JArray:
    return
  for item in parsed:
    if item.kind != JString:
      continue
    let packet =
      try:
        parseJson(item.getStr())
      except JsonParsingError:
        continue
    if packet.kind != JObject:
      continue
    let (packetType, hasPacketType) = getJsonStringField(packet, "type")
    if not hasPacketType:
      continue
    if packetType == "message":
      let (bridgeMessageId, hasMessageId) = getJsonStringField(packet, "id")
      if not hasMessageId or "payload" notin packet or packet["payload"].kind != JObject:
        continue
      handleInternalBridgeMessage(bridgeMessageId, packet["payload"])
    elif packetType == "request":
      let (requestId, hasRequestId) = getJsonStringField(packet, "id")
      let (bridgeMethod, hasMethod) = getJsonStringField(packet, "method")
      if not hasRequestId or not hasMethod or "params" notin packet or packet["params"].kind != JObject:
        continue
      handleInternalBridgeRequest(hostWebviewId, requestId, bridgeMethod, packet["params"])

proc noopHarnessWebviewCallbacks(): WebviewCallbacks =
  WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: noopWebviewEvent,
    eventBridge: noopWebviewPostMessage,
    hostBridge: noopWebviewPostMessage,
    internalBridge: noopWebviewPostMessage,
  )

proc observedHarnessWebviewCallbacks(): WebviewCallbacks =
  WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: webviewEventHandler(observedWebviewEvent),
    eventBridge: webviewBridgeHandler(observedWebviewBridge),
    hostBridge: noopWebviewPostMessage,
    internalBridge: webviewBridgeHandler(observedWebviewBridge),
  )

proc createWindowWithHarnessCustomRenderer(
  state: ptr AppState,
  title: string,
  frame: Rect,
  renderer: Renderer,
  hidden: bool,
  activate: bool,
  titleBarStyle: string,
  window_callbacks: WindowCallbacks,
  webview_callbacks: WebviewCallbacks,
  ): (WindowWithWebview, string) =
  var window_options = defaultWindowOptions(title)
  window_options.frame = frame
  window_options.hidden = hidden
  window_options.activate = activate
  window_options.titleBarStyle = titleBarStyle
  window_options.callbacks = window_callbacks
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return (default(WindowWithWebview), errName(window_err))
  var webview_options = defaultWebviewOptions(windowId)
  webview_options.renderer = renderer
  webview_options.url = testHarnessUrl
  webview_options.frame = Rect(x: 0, y: 0, width: frame.width, height: frame.height)
  webview_options.secretKey = defaultSecretKey
  webview_options.callbacks = webview_callbacks
  webview_options.sandbox = false
  
  var (webviewId, webview_err) = (state.core.createWebview( webview_options))
  if webview_err != ebNone:
    discard state.core.closeWindow( windowId)
    return (default(WindowWithWebview), errName(webview_err))
  return (WindowWithWebview(windowId: windowId, webviewId: webviewId), "")

proc createWindowWithHarnessCustom(
  state: ptr AppState,
  title: string,
  frame: Rect,
  hidden: bool,
  activate: bool,
  titleBarStyle: string,
  window_callbacks: WindowCallbacks,
  webview_callbacks: WebviewCallbacks,
): (WindowWithWebview, string) =
  createWindowWithHarnessCustomRenderer(
    state,
    title,
    frame,
    rNative,
    hidden,
    activate,
    titleBarStyle,
    window_callbacks,
    webview_callbacks,
  )

proc openInteractivePlaygroundWindow(
  state: ptr AppState,
  title: string,
  url: string,
  renderer: Renderer,
  frame: Rect,
  ): (WindowWithWebview, string) =
  resetCallbackState()
  
  var window_options = defaultWindowOptions(title)
  window_options.frame = frame
  window_options.hidden = false
  window_options.activate = true
  window_options.callbacks = WindowCallbacks(
    close: observedWindowClose,
  )
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return (default(WindowWithWebview), errName(window_err))
  var webview_options = defaultWebviewOptions(windowId)
  webview_options.renderer = renderer
  webview_options.url = url
  webview_options.frame = Rect(x: 0, y: 0, width: frame.width, height: frame.height)
  webview_options.secretKey = defaultSecretKey
  webview_options.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: webviewEventHandler(observedWebviewEvent),
    eventBridge: webviewBridgeHandler(observedWebviewBridge),
    hostBridge: webviewBridgeHandler(testRunnerHostBridge),
    internalBridge: webviewBridgeHandler(playgroundInternalBridge),
  )
  webview_options.sandbox = false
  
  var (webviewId, webview_err) = (state.core.createWebview( webview_options))
  if webview_err != ebNone:
    discard state.core.closeWindow( windowId)
    return (default(WindowWithWebview), errName(webview_err))
  rememberTopLevelWebview(webviewId, windowId)
  
  let err = state.core.setWindowAlwaysOnTop( windowId, true)
  if err != ebNone:
    discard state.core.closeWindow( windowId)
    return (default(WindowWithWebview), errName(err))
  return (WindowWithWebview(windowId: windowId, webviewId: webviewId), "")

proc createWindowWithTestHarness(
  state: ptr AppState,
  title: string,
  frame: Rect,
  hidden: bool,
  activate: bool,
  ): (WindowWithWebview, string) =
  return createWindowWithHarnessCustom(
  state,
  title,
  frame,
  hidden,
  activate,
  "default",
  default(WindowCallbacks),
  noopHarnessWebviewCallbacks(),
  )

proc runSmokeTest(): string =
  return ""

proc runAppPackagedModeReflectsBuildChannelTest(state: ptr AppState): string =
  var channel = state.appInfo.channel
  if channel != "dev" and channel != "canary" and channel != "stable":
    return "UnexpectedBuildChannel"
  
  var expected_packaged = channel != "dev"
  if appInfoIsPackaged(state.appInfo) != expected_packaged:
    return "PackagedModeDoesNotReflectBuildChannel"
  return ""

proc runWindowCreateCloseTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("Electrobun Nim Window Test")
  window_options.frame = Rect(x: 60, y: 60, width: 320, height: 240)
  window_options.hidden = false
  window_options.activate = true
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  sleepMs(visibleTestWindowDelayMs)
  let err = state.core.closeWindow( windowId)
  if err != ebNone:
    return errName(err)
  return ""

proc runWindowCreationWithUrlTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "URL Window Test",
  Rect(x: 120, y: 120, width: 400, height: 300),
  true,
  false,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  if created.windowId == 0 or created.webviewId == 0:
    return "InvalidWindowOrWebviewId"
  return ""

proc runWindowHiddenOptionTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Hidden Window Test",
  Rect(x: 140, y: 140, width: 400, height: 300),
  true,
  false,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  if state.core.isWindowVisible( created.windowId):
    return "WindowUnexpectedlyVisible"
  
  let err = state.core.showWindow( created.windowId, true)
  if err != ebNone:
    return errName(err)
  sleepMs(mediumWaitMs)
  
  if not state.core.isWindowVisible( created.windowId):
    return "WindowDidNotBecomeVisible"
  
  let hideErr = state.core.hideWindow( created.windowId)
  if hideErr != ebNone:
    return errName(hideErr)
  sleepMs(mediumWaitMs)
  
  if state.core.isWindowVisible( created.windowId):
    return "WindowDidNotHide"
  
  return ""

proc runWindowInactiveShowApiTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Inactive Show Test",
  Rect(x: 150, y: 150, width: 400, height: 300),
  true,
  false,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  let err = state.core.showWindow( created.windowId, false)
  if err != ebNone:
    return errName(err)
  sleepMs(mediumWaitMs)
  let err2 = state.core.activateWindow( created.windowId)
  if err2 != ebNone:
    return errName(err2)
  sleepMs(mediumWaitMs)
  return ""

proc runWindowPageZoomTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Page Zoom Test",
  Rect(x: 150, y: 150, width: 420, height: 320),
  true,
  false,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  var target_zoom = 1.25
  let err = state.core.setWebviewPageZoom( created.webviewId, target_zoom)
  if err != ebNone:
    return errName(err)
  sleepMs(mediumWaitMs)
  
  var zoom = state.core.getWebviewPageZoom( created.webviewId)
  if not approxEq(zoom, target_zoom, 0.02):
    return "UnexpectedWindowZoom"
  return ""

proc runWindowSetTitleTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("Original Title")
  window_options.frame = Rect(x: 160, y: 160, width: 400, height: 300)
  window_options.hidden = true
  window_options.activate = false
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  let err = state.core.setWindowTitle( windowId, "New Title From Odin Test")
  if err != ebNone:
    return errName(err)
  sleepMs(shortWaitMs)
  return ""

proc runWindowMinimizeUnminimizeTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Minimize Test",
  Rect(x: 160, y: 160, width: 420, height: 320),
  false,
  true,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(longWaitMs)
  if state.core.isWindowMinimized( created.windowId):
    return "UnexpectedInitialMinimizedState"
  
  let err = state.core.minimizeWindow( created.windowId)
  if err != ebNone:
    return errName(err)
  sleepMs(2000)
  if not state.core.isWindowMinimized( created.windowId):
    return "WindowDidNotMinimize"
  
  let err2 = state.core.restoreWindow( created.windowId)
  if err2 != ebNone:
    return errName(err2)
  sleepMs(3000)
  if state.core.isWindowMinimized( created.windowId):
    return "WindowDidNotRestore"
  return ""

proc runWindowFullscreenToggleTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Fullscreen Test",
  Rect(x: 170, y: 170, width: 420, height: 320),
  false,
  true,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(mediumWaitMs)
  if state.core.isWindowFullScreen( created.windowId):
    return "UnexpectedInitialFullscreenState"
  
  let err = state.core.setWindowFullScreen( created.windowId, true)
  if err != ebNone:
    return errName(err)
  sleepMs(longWaitMs)
  if not state.core.isWindowFullScreen( created.windowId):
    return "WindowDidNotEnterFullscreen"
  
  let err2 = state.core.setWindowFullScreen( created.windowId, false)
  if err2 != ebNone:
    return errName(err2)
  sleepMs(longWaitMs)
  if state.core.isWindowFullScreen( created.windowId):
    return "WindowDidNotExitFullscreen"
  return ""

proc runWindowFullscreenToggleHiddenTitlebarTest(state: ptr AppState): string =
  when not defined(macosx):
    return ""
  else:
    let (created, create_err) = createWindowWithHarnessCustom(
    state,
    "Hidden Fullscreen Test",
    Rect(x: 180, y: 180, width: 420, height: 320),
    false,
    true,
    "hidden",
    default(WindowCallbacks),
    noopHarnessWebviewCallbacks(),
    )
    if create_err != "":
      return create_err
    defer:
      discard state.core.closeWindow( created.windowId)
    
    sleepMs(mediumWaitMs)
    if state.core.isWindowFullScreen( created.windowId):
      return "UnexpectedInitialFullscreenState"
    
    let err = state.core.setWindowFullScreen( created.windowId, true)
    if err != ebNone:
      return errName(err)
    sleepMs(longWaitMs)
    if not state.core.isWindowFullScreen( created.windowId):
      return "WindowDidNotEnterFullscreen"
    
    let err2 = state.core.setWindowFullScreen( created.windowId, false)
    if err2 != ebNone:
      return errName(err2)
    sleepMs(longWaitMs)
    if state.core.isWindowFullScreen( created.windowId):
      return "WindowDidNotExitFullscreen"
    return ""

proc runWindowSetPositionTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("Position Test")
  window_options.frame = Rect(x: 50, y: 60, width: 420, height: 320)
  window_options.hidden = true
  window_options.activate = false
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  let err = state.core.setWindowPosition( windowId, 200, 200)
  if err != ebNone:
    return errName(err)
  sleepMs(shortWaitMs)
  
  var (frame, frame_err) = (state.core.getWindowFrame( windowId))
  if frame_err != ebNone:
    return errName(frame_err)
  if not approxEq(frame.x, 200, 4) or not approxEq(frame.y, 200, 4):
    return "UnexpectedWindowPosition"
  return ""

proc runWindowOmittedPositionCentersOnPrimaryDisplayTest(state: ptr AppState): string =
  var (display, display_err) = (getPrimaryDisplay(state.core))
  if display_err != ebNone:
    return errName(display_err)
  
  var window_options = defaultWindowOptions("Centered Window Test")
  window_options.frame = Rect(x: 0, y: 0, width: 480, height: 320)
  window_options.hidden = true
  window_options.activate = false
  window_options.centered = true
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  var (frame, frame_err) = (state.core.getWindowFrame( windowId))
  if frame_err != ebNone:
    return errName(frame_err)
  
  var expected_x = display.workArea.x + (display.workArea.width - frame.width) / 2
  var expected_y = display.workArea.y + (display.workArea.height - frame.height) / 2
  const centerTolerance = 8.0
  if not approxEq(frame.x, expected_x, centerTolerance) or
  not approxEq(frame.y, expected_y, centerTolerance):
    return "WindowNotCenteredOnPrimaryDisplay"
  return ""

proc runWindowSetSizeTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Size Test",
  Rect(x: 70, y: 80, width: 420, height: 320),
  false,
  false,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(shortWaitMs)
  let err = state.core.setWindowSize( created.windowId, 600, 500)
  if err != ebNone:
    return errName(err)
  sleepMs(shortWaitMs)
  
  var (grown_frame, grown_frame_err) = (state.core.getWindowFrame( created.windowId))
  if grown_frame_err != ebNone:
    return errName(grown_frame_err)
  if not approxEq(grown_frame.width, 600, 24) or not approxEq(grown_frame.height, 500, 24):
    return "UnexpectedWindowSize"
  
  let err2 = state.core.setWindowSize( created.windowId, 320, 240)
  if err2 != ebNone:
    return errName(err2)
  sleepMs(shortWaitMs)
  
  var (shrunk_frame, shrunk_frame_err) = (state.core.getWindowFrame( created.windowId))
  if shrunk_frame_err != ebNone:
    return errName(shrunk_frame_err)
  if not approxEq(shrunk_frame.width, 320, 24) or not approxEq(shrunk_frame.height, 240, 24):
    return "UnexpectedWindowSize"
  return ""

proc runWindowSetFrameTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("Electrobun Nim Frame Test")
  window_options.frame = Rect(x: 80, y: 80, width: 320, height: 240)
  window_options.hidden = true
  window_options.activate = false
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  let err = state.core.setWindowFrame( windowId, Rect(x: 120, y: 140, width: 640, height: 480))
  if err != ebNone:
    return errName(err)
  
  var (frame, frame_err) = (state.core.getWindowFrame( windowId))
  if frame_err != ebNone:
    return errName(frame_err)
  if frame.width != 640 or frame.height != 480:
    return "UnexpectedWindowFrame"
  return ""

proc runWindowGetFrameTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("GetFrame Test")
  window_options.frame = Rect(x: 150, y: 150, width: 500, height: 400)
  window_options.hidden = true
  window_options.activate = false
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  sleepMs(shortWaitMs)
  var (frame, frame_err) = (state.core.getWindowFrame( windowId))
  if frame_err != ebNone:
    return errName(frame_err)
  if frame.x < 0 or frame.y < 0 or frame.width <= 0 or frame.height <= 0:
    return "InvalidWindowFrame"
  if not approxEq(frame.width, 500, 100) or not approxEq(frame.height, 400, 100):
    return "UnexpectedWindowFrame"
  return ""

proc runWindowGetPositionTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("GetPosition Test")
  window_options.frame = Rect(x: 200, y: 180, width: 400, height: 300)
  window_options.hidden = true
  window_options.activate = false
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  sleepMs(shortWaitMs)
  var (frame, frame_err) = (state.core.getWindowFrame( windowId))
  if frame_err != ebNone:
    return errName(frame_err)
  if frame.x < 0 or frame.y < 0:
    return "InvalidWindowPosition"
  return ""

proc runWindowGetSizeTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("GetSize Test")
  window_options.frame = Rect(x: 100, y: 100, width: 600, height: 450)
  window_options.hidden = true
  window_options.activate = false
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  sleepMs(shortWaitMs)
  var (frame, frame_err) = (state.core.getWindowFrame( windowId))
  if frame_err != ebNone:
    return errName(frame_err)
  if frame.width <= 0 or frame.height <= 0:
    return "InvalidWindowSize"
  if not approxEq(frame.width, 600, 100) or not approxEq(frame.height, 450, 100):
    return "UnexpectedWindowSize"
  return ""

proc runWindowMaximizeUnmaximizeTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Maximize Test",
  Rect(x: 180, y: 180, width: 420, height: 320),
  false,
  true,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(mediumWaitMs)
  if state.core.isWindowMaximized( created.windowId):
    return "UnexpectedInitialMaximizedState"
  
  let err = state.core.maximizeWindow( created.windowId)
  if err != ebNone:
    return errName(err)
  sleepMs(longWaitMs)
  if not state.core.isWindowMaximized( created.windowId):
    return "WindowDidNotMaximize"
  
  let err2 = state.core.unmaximizeWindow( created.windowId)
  if err2 != ebNone:
    return errName(err2)
  sleepMs(longWaitMs)
  if state.core.isWindowMaximized( created.windowId):
    return "WindowDidNotUnmaximize"
  return ""

proc runWindowAlwaysOnTopTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Always On Top Test",
  Rect(x: 200, y: 200, width: 420, height: 320),
  false,
  true,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(shortWaitMs)
  if state.core.isWindowAlwaysOnTop( created.windowId):
    return "UnexpectedInitialAlwaysOnTopState"
  
  let err = state.core.setWindowAlwaysOnTop( created.windowId, true)
  if err != ebNone:
    return errName(err)
  sleepMs(longWaitMs)
  if not state.core.isWindowAlwaysOnTop( created.windowId):
    when defined(linux):
      return ""
    else:
      return "WindowDidNotBecomeAlwaysOnTop"
  
  let err2 = state.core.setWindowAlwaysOnTop( created.windowId, false)
  if err2 != ebNone:
    return errName(err2)
  sleepMs(mediumWaitMs)
  if state.core.isWindowAlwaysOnTop( created.windowId):
    return "WindowDidNotClearAlwaysOnTop"
  return ""

proc runWindowVisibleOnAllWorkspacesTest(state: ptr AppState): string =
  when not defined(macosx):
    return ""
  else:
    let (created, create_err) = createWindowWithTestHarness(
    state,
    "Visible On All Workspaces Test",
    Rect(x: 220, y: 220, width: 420, height: 320),
    false,
    true,
    )
    if create_err != "":
      return create_err
    defer:
      discard state.core.closeWindow( created.windowId)
    
    sleepMs(shortWaitMs)
    if state.core.isWindowVisibleOnAllWorkspaces( created.windowId):
      return "UnexpectedInitialVisibleOnAllWorkspacesState"
    
    let err = state.core.setWindowVisibleOnAllWorkspaces( created.windowId, true)
    if err != ebNone:
      return errName(err)
    sleepMs(longWaitMs)
    if not state.core.isWindowVisibleOnAllWorkspaces( created.windowId):
      return "WindowDidNotBecomeVisibleOnAllWorkspaces"
    
    let err2 = state.core.setWindowVisibleOnAllWorkspaces( created.windowId, false)
    if err2 != ebNone:
      return errName(err2)
    sleepMs(mediumWaitMs)
    if state.core.isWindowVisibleOnAllWorkspaces( created.windowId):
      return "WindowDidNotClearVisibleOnAllWorkspaces"
    return ""

proc runWindowFocusTest(state: ptr AppState): string =
  resetCallbackState()
  
  var win1_options = defaultWindowOptions("Focus Test 1")
  win1_options.frame = Rect(x: 100, y: 100, width: 360, height: 260)
  win1_options.callbacks = WindowCallbacks(
    focus: observedWindowFocus,
  )
  var (win1, win1_err) = (state.core.createWindow( win1_options))
  if win1_err != ebNone:
    return errName(win1_err)
  defer:
    discard state.core.closeWindow( win1)
  
  var win2_options = defaultWindowOptions("Focus Test 2")
  win2_options.frame = Rect(x: 220, y: 220, width: 360, height: 260)
  win2_options.callbacks = WindowCallbacks(
    focus: observedWindowFocus,
  )
  var (win2, win2_err) = (state.core.createWindow( win2_options))
  if win2_err != ebNone:
    return errName(win2_err)
  defer:
    discard state.core.closeWindow( win2)
  
  sleepMs(mediumWaitMs)
  resetCallbackState()
  let err = state.core.activateWindow( win1)
  if err != ebNone:
    return errName(err)
  sleepMs(mediumWaitMs)
  let err2 = state.core.activateWindow( win2)
  if err2 != ebNone:
    return errName(err2)
  sleepMs(mediumWaitMs)
  
  if getWindowFocusCount() == 0:
    return "WindowFocusEventDidNotFire"
  return ""

proc runWindowCloseEventTest(state: ptr AppState): string =
  resetCallbackState()
  
  var window_options = defaultWindowOptions("Close Event Test")
  window_options.frame = Rect(x: 120, y: 120, width: 360, height: 260)
  window_options.callbacks = WindowCallbacks(
    close: observedWindowClose,
  )
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  
  sleepMs(shortWaitMs)
  let err = state.core.closeWindow( windowId)
  if err != ebNone:
    return errName(err)
  sleepMs(shortWaitMs)
  
  if getWindowCloseCount() == 0:
    return "WindowCloseEventDidNotFire"
  return ""

proc runWindowWillCloseVetoTest(state: ptr AppState): string =
  resetCallbackState()
  
  var window_options = defaultWindowOptions("Will Close Veto Test")
  window_options.frame = Rect(x: 120, y: 120, width: 360, height: 260)
  window_options.callbacks = WindowCallbacks(
    close: observedWindowClose,
    shouldClose: cast[WindowShouldCloseHandler](observedWindowShouldClose),
  )
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  
  let err = state.core.requestWindowClose( windowId)
  if err != ebNone:
    discard state.core.closeWindow( windowId)
    return errName(err)
  sleepMs(shortWaitMs)
  if getWindowShouldCloseCount() != 1 or getWindowCloseCount() != 0:
    discard state.core.closeWindow( windowId)
    return "FirstCloseRequestWasNotVetoed"
  var (_, frame_err) = (state.core.getWindowFrame( windowId))
  if frame_err != ebNone:
    discard state.core.closeWindow( windowId)
    return errName(frame_err)
  
  let err2 = state.core.requestWindowClose( windowId)
  if err2 != ebNone:
    discard state.core.closeWindow( windowId)
    return errName(err2)
  sleepMs(shortWaitMs)
  if getWindowShouldCloseCount() != 2 or getWindowCloseCount() == 0:
    discard state.core.closeWindow( windowId)
    return "SecondCloseRequestWasNotAllowed"
  return ""

proc runWindowResizeEventTest(state: ptr AppState): string =
  resetCallbackState()
  
  var window_options = defaultWindowOptions("Resize Event Test")
  window_options.frame = Rect(x: 120, y: 120, width: 400, height: 300)
  window_options.callbacks = WindowCallbacks(
    resize: observedWindowResize,
  )
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  sleepMs(shortWaitMs)
  resetCallbackState()
  let err = state.core.setWindowSize( windowId, 700, 520)
  if err != ebNone:
    return errName(err)
  sleepMs(mediumWaitMs)
  
  var resize_count = getWindowResizeCount()
  var last_size = getLastResizeSize()
  if resize_count == 0:
    return "WindowResizeEventDidNotFire"
  if last_size.width <= 400 or last_size.height <= 300:
    return "WindowResizeEventDidNotReportUpdatedSize"
  return ""

proc runWindowGetByIdTest(state: ptr AppState): string =
  var registry = windowRegistryInit(addr state.core)
  defer:
    registry.deinit()
  var windowOptions = defaultWindowOptions("GetById Test")
  windowOptions.frame = Rect(x: 260, y: 260, width: 420, height: 320)
  windowOptions.hidden = true
  windowOptions.activate = false
  let (window, windowErr) = createBrowserWindow(registry, windowOptions)
  if windowErr != ebNone:
    return errName(windowErr)
  defer:
    discard window.close()
  let (retrieved, found) = getById(registry, window.id)
  if not found:
    return "WindowRegistryLookupFailed"
  if retrieved.id != window.id:
    return "WindowRegistryReturnedUnexpectedId"
  ""

proc runWindowInsetTitlebarStyleTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("Inset Titlebar")
  window_options.frame = Rect(x: 270, y: 270, width: 420, height: 320)
  window_options.titleBarStyle = "hiddenInset"
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  if windowId == 0:
    return "InvalidInsetTitlebarWindowId"
  sleepMs(300)
  return ""

proc runWindowTrafficLightPositionApiTest(state: ptr AppState): string =
  when not defined(macosx):
    return ""
  else:
    var registry = windowRegistryInit(addr state.core)
    defer:
      registry.deinit()
    var baselineOptions = defaultWindowOptions("Traffic Light Baseline")
    baselineOptions.frame = Rect(x: 220, y: 220, width: 480, height: 340)
    baselineOptions.titleBarStyle = "hiddenInset"
    baselineOptions.activate = false
    let (baseline, baselineErr) = createBrowserWindow(registry, baselineOptions)
    if baselineErr != ebNone:
      return errName(baselineErr)
    defer:
      discard baseline.close()
    var windowOptions = defaultWindowOptions("Traffic Light Position Test")
    windowOptions.frame = Rect(x: 280, y: 280, width: 480, height: 340)
    windowOptions.titleBarStyle = "hiddenInset"
    windowOptions.trafficLightOffset = TrafficLightOffset(x: 24, y: 18)
    windowOptions.activate = false
    let (window, windowErr) = createBrowserWindow(registry, windowOptions)
    if windowErr != ebNone:
      return errName(windowErr)
    defer:
      discard window.close()
    sleepMs(300)
    let (baselinePosition, baselinePositionErr) = windowGetWindowButtonPosition(baseline)
    if baselinePositionErr != ebNone:
      return errName(baselinePositionErr)
    let (offsetPosition, offsetPositionErr) = windowGetWindowButtonPosition(window)
    if offsetPositionErr != ebNone:
      return errName(offsetPositionErr)
    if not approxEq(offsetPosition.x - baselinePosition.x, 24, 0.5) or
        not approxEq(offsetPosition.y - baselinePosition.y, 18, 0.5):
      return "UnexpectedTrafficLightOffset"
    let setErr = windowSetWindowButtonPosition(window, 52, 22)
    if setErr != ebNone:
      return errName(setErr)
    sleepMs(300)
    let (positioned, positionErr) = windowGetWindowButtonPosition(window)
    if positionErr != ebNone:
      return errName(positionErr)
    if not approxEq(positioned.x, 52, 0.5) or not approxEq(positioned.y, 22, 0.5):
      return "UnexpectedTrafficLightPosition"
    let resizeErr = state.core.setWindowSize(window.id, 540, 380)
    if resizeErr != ebNone:
      return errName(resizeErr)
    sleepMs(300)
    let (resized, resizedErr) = windowGetWindowButtonPosition(window)
    if resizedErr != ebNone:
      return errName(resizedErr)
    if not approxEq(resized.x, 52, 0.5) or not approxEq(resized.y, 22, 0.5):
      return "TrafficLightPositionChangedAfterResize"
    ""

proc runWebviewCreateTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("Electrobun Nim Webview Test")
  window_options.frame = Rect(x: 100, y: 100, width: 500, height: 360)
  window_options.hidden = true
  window_options.activate = false
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  var webview_options = defaultWebviewOptions(windowId)
  webview_options.renderer = rNative
  webview_options.url = "views://zig/index.html"
  webview_options.frame = Rect(x: 0, y: 0, width: 500, height: 360)
  webview_options.secretKey = defaultSecretKey
  webview_options.callbacks = noopHarnessWebviewCallbacks()
  webview_options.sandbox = true
  
  var (_, webview_err) = (state.core.createWebview( webview_options))
  if webview_err != ebNone:
    return errName(webview_err)
  return ""

proc runWebviewPageZoomTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "View Zoom Test",
  Rect(x: 240, y: 240, width: 420, height: 320),
  true,
  false,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  var target_zoom = 1.1
  let err = state.core.setWebviewPageZoom( created.webviewId, target_zoom)
  if err != ebNone:
    return errName(err)
  sleepMs(mediumWaitMs)
  
  var zoom = state.core.getWebviewPageZoom( created.webviewId)
  if not approxEq(zoom, target_zoom, 0.02):
    return "UnexpectedWebviewZoom"
  return ""

proc runWebviewSpellCheckTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Spell Check Test",
  Rect(x: 240, y: 240, width: 420, height: 320),
  true,
  false,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  var expectedSupport = defined(macosx)
  var (disabled, disable_err) = (state.core.setWebviewSpellCheck( created.webviewId, false))
  if disable_err != ebNone:
    return errName(disable_err)
  var (enabled, enable_err) = (state.core.setWebviewSpellCheck( created.webviewId, true))
  if enable_err != ebNone:
    return errName(enable_err)
  if disabled != expectedSupport or enabled != expectedSupport:
    return "UnexpectedSpellCheckSupport"
  return ""

proc runWebviewTagPlaygroundIntegrationTest(state: ptr AppState): string =
  clearChildWebviews()
  resetCallbackState()
  
  var window_options = defaultWindowOptions("Webview Tag Playground Integration")
  window_options.frame = Rect(x: 220, y: 120, width: 900, height: 1000)
  window_options.hidden = false
  window_options.activate = true
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
    clearChildWebviews()
  
  var webview_options = defaultWebviewOptions(windowId)
  webview_options.renderer = rCef
  webview_options.url = "views://playgrounds/webviewtag/index.html"
  webview_options.frame = Rect(x: 0, y: 0, width: 900, height: 1000)
  webview_options.secretKey = defaultSecretKey
  webview_options.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: webviewEventHandler(observedWebviewEvent),
    eventBridge: webviewBridgeHandler(observedWebviewBridge),
    hostBridge: webviewBridgeHandler(testRunnerHostBridge),
    internalBridge: webviewBridgeHandler(playgroundInternalBridge),
  )
  webview_options.sandbox = false
  
  var (_, webview_err) = (state.core.createWebview( webview_options))
  if webview_err != ebNone:
    return errName(webview_err)
  
  let deadlineStart = getMonoTime()
  while (getMonoTime() - deadlineStart).inMilliseconds < 8000:
    if getWebviewDomReadyCount() > 0 and getWebviewTagInitCount() >= 2:
      sleepMs(mediumWaitMs)
      return ""
    sleepMs(50)
  
  return "WebviewTagIntegrationTimedOut"

proc runWgpuTagPlaygroundIntegrationTest(state: ptr AppState): string =
  resetCallbackState()
  
  var window_options = defaultWindowOptions("WGPU Tag Playground Integration")
  window_options.frame = Rect(x: 240, y: 140, width: 860, height: 720)
  window_options.hidden = false
  window_options.activate = true
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  var webview_options = defaultWebviewOptions(windowId)
  webview_options.renderer = rNative
  webview_options.url = "views://playgrounds/wgpu-tag/index.html"
  webview_options.frame = Rect(x: 0, y: 0, width: 860, height: 720)
  webview_options.secretKey = defaultSecretKey
  webview_options.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: webviewEventHandler(observedWebviewEvent),
    eventBridge: webviewBridgeHandler(observedWebviewBridge),
    hostBridge: webviewBridgeHandler(testRunnerHostBridge),
    internalBridge: webviewBridgeHandler(playgroundInternalBridge),
  )
  webview_options.sandbox = false
  
  var (_, webview_err) = (state.core.createWebview( webview_options))
  if webview_err != ebNone:
    return errName(webview_err)
  
  let deadlineStart = getMonoTime()
  while (getMonoTime() - deadlineStart).inMilliseconds < 8000:
    if getWebviewDomReadyCount() > 0 and getWgpuTagInitCount() > 0 and getWgpuTagReadyCount() > 0:
      sleepMs(mediumWaitMs)
      return ""
    sleepMs(50)
  
  return "WgpuTagIntegrationTimedOut"

proc waitForInteractiveWindowClose() =
  while getWindowCloseCount() == 0:
    sleepMs(100)

proc runWebviewTagPlaygroundInteractiveTest(state: ptr AppState): string =
  clearChildWebviews()
  resetCallbackState()
  
  var window_options = defaultWindowOptions("Webview Tag Playground")
  window_options.frame = Rect(x: 100, y: 50, width: 800, height: 900)
  window_options.hidden = false
  window_options.activate = true
  window_options.callbacks = WindowCallbacks(
    close: observedWindowClose,
  )
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  
  var webview_options = defaultWebviewOptions(windowId)
  webview_options.renderer = rCef
  webview_options.url = "views://playgrounds/webviewtag/index.html"
  webview_options.frame = Rect(x: 0, y: 0, width: 800, height: 900)
  webview_options.secretKey = defaultSecretKey
  webview_options.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: webviewEventHandler(observedWebviewEvent),
    eventBridge: webviewBridgeHandler(observedWebviewBridge),
    hostBridge: webviewBridgeHandler(testRunnerHostBridge),
    internalBridge: webviewBridgeHandler(playgroundInternalBridge),
  )
  webview_options.sandbox = false
  
  var (webviewId, webview_err) = (state.core.createWebview( webview_options))
  if webview_err != ebNone:
    discard state.core.closeWindow( windowId)
    return errName(webview_err)
  rememberTopLevelWebview(webviewId, windowId)
  defer:
    forgetTopLevelWebview(webviewId)
    clearChildWebviews()
  
  let err = state.core.setWindowAlwaysOnTop( windowId, true)
  if err != ebNone:
    discard state.core.closeWindow( windowId)
    return errName(err)
  waitForInteractiveWindowClose()
  return ""

proc runWgpuTagPlaygroundInteractiveTest(state: ptr AppState): string =
  resetCallbackState()
  
  var window_options = defaultWindowOptions("WGPU Tag Playground")
  window_options.frame = Rect(x: 120, y: 60, width: 860, height: 720)
  window_options.hidden = false
  window_options.activate = true
  window_options.callbacks = WindowCallbacks(
    close: observedWindowClose,
  )
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  
  var webview_options = defaultWebviewOptions(windowId)
  webview_options.renderer = rNative
  webview_options.url = "views://playgrounds/wgpu-tag/index.html"
  webview_options.frame = Rect(x: 0, y: 0, width: 860, height: 720)
  webview_options.secretKey = defaultSecretKey
  webview_options.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: webviewEventHandler(observedWebviewEvent),
    eventBridge: webviewBridgeHandler(observedWebviewBridge),
    hostBridge: webviewBridgeHandler(testRunnerHostBridge),
    internalBridge: webviewBridgeHandler(playgroundInternalBridge),
  )
  webview_options.sandbox = false
  
  var (webviewId, webview_err) = (state.core.createWebview( webview_options))
  if webview_err != ebNone:
    discard state.core.closeWindow( windowId)
    return errName(webview_err)
  rememberTopLevelWebview(webviewId, windowId)
  defer:
    forgetTopLevelWebview(webviewId)
  
  let err = state.core.setWindowAlwaysOnTop( windowId, true)
  if err != ebNone:
    discard state.core.closeWindow( windowId)
    return errName(err)
  waitForInteractiveWindowClose()
  return ""

proc runNavigationLoadUrlTest(state: ptr AppState): string =
  resetCallbackState()
  let (created, create_err) = createWindowWithHarnessCustom(
  state,
  "LoadURL Test",
  Rect(x: 260, y: 260, width: 500, height: 360),
  false,
  true,
  "default",
  WindowCallbacks(),
  observedHarnessWebviewCallbacks(),
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(mediumWaitMs)
  resetCallbackState()
  let err = state.core.loadURLInWebview( created.webviewId, "views://test-runner/index.html")
  if err != ebNone:
    return errName(err)
  sleepMs(1500)
  
  if getWebviewWillNavigateCount() == 0:
    return "LoadUrlDidNotTriggerWillNavigate"
  return ""

proc runNavigationLoadHtmlTest(state: ptr AppState): string =
  resetCallbackState()
  let (created, create_err) = createWindowWithHarnessCustom(
  state,
  "LoadHTML Test",
  Rect(x: 270, y: 270, width: 500, height: 360),
  false,
  true,
  "default",
  WindowCallbacks(),
  observedHarnessWebviewCallbacks(),
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(mediumWaitMs)
  resetCallbackState()
  let err = loadHTMLInWebview(
  state.core,
  created.webviewId,
  "<html><body><h1 id='test-heading'>Custom HTML Content</h1></body></html>",
  )
  if err != ebNone:
    return errName(err)
  sleepMs(1500)
  
  if getWebviewWillNavigateCount() == 0:
    return "LoadHtmlDidNotTriggerWillNavigate"
  return ""

proc runNavigationDomReadyEventTest(state: ptr AppState): string =
  resetCallbackState()
  let (created, create_err) = createWindowWithHarnessCustom(
  state,
  "DOM Ready Test",
  Rect(x: 280, y: 280, width: 500, height: 360),
  false,
  true,
  "default",
  WindowCallbacks(),
  observedHarnessWebviewCallbacks(),
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(800)
  resetCallbackState()
  let err = state.core.loadURLInWebview( created.webviewId, "views://test-runner/index.html")
  if err != ebNone:
    return errName(err)
  sleepMs(1500)
  
  if getWebviewDomReadyCount() == 0:
    return "DomReadyDidNotFire"
  return ""

proc runNavigationDidNavigateEventTest(state: ptr AppState): string =
  resetCallbackState()
  let (created, create_err) = createWindowWithHarnessCustom(
  state,
  "Did Navigate Test",
  Rect(x: 290, y: 290, width: 500, height: 360),
  false,
  true,
  "default",
  WindowCallbacks(),
  observedHarnessWebviewCallbacks(),
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(mediumWaitMs)
  resetCallbackState()
  let err = state.core.loadURLInWebview( created.webviewId, "views://test-runner/index.html")
  if err != ebNone:
    return errName(err)
  sleepMs(2000)
  
  if getWebviewDidNavigateCount() == 0:
    return "DidNavigateDidNotFire"
  if not lastWebviewDetailContains("test-runner"):
    return "DidNavigateMissingExpectedUrl"
  return ""

proc runNavigationDidCommitNavigationEventTest(state: ptr AppState): string =
  resetCallbackState()
  let (created, create_err) = createWindowWithHarnessCustomRenderer(
  state,
  "Did Commit Navigation Test",
  Rect(x: 295, y: 295, width: 500, height: 360),
  activePlaygroundRenderer(state),
  false,
  true,
  "default",
  WindowCallbacks(),
  observedHarnessWebviewCallbacks(),
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  # Wait past the harness's own OnLoadStart before switching to
  # test-runner. On Windows CEF the initial load's OnLoadStart takes
  # ~3s (vs ~0.5s on Linux/mac); calling loadURL before it fires ends
  # up aborting the pending navigation without CEF ever committing the
  # follow-up view.
  sleepMs(longWaitMs)
  resetCallbackState()
  let err = state.core.loadURLInWebview( created.webviewId, "views://test-runner/index.html")
  if err != ebNone:
    return errName(err)
  sleepMs(2000)
  
  if getWebviewDidCommitNavigationCount() == 0:
    return "DidCommitNavigationDidNotFire"
  if not lastWebviewDetailContains("test-runner"):
    return "DidCommitNavigationMissingExpectedUrl"
  return ""

proc runNavigationExecuteJavascriptTest(state: ptr AppState): string =
  let (created, create_err) = createWindowWithTestHarness(
  state,
  "Execute JS Test",
  Rect(x: 300, y: 300, width: 500, height: 360),
  false,
  true,
  )
  if create_err != "":
    return create_err
  defer:
    discard state.core.closeWindow( created.windowId)
  
  sleepMs(mediumWaitMs)
  let err = state.core.evaluateJavaScriptWithNoCompletion(created.webviewId, "document.body.innerHTML = '<h1>Modified by executeJavascript</h1>';")
  if err != ebNone:
    return errName(err)
  sleepMs(shortWaitMs)
  return ""

proc runAppDataProtocolTest(state: ptr AppState; enabled: bool): string =
  const fixtureName = "kitchen-appdata-protocol-nim.txt"
  const fixtureContents = "electrobun-appdata-protocol-ok"
  let (paths, pathsErr) = resolvePaths(state.appInfo)
  if pathsErr != ebNone:
    return errName(pathsErr)
  try:
    createDir(paths.userData)
  except OSError:
    discard
  let fixturePath = paths.userData / fixtureName
  try:
    writeFile(fixturePath, fixtureContents)
  except IOError:
    return "CreateAppDataProtocolFixtureFailed"
  defer:
    try:
      removeFile(fixturePath)
    except IOError:
      discard
  var windowOptions = defaultWindowOptions("AppData Protocol Test")
  windowOptions.frame = Rect(x: 320, y: 320, width: 500, height: 360)
  windowOptions.hidden = true
  windowOptions.activate = false
  let (windowId, windowErr) = state.core.createWindow(windowOptions)
  if windowErr != ebNone:
    return errName(windowErr)
  defer:
    discard state.core.closeWindow(windowId)
  resetCallbackState()
  var webviewOptions = defaultWebviewOptions(windowId)
  webviewOptions.renderer = rCef
  webviewOptions.url = testHarnessUrl
  webviewOptions.frame = Rect(x: 0, y: 0, width: 500, height: 360)
  webviewOptions.secretKey = defaultSecretKey
  webviewOptions.allowedProtocols = AllowedProtocols(views: true, appData: enabled)
  webviewOptions.callbacks = observedHarnessWebviewCallbacks()
  webviewOptions.sandbox = false
  let (webviewId, webviewErr) = state.core.createWebview(webviewOptions)
  if webviewErr != ebNone:
    return errName(webviewErr)
  sleepMs(longWaitMs)
  let expected = if enabled: "true" else: "false"
  let script = fmt"""fetch("appdata://{fixtureName}").then(async response => response.ok && (await response.text()) === "{fixtureContents}").catch(() => false).then(readable => location.href = "views://test-harness/index.html?appdataResult=" + (readable === {expected} ? "ok" : "fail"));"""
  let err = state.core.evaluateJavaScriptWithNoCompletion(webviewId, script)
  if err != ebNone:
    return errName(err)
  let deadline = milliTimestamp() + int64(5000 * slowPlatformScale())
  while not lastWebviewDetailContains("appdataResult=ok") and milliTimestamp() < deadline:
    sleepMs(25)
  if not lastWebviewDetailContains("appdataResult=ok"):
    return "AppDataProtocolUnexpectedResult"
  ""

proc runTrayVisibilityToggleAndBoundsTest(state: ptr AppState): string =
  var tray_options = defaultTrayOptions(trayTemplateIconUrl)
  tray_options.title = "Kitchen Tray API Test"
  tray_options.isTemplate = true
  tray_options.width = 32
  tray_options.height = 32
  
  var (tray_id, tray_err) = (state.core.createTray( tray_options))
  if tray_err != ebNone:
    return errName(tray_err)
  defer:
    discard state.core.removeTray(tray_id)
  
  block hideTray:
    let err = state.core.hideTray(tray_id)
    if err != ebNone:
      return errName(err)
  sleepMs(shortWaitMs)
  block showTray:
    let err2 = state.core.showTray(tray_id)
    if err2 != ebNone:
      return errName(err2)
  sleepMs(shortWaitMs)
  
  var (bounds, bounds_err) = (state.core.getTrayBounds( tray_id))
  if bounds_err != ebNone:
    return errName(bounds_err)
  if bounds.width < 0 or bounds.height < 0:
    return "InvalidTrayBounds"
  return ""

proc runSessionFromPartitionTest(state: ptr AppState): string =
  let session = sessionFromPartition(addr state.core, "persist:test-partition")
  if session.partition != "persist:test-partition":
    return "SessionPartitionMismatch"
  return ""

proc runSessionDefaultSessionTest(state: ptr AppState): string =
  let session = defaultSession(addr state.core)
  if session.partition != "persist:default":
    return "DefaultSessionPartitionMismatch"
  return ""

proc runSessionCookiesApiExistsTest(state: ptr AppState): string =
  let session = sessionFromPartition(addr state.core, "persist:cookie-api-test")
  let (_, cookiesErr) = getCookies(session)
  if cookiesErr != ebNone:
    return errName(cookiesErr)
  ""

proc runApplicationMenuPlaygroundTest(state: ptr AppState): string =
  when defined(linux):
    return ""
  else:
    let (created, create_err) = openInteractivePlaygroundWindow(
    state,
    "Application Menu Playground",
    "views://playgrounds/application-menu/index.html",
    activePlaygroundRenderer(state),
    Rect(x: 100, y: 50, width: 800, height: 600),
    )
    if create_err != "":
      return create_err
    defer:
      forgetTopLevelWebview(created.webviewId)
    
    setApplicationMenuTargetWebview(created.webviewId)
    waitForInteractiveWindowClose()
    return ""

proc runContextMenuPlaygroundTest(state: ptr AppState): string =
  when defined(linux):
    return ""
  else:
    let (created, create_err) = openInteractivePlaygroundWindow(
    state,
    "Context Menu Playground",
    "views://playgrounds/context-menu/index.html",
    activePlaygroundRenderer(state),
    Rect(x: 150, y: 80, width: 800, height: 600),
    )
    if create_err != "":
      return create_err
    defer:
      forgetTopLevelWebview(created.webviewId)
    
    setContextMenuTargetWebview(created.webviewId)
    waitForInteractiveWindowClose()
    return ""

proc runShowMessageBoxInfoDialogTest(state: ptr AppState): string =
  let buttons = @["OK", "Cancel"]
  var options = defaultMessageBoxOptions()
  options.boxType = "info"
  options.title = "Test Info Dialog"
  options.message = "This is a Nim-mode test info dialog"
  options.detail = "Click any button to pass the test."
  options.buttons = buttons
  options.defaultId = 0
  options.cancelId = 1
  
  var (response, response_err) = (state.core.showMessageBox( options))
  if response_err != ebNone:
    return errName(response_err)
  if response < 0:
    return "MessageBoxFailed"
  return ""

proc runFileDialogPlaygroundTest(state: ptr AppState): string =
  let (created, create_err) = openInteractivePlaygroundWindow(
  state,
  "File Dialog Playground",
  "views://playgrounds/file-dialog/index.html",
  activePlaygroundRenderer(state),
  Rect(x: 200, y: 50, width: 600, height: 850),
  )
  if create_err != "":
    return create_err
  defer:
    forgetTopLevelWebview(created.webviewId)
  
  waitForInteractiveWindowClose()
  return ""

proc runGlobalShortcutsPlaygroundTest(state: ptr AppState): string =
  let err = unregisterAllGlobalShortcuts(state.core)
  if err != ebNone:
    return errName(err)
  
  let (created, create_err) = openInteractivePlaygroundWindow(
  state,
  "Global Shortcuts Playground",
  "views://playgrounds/shortcuts/index.html",
  activePlaygroundRenderer(state),
  Rect(x: 200, y: 50, width: 550, height: 750),
  )
  if create_err != "":
    return create_err
  defer:
    forgetTopLevelWebview(created.webviewId)
    discard unregisterAllGlobalShortcuts(state.core)
  
  setShortcutTargetWebview(created.webviewId)
  waitForInteractiveWindowClose()
  return ""

proc runGlobalShortcutIsRegisteredApiTest(state: ptr AppState): string =
  let err = unregisterAllGlobalShortcuts(state.core)
  if err != ebNone:
    return errName(err)
  defer:
    discard unregisterAllGlobalShortcuts(state.core)
  let candidates = @[
    "Alt+Shift+Super+F11",
    "Alt+Shift+Super+F12",
    "Alt+Shift+Super+Insert",
    "CommandOrControl+Shift+Super+F11",
    "CommandOrControl+Alt+Super+F11",
    "Alt+Shift+Super+Delete",
  ]
  var registeredAccelerator = ""
  var hasRegistered = false
  for candidate in candidates:
    if state.core.registerGlobalShortcut(candidate):
      registeredAccelerator = candidate
      hasRegistered = true
      break
  if not hasRegistered:
    return ""
  if not state.core.isGlobalShortcutRegistered(registeredAccelerator):
    return "GlobalShortcutDidNotRegister"
  if not state.core.unregisterGlobalShortcut(registeredAccelerator):
    return "GlobalShortcutDidNotUnregister"
  if state.core.isGlobalShortcutRegistered(registeredAccelerator):
    return "GlobalShortcutStillRegistered"
  ""

proc runGlobalShortcutUnregisterAllApiTest(state: ptr AppState): string =
  let err = unregisterAllGlobalShortcuts(state.core)
  if err != ebNone:
    return errName(err)
  defer:
    discard unregisterAllGlobalShortcuts(state.core)
  let candidates = @[
    "Alt+Shift+Super+F9",
    "Alt+Shift+Super+F10",
    "Alt+Shift+Super+PageUp",
    "CommandOrControl+Shift+Super+F9",
    "CommandOrControl+Alt+Super+F9",
    "CommandOrControl+Alt+Super+F10",
  ]
  var registered: seq[string] = @[]
  for candidate in candidates:
    if state.core.registerGlobalShortcut(candidate):
      registered.add(candidate)
      if registered.len >= 3:
        break
  if registered.len == 0:
    return ""
  let clearErr = unregisterAllGlobalShortcuts(state.core)
  if clearErr != ebNone:
    return errName(clearErr)
  for candidate in registered:
    if state.core.isGlobalShortcutRegistered(candidate):
      return "GlobalShortcutUnregisterAllFailed"
  ""

proc runLifecycleBeforeQuitCancelTest(state: ptr AppState): string =
  discard state
  resetCallbackState()
  setBeforeQuitShouldCancel(true)
  quitRequestedHandler()
  
  if getBeforeQuitCount() == 0:
    return "BeforeQuitDidNotFire"
  return ""

proc runQuitShutdownPlaygroundTest(state: ptr AppState): string =
  let (created, create_err) = openInteractivePlaygroundWindow(
  state,
  "Quit/Shutdown Test Playground",
  "views://playgrounds/quit-test/index.html",
  activePlaygroundRenderer(state),
  Rect(x: 200, y: 50, width: 600, height: 700),
  )
  if create_err != "":
    return create_err
  defer:
    forgetTopLevelWebview(created.webviewId)
  
  setQuitTargetWebview(created.webviewId)
  setBeforeQuitShouldCancel(true)
  waitForInteractiveWindowClose()
  return ""

proc runWgpuAdapterContextDeviceTest(state: ptr AppState): string =
  var window_options = defaultWindowOptions("WGPU Adapter Context Test")
  window_options.frame = Rect(x: 120, y: 120, width: 320, height: 240)
  window_options.hidden = false
  window_options.activate = true
  
  var (windowId, window_err) = (state.core.createWindow( window_options))
  if window_err != ebNone:
    return errName(window_err)
  defer:
    discard state.core.closeWindow( windowId)
  
  var wgpu_view_options = defaultWGPUViewOptions(windowId)
  wgpu_view_options.frame = Rect(x: 0, y: 0, width: 320, height: 240)
  wgpu_view_options.autoResize = true
  
  var (wgpu_view_id, wgpu_view_err) = (state.core.createWGPUView( wgpu_view_options))
  if wgpu_view_err != ebNone:
    return errName(wgpu_view_err)
  defer:
    discard state.core.removeWGPUView(wgpu_view_id)
  
  sleepMs(shortWaitMs)
  
  var native: WgpuNative
  var nativeErr: EbError
  (native, nativeErr) = wgpuNativeLoad()
  if nativeErr != ebNone:
    return errName(nativeErr)
  defer:
    native.close()
  let (wgpuContext, contextErr) = createForWgpuView(state.core, native, wgpu_view_id)
  if contextErr != ebNone:
    return errName(contextErr)
  if wgpuContext.instancePtr == nil or wgpuContext.surfacePtr == nil or wgpuContext.devicePtr == nil:
    return "WgpuContextMissingPointers"
  if getQueue(wgpuContext, native) == nil:
    return "WgpuQueueMissing"
  ""

proc runDockIconVisibilityContractTest(state: ptr AppState): string =
  var initial_visible = isDockIconVisible(state.core)
  defer:
    discard state.core.setDockIconVisible(initial_visible)
  
  when defined(macosx):
    let err = state.core.setDockIconVisible( false)
    if err != ebNone:
      return errName(err)
    sleepMs(200)
    if isDockIconVisible(state.core):
      return "DockIconDidNotHide"
    
    let err2 = state.core.setDockIconVisible( true)
    if err2 != ebNone:
      return errName(err2)
    sleepMs(200)
    if not isDockIconVisible(state.core):
      return "DockIconDidNotShow"
  else:
    let err3 = state.core.setDockIconVisible( false)
    if err3 != ebNone:
      return errName(err3)
    sleepMs(50)
    discard isDockIconVisible(state.core)
  return ""

proc runUtilsClipboardRoundTripTest(state: ptr AppState): string =
  let testText = fmt"Test clipboard {milliTimestamp()}"
  let err = state.core.clipboardWriteText(testText)
  if err != ebNone:
    return errName(err)
  let (readText, hasText) = clipboardReadText(state.core)
  if not hasText:
    return "MissingClipboardText"
  if readText != testText:
    return "ClipboardRoundTripMismatch"
  ""

proc runUtilsClipboardAvailableFormatsTest(state: ptr AppState): string =
  let err = state.core.clipboardWriteText("test")
  if err != ebNone:
    return errName(err)
  let formatsCsv = clipboardAvailableFormatsCsv(state.core)
  if formatsCsv.len == 0:
    return "EmptyClipboardFormats"
  ""

proc runUtilsClipboardClearTest(state: ptr AppState): string =
  block writeText:
    let err = state.core.clipboardWriteText("text to clear")
    if err != ebNone:
      return errName(err)
  block clearClipboard:
    let err2 = clipboardClear(state.core)
    if err2 != ebNone:
      return errName(err2)
  let (text, hasText) = clipboardReadText(state.core)
  if hasText and text.len != 0:
    return "ClipboardDidNotClear"
  ""

proc runUtilsShowNotificationTest(state: ptr AppState): string =
  let err = state.core.showNotification(NotificationOptions(
    title: "Test Notification",
    body: "This is a test notification from the Nim integration tests",
    subtitle: "Electrobun Nim Tests",
    silent: true,
  ))
  if err != ebNone:
    return errName(err)
  sleepMs(mediumWaitMs)
  ""

proc runUtilsOpenExternalExistsTest(): string =
  if appState().core.symbols.openExternal.isNil:
    return "MissingOpenExternal"
  ""

proc runUtilsOpenPathExistsTest(): string =
  if appState().core.symbols.openPath.isNil:
    return "MissingOpenPath"
  ""

proc runUtilsShowItemInFolderExistsTest(): string =
  if appState().core.symbols.showItemInFolder.isNil:
    return "MissingShowItemInFolder"
  ""

proc runUtilsQuitExistsTest(): string =
  if appState().core.symbols.quitGracefully.isNil:
    return "MissingQuitGracefully"
  ""



proc expectedHomePath(): (string, bool) =
  when defined(windows):
    let v = getEnv("USERPROFILE", "")
    if v != "": return (v, true)
  let home = getEnv("HOME", "")
  if home != "": return (home, true)
  ("", false)

proc expectedTempPath(): string =
  when defined(windows):
    for key in ["TEMP", "TMP"]:
      let v = getEnv(key, "")
      if v != "": return v
    return r"C:\Temp"
  let tmp = getEnv("TMPDIR", "")
  if tmp != "": return tmp
  "/tmp"

proc runUtilsPathsObjectExistsTest(state: ptr AppState): string =
  let (paths, pathsErr) = resolvePaths(state.appInfo)
  if pathsErr != ebNone: return errName(pathsErr)
  if paths.home.len == 0 or paths.appData.len == 0 or paths.userData.len == 0:
    return "PathsObjectMissingExpectedValues"
  ""

proc runUtilsPathsHomeMatchesTest(state: ptr AppState): string =
  let (paths, pathsErr) = resolvePaths(state.appInfo)
  if pathsErr != ebNone: return errName(pathsErr)
  let (expectedHome, found) = expectedHomePath()
  if not found: return "EnvVarNotFound"
  if paths.home != expectedHome: return "PathsHomeMismatch"
  ""

proc runUtilsPathsTempMatchesTest(state: ptr AppState): string =
  let (paths, pathsErr) = resolvePaths(state.appInfo)
  if pathsErr != ebNone: return errName(pathsErr)
  if paths.temp != expectedTempPath(): return "PathsTempMismatch"
  ""

proc runUtilsPathsOsDirectoriesTest(state: ptr AppState): string =
  let (paths, pathsErr) = resolvePaths(state.appInfo)
  if pathsErr != ebNone: return errName(pathsErr)
  for value in [paths.appData, paths.config, paths.cache, paths.logs, paths.documents, paths.downloads, paths.desktop, paths.pictures, paths.music, paths.videos]:
    if value.len == 0: return "EmptyOsDirectoryPath"
  ""

proc runUtilsPathsAppScopedDirectoriesTest(state: ptr AppState): string =
  let (paths, pathsErr) = resolvePaths(state.appInfo)
  if pathsErr != ebNone: return errName(pathsErr)
  for value in [paths.userData, paths.userCache, paths.userLogs]:
    if value.len == 0: return "EmptyAppScopedPath"
  if paths.userData.len <= paths.appData.len or paths.userCache.len <= paths.cache.len or paths.userLogs.len <= paths.logs.len:
    return "AppScopedPathsDidNotExtendBasePaths"
  ""

proc runUtilsPathsStableAcrossCallsTest(state: ptr AppState): string =
  let (pathsA, errA) = resolvePaths(state.appInfo)
  if errA != ebNone: return errName(errA)
  let (pathsB, errB) = resolvePaths(state.appInfo)
  if errB != ebNone: return errName(errB)
  if pathsA.home != pathsB.home or pathsA.downloads != pathsB.downloads or pathsA.userData != pathsB.userData:
    return "PathsWereNotStableAcrossCalls"
  ""

proc runUtilsMoveToTrashTest(state: ptr AppState): string =
  let (paths, pathsErr) = resolvePaths(state.appInfo)
  if pathsErr != ebNone: return errName(pathsErr)
  createDir(paths.userData)
  let testFileName = &"electrobun-nim-trash-{milliTimestamp()}.txt"
  let testFile = paths.userData / testFileName
  writeFile(testFile, "This file will be moved to trash")
  if not state.core.moveToTrash(testFile): return "MoveToTrashFailed"
  if fileExists(testFile): return "FileStillExistsAfterMoveToTrash"
  ""

proc runScreenPrimaryDisplayTest(state: ptr AppState): string =
  let (display, displayErr) = state.core.getPrimaryDisplay()
  if displayErr != ebNone: return errName(displayErr)
  if display.bounds.width <= 0 or display.bounds.height <= 0: return "InvalidPrimaryDisplayBounds"
  if not display.isPrimary: return "PrimaryDisplayNotMarkedPrimary"
  ""

proc runScreenAllDisplaysTest(state: ptr AppState): string =
  let (displays, displaysErr) = state.core.getAllDisplays()
  if displaysErr != ebNone: return errName(displaysErr)
  if displays.len == 0: return "NoDisplaysFound"
  var primaryCount = 0
  for display in displays:
    if display.bounds.width <= 0 or display.bounds.height <= 0: return "InvalidDisplayBounds"
    if display.isPrimary: inc primaryCount
  if primaryCount != 1: return "UnexpectedPrimaryDisplayCount"
  ""

proc runScreenCursorScreenPointTest(state: ptr AppState): string =
  let (point, pointErr) = state.core.getCursorScreenPoint()
  if pointErr != ebNone: return errName(pointErr)
  if point.x.isNaN or point.y.isNaN: return "InvalidCursorPoint"
  ""

proc runScreenCaptureRegionTest(state: ptr AppState): string =
  let (display, displayErr) = state.core.getPrimaryDisplay()
  if displayErr != ebNone: return errName(displayErr)
  let rect = Rect(
    x: floor(display.bounds.x + display.bounds.width / 2.0) - 1.0,
    y: floor(display.bounds.y + display.bounds.height / 2.0) - 1.0,
    width: 2.0,
    height: 2.0,
  )
  let (pixels, captureErr) = state.core.captureScreenRegion(rect)
  if captureErr != ebNone:
    when defined(windows): return errName(captureErr)
    else: return ""
  if pixels.len != 16: return "InvalidScreenCaptureLength"
  if pixels[3] != 255'u8 or pixels[7] != 255'u8 or pixels[11] != 255'u8 or pixels[15] != 255'u8:
    return "InvalidScreenCaptureAlpha"
  ""

proc runScreenBoundsVsWorkAreaTest(state: ptr AppState): string =
  let (display, displayErr) = state.core.getPrimaryDisplay()
  if displayErr != ebNone: return errName(displayErr)
  if display.workArea.width > display.bounds.width or display.workArea.height > display.bounds.height:
    return "WorkAreaExceedsBounds"
  ""

proc runNimTest(nimTest: NimTest): TestResult =
  let state = appState()
  let started = getMonoTime()
  var errorName = ""
  case nimTest.kind
  of smoke:
    errorName = runSmokeTest()
  of app_packaged_mode_reflects_build_channel:
    errorName = runAppPackagedModeReflectsBuildChannelTest(state)
  of window_create_close:
    errorName = runWindowCreateCloseTest(state)
  of window_creation_with_url:
    errorName = runWindowCreationWithUrlTest(state)
  of window_hidden_option:
    errorName = runWindowHiddenOptionTest(state)
  of window_inactive_show_api:
    errorName = runWindowInactiveShowApiTest(state)
  of window_page_zoom:
    errorName = runWindowPageZoomTest(state)
  of window_set_title:
    errorName = runWindowSetTitleTest(state)
  of window_minimize_unminimize:
    errorName = runWindowMinimizeUnminimizeTest(state)
  of window_fullscreen_toggle:
    errorName = runWindowFullscreenToggleTest(state)
  of window_fullscreen_toggle_hidden_titlebar:
    errorName = runWindowFullscreenToggleHiddenTitlebarTest(state)
  of window_omitted_position_centers_on_primary_display:
    errorName = runWindowOmittedPositionCentersOnPrimaryDisplayTest(state)
  of window_set_position:
    errorName = runWindowSetPositionTest(state)
  of window_set_size:
    errorName = runWindowSetSizeTest(state)
  of window_set_frame:
    errorName = runWindowSetFrameTest(state)
  of window_get_frame:
    errorName = runWindowGetFrameTest(state)
  of window_get_position:
    errorName = runWindowGetPositionTest(state)
  of window_get_size:
    errorName = runWindowGetSizeTest(state)
  of window_maximize_unmaximize:
    errorName = runWindowMaximizeUnmaximizeTest(state)
  of window_always_on_top:
    errorName = runWindowAlwaysOnTopTest(state)
  of window_visible_on_all_workspaces:
    errorName = runWindowVisibleOnAllWorkspacesTest(state)
  of window_focus:
    errorName = runWindowFocusTest(state)
  of window_close_event:
    errorName = runWindowCloseEventTest(state)
  of window_will_close_veto:
    errorName = runWindowWillCloseVetoTest(state)
  of window_resize_event:
    errorName = runWindowResizeEventTest(state)
  of window_get_by_id:
    errorName = runWindowGetByIdTest(state)
  of window_inset_titlebar_style:
    errorName = runWindowInsetTitlebarStyleTest(state)
  of window_traffic_light_position_api:
    errorName = runWindowTrafficLightPositionApiTest(state)
  of webview_create:
    errorName = runWebviewCreateTest(state)
  of webview_page_zoom:
    errorName = runWebviewPageZoomTest(state)
  of webview_spell_check:
    errorName = runWebviewSpellCheckTest(state)
  of appdata_protocol_allow:
    errorName = runAppDataProtocolTest(state, true)
  of appdata_protocol_deny:
    errorName = runAppDataProtocolTest(state, false)
  of webview_tag_playground_integration:
    errorName = runWebviewTagPlaygroundIntegrationTest(state)
  of webview_tag_playground_interactive:
    errorName = runWebviewTagPlaygroundInteractiveTest(state)
  of wgpu_tag_playground_integration:
    errorName = runWgpuTagPlaygroundIntegrationTest(state)
  of wgpu_tag_playground_interactive:
    errorName = runWgpuTagPlaygroundInteractiveTest(state)
  of navigation_load_url:
    errorName = runNavigationLoadUrlTest(state)
  of navigation_load_html:
    errorName = runNavigationLoadHtmlTest(state)
  of navigation_dom_ready_event:
    errorName = runNavigationDomReadyEventTest(state)
  of navigation_did_navigate_event:
    errorName = runNavigationDidNavigateEventTest(state)
  of navigation_did_commit_navigation_event:
    errorName = runNavigationDidCommitNavigationEventTest(state)
  of navigation_execute_javascript:
    errorName = runNavigationExecuteJavascriptTest(state)
  of tray_visibility_toggle_and_bounds:
    errorName = runTrayVisibilityToggleAndBoundsTest(state)
  of session_from_partition:
    errorName = runSessionFromPartitionTest(state)
  of session_default_session:
    errorName = runSessionDefaultSessionTest(state)
  of session_cookies_api_exists:
    errorName = runSessionCookiesApiExistsTest(state)
  of application_menu_playground:
    errorName = runApplicationMenuPlaygroundTest(state)
  of context_menu_playground:
    errorName = runContextMenuPlaygroundTest(state)
  of dialog_show_message_box_info:
    errorName = runShowMessageBoxInfoDialogTest(state)
  of dialog_file_dialog_playground:
    errorName = runFileDialogPlaygroundTest(state)
  of global_shortcuts_playground:
    errorName = runGlobalShortcutsPlaygroundTest(state)
  of global_shortcut_is_registered_api:
    errorName = runGlobalShortcutIsRegisteredApiTest(state)
  of global_shortcut_unregister_all_api:
    errorName = runGlobalShortcutUnregisterAllApiTest(state)
  of lifecycle_before_quit_cancel:
    errorName = runLifecycleBeforeQuitCancelTest(state)
  of quit_shutdown_playground:
    errorName = runQuitShutdownPlaygroundTest(state)
  of wgpu_adapter_context_device:
    errorName = runWgpuAdapterContextDeviceTest(state)
  of dock_icon_visibility_contract:
    errorName = runDockIconVisibilityContractTest(state)
  of utils_clipboard_round_trip:
    errorName = runUtilsClipboardRoundTripTest(state)
  of utils_clipboard_available_formats:
    errorName = runUtilsClipboardAvailableFormatsTest(state)
  of utils_clipboard_clear:
    errorName = runUtilsClipboardClearTest(state)
  of utils_show_notification:
    errorName = runUtilsShowNotificationTest(state)
  of utils_open_external_exists:
    errorName = runUtilsOpenExternalExistsTest()
  of utils_open_path_exists:
    errorName = runUtilsOpenPathExistsTest()
  of utils_show_item_in_folder_exists:
    errorName = runUtilsShowItemInFolderExistsTest()
  of utils_quit_exists:
    errorName = runUtilsQuitExistsTest()
  of utils_paths_object_exists:
    errorName = runUtilsPathsObjectExistsTest(state)
  of utils_paths_home_matches:
    errorName = runUtilsPathsHomeMatchesTest(state)
  of utils_paths_temp_matches:
    errorName = runUtilsPathsTempMatchesTest(state)
  of utils_paths_os_directories:
    errorName = runUtilsPathsOsDirectoriesTest(state)
  of utils_paths_app_scoped_directories:
    errorName = runUtilsPathsAppScopedDirectoriesTest(state)
  of utils_paths_stable_across_calls:
    errorName = runUtilsPathsStableAcrossCallsTest(state)
  of utils_move_to_trash:
    errorName = runUtilsMoveToTrashTest(state)
  of screen_primary_display:
    errorName = runScreenPrimaryDisplayTest(state)
  of screen_all_displays:
    errorName = runScreenAllDisplaysTest(state)
  of screen_cursor_screen_point:
    errorName = runScreenCursorScreenPointTest(state)
  of screen_capture_region:
    errorName = runScreenCaptureRegionTest(state)
  of screen_bounds_vs_workarea:
    errorName = runScreenBoundsVsWorkAreaTest(state)
  else:
    errorName = "UnknownTestKind"
  let elapsedMs = uint64((getMonoTime() - started).inMilliseconds)
  if errorName == "":
    return TestResult(testId: nimTest.id, name: nimTest.name, status: "passed", duration: elapsedMs)
  return TestResult(testId: nimTest.id, name: nimTest.name, status: "failed", duration: elapsedMs, error: some(errorName))

proc executeSingleTestAndBroadcast(webviewId: uint32; nimTest: NimTest): TestResult =
  stderr.writeLine(fmt"[kitchen nim] running test: {nimTest.name}")
  sendRpcMessage(webviewId, "testStarted", TestStartedPayload(testId: nimTest.id, name: nimTest.name))
  sendTestLog(webviewId, nimTest.id, "Running Nim native test")
  let result = runNimTest(nimTest)
  if result.error.isSome:
    stderr.writeLine(fmt"[kitchen nim] failed test: {nimTest.name}: {result.error.get()}")
    sendTestLog(webviewId, nimTest.id, result.error.get())
  sendRpcMessage(webviewId, "testCompleted", TestCompletedPayload(testId: nimTest.id, result: result))
  stderr.writeLine(fmt"[kitchen nim] completed test: {nimTest.name} -> {result.status}")
  result

proc runSelectedTests(webviewId: uint32; interactiveOnly: bool): seq[TestResult] =
  var results: seq[TestResult] = @[]
  for nimTest in nimTests:
    if nimTest.interactive != interactiveOnly:
      continue
    results.add executeSingleTestAndBroadcast(webviewId, nimTest)
  sendRpcMessage(webviewId, "allCompleted", AllCompletedPayload(results: results))
  results

proc autoRunExitCode(results: openArray[TestResult]): cint =
  for result in results:
    if result.status == "failed":
      return 1
  0

proc finishAutoRun(exitCode: cint) =
  stderr.writeLine(fmt"[kitchen nim] auto-run complete; exiting with code {exitCode}")
  sleepMs(500)
  appState().core.quitGracefully(exitCode)

proc runSingleTestJob(job: ptr SingleTestJob) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      let result = executeSingleTestAndBroadcast(job.webviewId, job.nimTest)
      if job.requestId.isSome:
        sendRpcResponseSuccess(job.webviewId, job.requestId.get(), result)
      else:
        finishAutoRun(autoRunExitCode(@[result]))
    finally:
      dealloc(job)

proc runAllTestsJob(job: ptr AllTestsJob) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      let results = runSelectedTests(job.webviewId, job.interactiveOnly)
      if job.requestId.isSome:
        sendRpcResponseSuccess(job.webviewId, job.requestId.get(), results)
      else:
        finishAutoRun(autoRunExitCode(results))
    finally:
      dealloc(job)

proc startSingleTest(webviewId: uint32; requestId: Option[uint64]; nimTest: NimTest): bool =
  var job = cast[ptr SingleTestJob](alloc0(sizeOf(SingleTestJob)))
  if job.isNil:
    stderr.writeLine("[kitchen nim] failed to allocate single test job")
    if requestId.isSome:
      sendRpcResponseError(webviewId, requestId.get(), "Failed to allocate test job")
    return false
  job.webviewId = webviewId
  job.requestId = requestId
  job.nimTest = nimTest
  var testThread: Thread[ptr SingleTestJob]
  createThread(testThread, runSingleTestJob, job)
  true

proc startAllTests(webviewId: uint32; requestId: Option[uint64]; interactiveOnly: bool): bool =
  var job = cast[ptr AllTestsJob](alloc0(sizeOf(AllTestsJob)))
  if job.isNil:
    stderr.writeLine("[kitchen nim] failed to allocate all-tests job")
    if requestId.isSome:
      sendRpcResponseError(webviewId, requestId.get(), "Failed to allocate all-tests job")
    return false
  job.webviewId = webviewId
  job.requestId = requestId
  job.interactiveOnly = interactiveOnly
  var allTestsThread: Thread[ptr AllTestsJob]
  createThread(allTestsThread, runAllTestsJob, job)
  true

proc maybeAutoRunAfterHandshake(webviewId: uint32) =
  let state = appState()
  var autoRunAll = false
  var autoRunTestName = ""
  var hasAutoRunTestName = false
  var autoRunTest = default(NimTest)
  var autoRunTestFound = false
  state.mutex.acquire()
  if state.autoRunTriggered:
    state.mutex.release()
    return
  if not state.autoRunAll and state.autoRunTestName.isNone:
    state.mutex.release()
    return
  state.autoRunTriggered = true
  autoRunAll = state.autoRunAll
  if state.autoRunTestName.isSome:
    autoRunTestName = state.autoRunTestName.get()
    hasAutoRunTestName = true
    (autoRunTest, autoRunTestFound) = findTestByName(autoRunTestName)
  state.mutex.release()
  if hasAutoRunTestName:
    stderr.writeLine(fmt"[kitchen nim] auto-running test: {autoRunTestName}")
    if autoRunTestFound:
      if not startSingleTest(webviewId, none(uint64), autoRunTest):
        finishAutoRun(1)
    else:
      stderr.writeLine(fmt"[kitchen nim] failed to find auto-run test: {autoRunTestName}")
      finishAutoRun(1)
    return
  if autoRunAll:
    stderr.writeLine("[kitchen nim] auto-running all automated tests")
    if not startAllTests(webviewId, none(uint64), false):
      finishAutoRun(1)

proc rpcRequestId(value: JsonNode): (uint64, bool) =
  case value.kind
  of JInt:
    (uint64(value.getInt()), true)
  of JFloat:
    (uint64(value.getFloat()), true)
  else:
    (0'u64, false)

proc handleRpcRequest(webviewId: uint32; requestId: uint64; rpcMethod: string; params: JsonNode) =
  stderr.writeLine(fmt"[kitchen nim] RPC request: {rpcMethod}")
  if rpcMethod == "getTests":
    var tests: seq[TestInfo] = @[]
    for nimTest in nimTests:
      tests.add testToInfo(nimTest)
    sendRpcResponseSuccess(webviewId, requestId, tests)
    sendInitialUiState(webviewId)
    maybeAutoRunAfterHandshake(webviewId)
    return
  if rpcMethod == "getTestRunnerPreferences":
    sendRpcResponseSuccess(webviewId, requestId, SearchPreferencesPayload(searchQuery: getSearchQuery()))
    sendInitialUiState(webviewId)
    return
  if rpcMethod == "setTestRunnerPreferences":
    if params.kind == JObject:
      let (query, hasQuery) = getJsonStringField(params, "searchQuery")
      if hasQuery:
        setSearchQuery(query)
    sendRpcResponseSuccess(webviewId, requestId, EmptyPayload())
    return
  if rpcMethod == "wgpuTagReady":
    if params.kind != JObject:
      sendRpcResponseError(webviewId, requestId, "Invalid wgpuTagReady params")
      return
    let wgpuViewId = getJsonU32Field(params, "id", 0)
    if wgpuViewId == 0:
      sendRpcResponseError(webviewId, requestId, "Missing WGPU view id")
      return
    let err = appState().core.runWGPUViewTest(wgpuViewId)
    if err != ebNone:
      sendRpcResponseError(webviewId, requestId, errName(err))
      return
    recordWgpuTagReady()
    sendRpcResponseSuccess(webviewId, requestId, SuccessPayload(success: true))
    return
  if rpcMethod == "wgpuTagToggleShader":
    if params.kind != JObject:
      sendRpcResponseError(webviewId, requestId, "Invalid wgpuTagToggleShader params")
      return
    let wgpuViewId = getJsonU32Field(params, "id", 0)
    if wgpuViewId == 0:
      sendRpcResponseError(webviewId, requestId, "Missing WGPU view id")
      return
    let err2 = appState().core.toggleWGPUViewTestShader(wgpuViewId)
    if err2 != ebNone:
      sendRpcResponseError(webviewId, requestId, errName(err2))
      return
    sendRpcResponseSuccess(webviewId, requestId, SuccessPayload(success: true))
    return
  if rpcMethod == "closeWindow":
    let (windowId, found) = windowIdForTopLevelWebview(webviewId)
    if not found:
      sendRpcResponseError(webviewId, requestId, "No top-level window for requesting webview")
      return
    let err3 = appState().core.closeWindow(windowId)
    if err3 != ebNone:
      sendRpcResponseError(webviewId, requestId, errName(err3))
      return
    forgetTopLevelWebview(webviewId)
    sendRpcResponseSuccess(webviewId, requestId, SuccessPayload(success: true))
    return
  if rpcMethod == "setApplicationMenu":
    if params.kind != JObject or "menu" notin params:
      sendRpcResponseError(webviewId, requestId, "Missing menu payload")
      return
    let (menuJson, ok) = prepareMenuJson(params["menu"])
    if not ok:
      sendRpcResponseError(webviewId, requestId, "PrepareMenuJsonFailed")
      return
    setApplicationMenuTargetWebview(webviewId)
    let err4 = appState().core.setApplicationMenuJson(menuJson, statusItemHandler(applicationMenuHandler))
    if err4 != ebNone:
      sendRpcResponseError(webviewId, requestId, errName(err4))
      return
    sendRpcResponseSuccess(webviewId, requestId, SuccessPayload(success: true))
    return
  if rpcMethod == "showContextMenu":
    if params.kind != JObject or "menu" notin params:
      sendRpcResponseError(webviewId, requestId, "Missing menu payload")
      return
    let (menuJson, ok) = prepareMenuJson(params["menu"])
    if not ok:
      sendRpcResponseError(webviewId, requestId, "PrepareMenuJsonFailed")
      return
    setContextMenuTargetWebview(webviewId)
    let err5 = appState().core.showContextMenuJson(menuJson, statusItemHandler(contextMenuHandler))
    if err5 != ebNone:
      sendRpcResponseError(webviewId, requestId, errName(err5))
      return
    sendRpcResponseSuccess(webviewId, requestId, SuccessPayload(success: true))
    return
  if rpcMethod == "openFileDialog":
    if params.kind != JObject:
      sendRpcResponseError(webviewId, requestId, "Invalid openFileDialog params")
      return
    var (startingFolder, hasStartingFolder) = getJsonStringField(params, "startingFolder")
    if not hasStartingFolder:
      startingFolder = "~/"
    let (expandedFolder, expanded) = expandTildePathAlloc(startingFolder)
    if not expanded:
      sendRpcResponseError(webviewId, requestId, "EnvVarNotFound")
      return
    var options = defaultOpenFileDialogOptions()
    options.startingFolder = expandedFolder
    let (allowedTypes, hasAllowedTypes) = getJsonStringField(params, "allowedFileTypes")
    if hasAllowedTypes:
      options.allowedFileTypes = allowedTypes
    options.canChooseFiles = getJsonBoolField(params, "canChooseFiles", true)
    options.canChooseDirectory = getJsonBoolField(params, "canChooseDirectory", true)
    options.allowsMultipleSelection = getJsonBoolField(params, "allowsMultipleSelection", true)
    let (paths, dialogErr) = appState().core.openFileDialogPaths(options)
    if dialogErr != ebNone:
      sendRpcResponseError(webviewId, requestId, errName(dialogErr))
      return
    sendRpcResponseSuccess(webviewId, requestId, paths)
    return
  if rpcMethod == "registerShortcut":
    if params.kind != JObject:
      sendRpcResponseError(webviewId, requestId, "Invalid registerShortcut params")
      return
    let (accelerator, hasAccelerator) = getJsonStringField(params, "accelerator")
    if not hasAccelerator:
      sendRpcResponseError(webviewId, requestId, "Missing accelerator")
      return
    setShortcutTargetWebview(webviewId)
    let success = appState().core.registerGlobalShortcut(accelerator)
    sendRpcResponseSuccess(webviewId, requestId, SuccessPayload(success: success))
    return
  if rpcMethod == "unregisterShortcut":
    if params.kind != JObject:
      sendRpcResponseError(webviewId, requestId, "Invalid unregisterShortcut params")
      return
    let (accelerator, hasAccelerator) = getJsonStringField(params, "accelerator")
    if not hasAccelerator:
      sendRpcResponseError(webviewId, requestId, "Missing accelerator")
      return
    let success = appState().core.unregisterGlobalShortcut(accelerator)
    sendRpcResponseSuccess(webviewId, requestId, SuccessPayload(success: success))
    return
  if rpcMethod == "unregisterAllShortcuts":
    let err6 = appState().core.unregisterAllGlobalShortcuts()
    if err6 != ebNone:
      sendRpcResponseError(webviewId, requestId, errName(err6))
      return
    sendRpcResponseSuccess(webviewId, requestId, SuccessPayload(success: true))
    return
  if rpcMethod == "isRegistered":
    if params.kind != JObject:
      sendRpcResponseError(webviewId, requestId, "Invalid isRegistered params")
      return
    let (accelerator, hasAccelerator) = getJsonStringField(params, "accelerator")
    if not hasAccelerator:
      sendRpcResponseError(webviewId, requestId, "Missing accelerator")
      return
    let registered = appState().core.isGlobalShortcutRegistered(accelerator)
    sendRpcResponseSuccess(webviewId, requestId, RegisteredPayload(registered: registered))
    return
  if rpcMethod == "triggerQuit":
    setQuitTargetWebview(webviewId)
    setBeforeQuitShouldCancel(true)
    quitRequestedHandler()
    sendRpcResponseSuccess(
      webviewId,
      requestId,
      SuccessMessagePayload(
        success: true,
        message: "Quit handled through Nim before-quit callback and cancelled for playground mode.",
      ),
    )
    return
  if rpcMethod == "runTest":
    if params.kind != JObject or "testId" notin params:
      sendRpcResponseError(webviewId, requestId, "Missing testId")
      return
    let testId =
      if params["testId"].kind == JString: params["testId"].getStr() else: ""
    if testId.len == 0:
      sendRpcResponseError(webviewId, requestId, "Invalid testId")
      return
    let (nimTest, found) = findTestById(testId)
    if not found:
      sendRpcResponseError(webviewId, requestId, "Unknown test id")
      return
    discard startSingleTest(webviewId, some(requestId), nimTest)
    return
  if rpcMethod == "runAllAutomated":
    discard startAllTests(webviewId, some(requestId), false)
    return
  if rpcMethod == "runInteractiveTests":
    discard startAllTests(webviewId, some(requestId), true)
    return
  if rpcMethod in ["submitInteractiveResult", "submitReady", "submitVerification", "applyUpdate", "clearUpdateStatusHistory"]:
    sendRpcResponseSuccess(webviewId, requestId, EmptyPayload())
    return
  if rpcMethod == "getUpdateStatusHistory":
    sendRpcResponseSuccess(webviewId, requestId, newJArray())
    return
  sendRpcResponseError(webviewId, requestId, "Unknown RPC request")

proc handleRpcMessage(messageId: string; payload: JsonNode) =
  if messageId == "logToBun" and payload.kind == JObject:
    let (msg, hasMsg) = getJsonStringField(payload, "msg")
    if hasMsg:
      stderr.writeLine("[kitchen nim ui] ", msg)

proc testRunnerWebviewEvent(webviewId: uint32; eventName: cstring; detail: cstring) {.cdecl.} =
  discard detail
  let state = appState()
  state.mutex.acquire()
  let isTestRunner = state.testRunnerWebviewId == webviewId
  state.mutex.release()
  if not isTestRunner:
    return
  if $eventName == "dom-ready":
    stderr.writeLine("[kitchen nim] test runner dom-ready")
    sendBuildConfig(webviewId)
    sendUpdateStatus(webviewId)

proc testRunnerHostBridge(webviewId: uint32; message: cstring) {.cdecl.} =
  let messageSlice = $message
  if messageSlice.len == 0:
    return
  let parsed =
    try:
      parseJson(messageSlice)
    except JsonParsingError as e:
      stderr.writeLine("[kitchen nim] failed to parse RPC packet: ", e.msg)
      return
  if parsed.kind != JObject:
    return
  let (packetType, hasPacketType) = getJsonStringField(parsed, "type")
  if not hasPacketType:
    return
  if packetType == "request":
    if "id" notin parsed:
      return
    let (rpcMethod, hasMethod) = getJsonStringField(parsed, "method")
    if not hasMethod:
      return
    let (requestId, hasRequestId) = rpcRequestId(parsed["id"])
    if not hasRequestId:
      return
    let params =
      if "params" in parsed: parsed["params"] else: newJNull()
    handleRpcRequest(webviewId, requestId, rpcMethod, params)
    return
  if packetType == "message":
    let (messageId, hasMessageId) = getJsonStringField(parsed, "id")
    if not hasMessageId:
      return
    let payload =
      if "payload" in parsed: parsed["payload"] else: newJNull()
    handleRpcMessage(messageId, payload)

proc createUi(uiContext: ptr CreateUiContext) =
  sleep(150)
  let state = uiContext.state
  let err = state.core.configureWebviewRuntimeFromExecutableDir(state.bundlePaths, 0)
  if err != ebNone:
    stderr.writeLine(fmt"[kitchen nim] failed to configure webview runtime: {errName(err)}")
    return
  var windowOptions = defaultWindowOptions("Electrobun Integration Tests")
  windowOptions.frame = Rect(x: 100, y: 100, width: 1200, height: 800)
  let (windowId, windowErr) = state.core.createWindow(windowOptions)
  if windowErr != ebNone:
    stderr.writeLine(fmt"[kitchen nim] failed to create test runner window: {errName(windowErr)}")
    return
  var webviewOptions = defaultWebviewOptions(windowId)
  webviewOptions.renderer = activePlaygroundRenderer(state)
  webviewOptions.url = "views://test-runner/index.html"
  webviewOptions.frame = Rect(x: 0, y: 0, width: 1200, height: 800)
  webviewOptions.secretKey = defaultSecretKey
  webviewOptions.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: webviewEventHandler(testRunnerWebviewEvent),
    eventBridge: noopWebviewPostMessage,
    hostBridge: webviewBridgeHandler(testRunnerHostBridge),
    internalBridge: noopWebviewPostMessage,
  )
  webviewOptions.sandbox = false
  let (runnerWebviewId, webviewErr) = state.core.createWebview(webviewOptions)
  if webviewErr != ebNone:
    stderr.writeLine(fmt"[kitchen nim] failed to create test runner webview: {errName(webviewErr)}")
    discard state.core.closeWindow(windowId)
    return
  state.mutex.acquire()
  state.testRunnerWindowId = windowId
  state.testRunnerWebviewId = runnerWebviewId
  state.mutex.release()

proc createUiThreadEntry(ctx: ptr CreateUiContext) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    createUi(ctx)

proc hostMessageQueueWorker() {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    drainHostMessageQueue()

proc main() =
  var core: Core
  var bundlePaths: BundlePaths
  var ownedAppInfo: OwnedAppInfo
  (core, bundlePaths) = (block:
    let (loadedCore, coreErr) = load()
    if coreErr != ebNone:
      stderr.writeLine(fmt"[kitchen nim] failed to load Electrobun core: {errName(coreErr)}")
      quit(1)
    let (paths, pathsErr) = resolveBundlePaths()
    if pathsErr != ebNone:
      stderr.writeLine(fmt"[kitchen nim] failed to resolve bundle paths: {errName(pathsErr)}")
      quit(1)
    (loadedCore, paths))
  defer:
    core.close()
  (ownedAppInfo) = block:
    let (info, infoErr) = resolveAppInfoFromBundle(bundlePaths)
    if infoErr != ebNone:
      stderr.writeLine(fmt"[kitchen nim] failed to resolve app info: {errName(infoErr)}")
      quit(1)
    info
  defer:
    ownedAppInfo.deinit()
  let appInfo = ownedAppInfo.borrowed()
  var autoRunAll = false
  var autoRunTestName = none(string)
  let autoRunTestNameEnv = getEnv("AUTO_RUN_TEST_NAME")
  if autoRunTestNameEnv.len > 0:
    autoRunTestName = some(autoRunTestNameEnv)
  if getEnv("AUTO_RUN").len > 0:
    autoRunAll = true
  var state = AppState(
    allocator: "",
    core: core,
    bundlePaths: bundlePaths,
    appInfo: appInfo,
    defaultRenderer: rNative,
    cefAvailable: false,
    childWebviews: initTable[uint32, ChildWebviewState](),
    topLevelWebviewWindows: initTable[uint32, uint32](),
    autoRunAll: autoRunAll,
    autoRunTestName: autoRunTestName,
    menuDataRegistry: initTable[string, string](),
    mutex: Lock(),
  )
  initLock(state.mutex)
  defer:
    appStateDeinit(state)
  let configErr = configureRuntimeBuildConfig(state)
  if configErr.len > 0:
    stderr.writeLine(fmt"[kitchen nim] failed to read runtime build config: {configErr}")
    quit(1)
  gState = addr state
  defer:
    gState = nil
  block setHandlers:
    let err = core.setGlobalShortcutCallback(cast[GlobalShortcutHandler](shortcutTriggeredHandler))
    if err != ebNone:
      stderr.writeLine(fmt"[kitchen nim] failed to set global shortcut callback: {errName(err)}")
      quit(1)
    let quitErr = core.setQuitRequestedHandler(cast[QuitRequestedHandler](quitRequestedHandler))
    if quitErr != ebNone:
      stderr.writeLine(fmt"[kitchen nim] failed to set quit requested handler: {errName(quitErr)}")
      quit(1)
    when defined(macosx):
      let reopenErr = core.setAppReopenHandler(cast[AppReopenHandler](appReopenHandler))
      if reopenErr != ebNone:
        stderr.writeLine(fmt"[kitchen nim] failed to set app reopen handler: {errName(reopenErr)}")
        quit(1)
      let urlErr = core.setURLOpenHandler(cast[URLOpenHandler](urlOpenHandler))
      if urlErr != ebNone:
        stderr.writeLine(fmt"[kitchen nim] failed to set URL open handler: {errName(urlErr)}")
        quit(1)
  var uiContext = CreateUiContext(state: addr state)
  var uiThread: Thread[ptr CreateUiContext]
  createThread(uiThread, createUiThreadEntry, addr uiContext)
  hostQueueRunning.store(true, moRelease)
  var hostThread: Thread[void]
  createThread(hostThread, hostMessageQueueWorker)
  defer:
    hostQueueRunning.store(false, moRelease)
    joinThread(hostThread)
  let runErr = core.runMainThread(appInfo)
  if runErr != ebNone:
    stderr.writeLine(fmt"[kitchen nim] main thread exited with error: {errName(runErr)}")
    quit(1)

when isMainModule:
  main()