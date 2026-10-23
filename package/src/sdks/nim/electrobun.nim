## Electrobun Nim SDK.
##
## Port of package/src/sdks/odin/electrobun.odin. Dynamically loads
## libElectrobunCore at runtime and wraps its C ABI entry points.

import std/[dynlib, os, strutils, json, math, sets, parseutils, options, macros]

const INSTALL_ROOT_NAME_ENVIRONMENT_VARIABLE* = "ELECTROBUN_INSTALL_ROOT_NAME"

type
  EbError* = enum
    ebNone
    ebMissingCoreSymbol
    ebLibraryLoadFailed
    ebElectrobunCoreFailure
    ebInvalidExePath
    ebInvalidRectJson
    ebInvalidJson
    ebFileReadFailed
    ebEnvVarNotFound
    ebInvalidScreenCaptureRegion
    ebAllocationFailed

  WindowCloseHandler* = proc (windowId: uint32) {.cdecl, raises: [].}
  WindowShouldCloseHandler* = proc (windowId: uint32) {.cdecl, raises: [].}
  WindowMoveHandler* = proc (windowId: uint32; x, y: float64) {.cdecl, raises: [].}
  WindowResizeHandler* = proc (windowId: uint32; x, y, width, height: float64) {.cdecl, raises: [].}
  WindowFocusHandler* = proc (windowId: uint32) {.cdecl, raises: [].}
  WindowBlurHandler* = proc (windowId: uint32) {.cdecl, raises: [].}
  WindowKeyHandler* = proc (windowId: uint32; a, b, c, d, e: uint32) {.cdecl, raises: [].}
  DecideNavigationHandler* = proc (webviewId: uint32; url: cstring): uint32 {.cdecl, raises: [].}
  WebviewEventHandler* = proc (webviewId: uint32; event, payload: cstring) {.cdecl, raises: [].}
  WebviewPostMessageHandler* = proc (webviewId: uint32; message: cstring) {.cdecl, raises: [].}
  StatusItemHandler* = proc (itemId: uint32; action: cstring) {.cdecl, raises: [].}
  GlobalShortcutHandler* = proc (accelerator: cstring) {.cdecl, raises: [].}
  QuitRequestedHandler* = proc () {.cdecl, raises: [].}
  URLOpenHandler* = proc (url: cstring) {.cdecl, raises: [].}
  AppReopenHandler* = proc () {.cdecl, raises: [].}

  LastErrorFn = proc (): cstring {.cdecl, raises: [].}
  RunMainThreadFn = proc (identifier, name, channel: cstring; flags: cint): cint {.cdecl, raises: [].}
  ConfigureWebviewRuntimeFn = proc (rpcPort: uint32; fullPreload, sandboxedPreload: cstring): bool {.cdecl, raises: [].}
  GetWindowStyleFn = proc (borderless, titled, closable, miniaturizable, resizable, unifiedTitleAndToolbar, fullScreen, fullSizeContentView, utilityWindow, docModalWindow, nonactivatingPanel, hudWindow: bool): uint32 {.cdecl, raises: [].}
  CreateWindowFn = proc (x, y, width, height: float64; styleMask: uint32; titleBarStyle: cstring; transparent: bool; title: cstring; hidden, activate, centered: bool; trafficLightX, trafficLightY: float64; close: WindowCloseHandler; move: WindowMoveHandler; resize: WindowResizeHandler; focus: WindowFocusHandler; blur: WindowBlurHandler; key: WindowKeyHandler; shouldClose: WindowShouldCloseHandler): uint32 {.cdecl, raises: [].}
  CreateWebviewFn = proc (windowId, hostWebviewId: uint32; renderer, url: cstring; x, y, width, height: float64; autoResize: bool; partition: cstring; decideNavigation: DecideNavigationHandler; event: WebviewEventHandler; eventBridge, hostBridge, internalBridge: WebviewPostMessageHandler; secretKey, preload, viewsRoot: cstring; sandbox, startTransparent, startPassthrough, spellCheck: bool): uint32 {.cdecl, raises: [].}
  SetNextWebviewAllowedProtocolsFn = proc (views, appData: bool) {.cdecl, raises: [].}
  CreateWGPUViewFn = proc (windowId: uint32; x, y, width, height: float64; autoResize, startTransparent, startPassthrough: bool): uint32 {.cdecl, raises: [].}
  SetWindowTitleFn = proc (windowId: uint32; title: cstring) {.cdecl, raises: [].}
  WindowIdFn = proc (windowId: uint32) {.cdecl, raises: [].}
  WindowIdBoolFn = proc (windowId: uint32): bool {.cdecl, raises: [].}
  SetWindowBoolFn = proc (windowId: uint32; value: bool) {.cdecl, raises: [].}
  SetWebviewSpellCheckFn = proc (webviewId: uint32; enabled: bool): bool {.cdecl, raises: [].}
  SetWindowXYFn = proc (windowId: uint32; x, y: float64) {.cdecl, raises: [].}
  GetWindowPointFn = proc (windowId: uint32; outX, outY: ptr float64) {.cdecl, raises: [].}
  SetWindowFrameFn = proc (windowId: uint32; x, y, width, height: float64) {.cdecl, raises: [].}
  GetWindowFrameFn = proc (windowId: uint32; outX, outY, outWidth, outHeight: ptr float64) {.cdecl, raises: [].}
  ResizeViewFn = proc (viewId: uint32; x, y, width, height: float64; masksJson: cstring) {.cdecl, raises: [].}
  IdCstringFn = proc (id: uint32; value: cstring) {.cdecl, raises: [].}
  UpdatePreloadScriptToWebViewFn = proc (webviewId: uint32; scriptIdentifier, script: cstring; allFrames: bool) {.cdecl, raises: [].}
  SendMessageToWebviewFn = proc (webviewId: uint32; message: cstring): bool {.cdecl, raises: [].}
  PopNextQueuedHostMessageFn = proc (outWebviewId: ptr uint32): cstring {.cdecl, raises: [].}
  FreeCoreStringFn = proc (value: cstring) {.cdecl, raises: [].}
  WebviewSetPageZoomFn = proc (webviewId: uint32; zoomLevel: float64) {.cdecl, raises: [].}
  WebviewGetPageZoomFn = proc (webviewId: uint32): float64 {.cdecl, raises: [].}
  WebviewFindInPageFn = proc (webviewId: uint32; searchText: cstring; forward, matchCase: bool) {.cdecl, raises: [].}
  GetViewPointerFn = proc (viewId: uint32): pointer {.cdecl, raises: [].}
  CreateTrayFn = proc (title, image: cstring; isTemplate: bool; width, height: uint32; handler: StatusItemHandler): uint32 {.cdecl, raises: [].}
  GetTrayBoundsFn = proc (trayId: uint32): cstring {.cdecl, raises: [].}
  SetBoolFn = proc (value: bool) {.cdecl, raises: [].}
  GetBoolFn = proc (): bool {.cdecl, raises: [].}
  GetCstringFn = proc (): cstring {.cdecl, raises: [].}
  CaptureScreenRegionFn = proc (x, y: float64; width, height: uint32; outRgba: pointer; outLen: uint64): bool {.cdecl, raises: [].}
  CstringToBoolFn = proc (value: cstring): bool {.cdecl, raises: [].}
  CstringVoidFn = proc (value: cstring) {.cdecl, raises: [].}
  ShowNotificationFn = proc (title, body, subtitle: cstring; silent: bool) {.cdecl, raises: [].}
  VoidFn = proc () {.cdecl, raises: [].}
  SetMenuFn = proc (menuJson: cstring; handler: StatusItemHandler) {.cdecl, raises: [].}
  OpenFileDialogFn = proc (startingFolder, allowedFileTypes: cstring; canChooseFiles, canChooseDirectory, allowsMultipleSelection: cint): cstring {.cdecl, raises: [].}
  ShowMessageBoxFn = proc (boxType, title, message, detail, buttons: cstring; defaultId, cancelId: cint): cint {.cdecl, raises: [].}
  SetGlobalShortcutCallbackFn = proc (callback: GlobalShortcutHandler) {.cdecl, raises: [].}
  SessionGetCookiesFn = proc (partition, filterJson: cstring): cstring {.cdecl, raises: [].}
  SessionSetCookieFn = proc (partition, cookieJson: cstring): bool {.cdecl, raises: [].}
  SessionRemoveCookieFn = proc (partition, url, name: cstring): bool {.cdecl, raises: [].}
  SessionClearStorageDataFn = proc (partition, storageTypesJson: cstring) {.cdecl, raises: [].}
  SetURLOpenHandlerFn = proc (handler: URLOpenHandler) {.cdecl, raises: [].}
  SetAppReopenHandlerFn = proc (handler: AppReopenHandler) {.cdecl, raises: [].}
  SetQuitRequestedHandlerFn = proc (handler: QuitRequestedHandler) {.cdecl, raises: [].}
  IntVoidFn = proc (value: cint) {.cdecl, raises: [].}
  QuitGracefullyFn = proc (code, timeoutMs: cint) {.cdecl, raises: [].}
  WgpuCreateSurfaceForViewFn = proc (instancePtr, viewPtr: pointer): pointer {.cdecl, raises: [].}
  WgpuTwoPtrVoidFn = proc (a, b: pointer) {.cdecl, raises: [].}
  WgpuThreePtrVoidFn = proc (a, b, c: pointer) {.cdecl, raises: [].}
  WgpuPresentFn = proc (surfacePtr: pointer): int32 {.cdecl, raises: [].}

  WgpuCreateInstanceFn = proc (descriptor: pointer): pointer {.cdecl, raises: [].}
  WgpuDeviceGetQueueFn = proc (device: pointer): pointer {.cdecl, raises: [].}

var
  gQuitRequestedStopEventLoop: VoidFn
  gQuitRequestedUserHandler: QuitRequestedHandler

proc quitRequestedTrampoline() {.cdecl, raises: [].} =
  if not gQuitRequestedUserHandler.isNil:
    gQuitRequestedUserHandler()
    return
  if not gQuitRequestedStopEventLoop.isNil:
    gQuitRequestedStopEventLoop()


type
  Symbols* = object
    handle*: LibHandle
    electrobun_core_last_error*: LastErrorFn
    electrobun_core_run_main_thread*: RunMainThreadFn
    configureWebviewRuntime*: ConfigureWebviewRuntimeFn
    getWindowStyle*: GetWindowStyleFn
    createWindow*: CreateWindowFn
    createWebview*: CreateWebviewFn
    setNextWebviewAllowedProtocols*: SetNextWebviewAllowedProtocolsFn
    createWGPUView*: CreateWGPUViewFn
    setWindowTitle*: SetWindowTitleFn
    minimizeWindow*: WindowIdFn
    restoreWindow*: WindowIdFn
    isWindowMinimized*: WindowIdBoolFn
    maximizeWindow*: WindowIdFn
    unmaximizeWindow*: WindowIdFn
    isWindowMaximized*: WindowIdBoolFn
    setWindowFullScreen*: SetWindowBoolFn
    isWindowFullScreen*: WindowIdBoolFn
    setWindowAlwaysOnTop*: SetWindowBoolFn
    isWindowAlwaysOnTop*: WindowIdBoolFn
    setWindowVisibleOnAllWorkspaces*: SetWindowBoolFn
    isWindowVisibleOnAllWorkspaces*: WindowIdBoolFn
    showWindow*: SetWindowBoolFn
    activateWindow*: WindowIdFn
    hideWindow*: WindowIdFn
    isWindowVisible*: WindowIdBoolFn
    setWindowButtonPosition*: SetWindowXYFn
    getWindowButtonPosition*: GetWindowPointFn
    setWindowPosition*: SetWindowXYFn
    centerWindow*: WindowIdFn
    setWindowSize*: SetWindowXYFn
    setWindowFrame*: SetWindowFrameFn
    getWindowFrame*: GetWindowFrameFn
    closeWindow*: WindowIdFn
    requestWindowClose*: WindowIdFn
    resizeWebview*: ResizeViewFn
    loadURLInWebView*: IdCstringFn
    loadHTMLInWebView*: IdCstringFn
    updatePreloadScriptToWebView*: UpdatePreloadScriptToWebViewFn
    webviewCanGoBack*: WindowIdBoolFn
    webviewCanGoForward*: WindowIdBoolFn
    webviewGoBack*: WindowIdFn
    webviewGoForward*: WindowIdFn
    webviewReload*: WindowIdFn
    webviewRemove*: WindowIdFn
    setWebviewHTMLContent*: IdCstringFn
    webviewSetTransparent*: SetWindowBoolFn
    webviewSetPassthrough*: SetWindowBoolFn
    webviewSetHidden*: SetWindowBoolFn
    webviewSetSpellCheck*: SetWebviewSpellCheckFn
    setWebviewNavigationRules*: IdCstringFn
    webviewFindInPage*: WebviewFindInPageFn
    webviewStopFind*: WindowIdFn
    sendInternalMessageToWebview*: SendMessageToWebviewFn
    sendHostMessageToWebviewViaTransport*: SendMessageToWebviewFn
    popNextQueuedHostMessage*: PopNextQueuedHostMessageFn
    freeCoreString*: FreeCoreStringFn
    webviewOpenDevTools*: WindowIdFn
    webviewCloseDevTools*: WindowIdFn
    webviewToggleDevTools*: WindowIdFn
    webviewSetPageZoom*: WebviewSetPageZoomFn
    webviewGetPageZoom*: WebviewGetPageZoomFn
    setWGPUViewFrame*: SetWindowFrameFn
    resizeWGPUView*: ResizeViewFn
    setWGPUViewTransparent*: SetWindowBoolFn
    setWGPUViewPassthrough*: SetWindowBoolFn
    setWGPUViewHidden*: SetWindowBoolFn
    removeWGPUView*: WindowIdFn
    getWGPUViewPointer*: GetViewPointerFn
    getWGPUViewNativeHandle*: GetViewPointerFn
    runWGPUViewTest*: WindowIdFn
    toggleWGPUViewTestShader*: WindowIdFn
    evaluateJavaScriptWithNoCompletion*: IdCstringFn
    createTray*: CreateTrayFn
    showTray*: WindowIdBoolFn
    hideTray*: WindowIdFn
    setTrayTitle*: IdCstringFn
    removeTray*: WindowIdFn
    getTrayBounds*: GetTrayBoundsFn
    setDockIconVisible*: SetBoolFn
    isDockIconVisible*: GetBoolFn
    getPrimaryDisplay*: GetCstringFn
    getAllDisplays*: GetCstringFn
    getCursorScreenPoint*: GetCstringFn
    captureScreenRegion*: CaptureScreenRegionFn
    moveToTrash*: CstringToBoolFn
    showItemInFolder*: CstringVoidFn
    openExternal*: CstringToBoolFn
    openPath*: CstringToBoolFn
    showNotification*: ShowNotificationFn
    clipboardReadText*: GetCstringFn
    clipboardWriteText*: CstringVoidFn
    clipboardClear*: VoidFn
    clipboardAvailableFormats*: GetCstringFn
    setApplicationMenu*: SetMenuFn
    showContextMenu*: SetMenuFn
    openFileDialog*: OpenFileDialogFn
    showMessageBox*: ShowMessageBoxFn
    setGlobalShortcutCallback*: SetGlobalShortcutCallbackFn
    registerGlobalShortcut*: CstringToBoolFn
    unregisterGlobalShortcut*: CstringToBoolFn
    unregisterAllGlobalShortcuts*: VoidFn
    isGlobalShortcutRegistered*: CstringToBoolFn
    sessionGetCookies*: SessionGetCookiesFn
    sessionSetCookie*: SessionSetCookieFn
    sessionRemoveCookie*: SessionRemoveCookieFn
    sessionClearCookies*: CstringVoidFn
    sessionClearStorageData*: SessionClearStorageDataFn
    setURLOpenHandler*: SetURLOpenHandlerFn
    setAppReopenHandler*: SetAppReopenHandlerFn
    setQuitRequestedHandler*: SetQuitRequestedHandlerFn
    setExitOnLastWindowClosed*: SetBoolFn
    stopEventLoop*: VoidFn
    waitForShutdownComplete*: IntVoidFn
    forceExit*: IntVoidFn
    quitGracefully*: QuitGracefullyFn
    wgpuCreateSurfaceForView*: WgpuCreateSurfaceForViewFn
    wgpuCreateAdapterDeviceMainThread*: WgpuThreePtrVoidFn
    wgpuSurfaceConfigureMainThread*: WgpuTwoPtrVoidFn
    wgpuSurfaceGetCurrentTextureMainThread*: WgpuTwoPtrVoidFn
    wgpuSurfacePresentMainThread*: WgpuPresentFn
proc loadSymbolsInto*(handle: LibHandle; syms: var Symbols): Option[string] =
  syms.handle = handle
  syms.electrobun_core_last_error = cast[LastErrorFn](symAddr(handle, "electrobun_core_last_error"))
  if syms.electrobun_core_last_error.isNil: return some("electrobun_core_last_error")
  syms.electrobun_core_run_main_thread = cast[RunMainThreadFn](symAddr(handle, "electrobun_core_run_main_thread"))
  if syms.electrobun_core_run_main_thread.isNil: return some("electrobun_core_run_main_thread")
  syms.configureWebviewRuntime = cast[ConfigureWebviewRuntimeFn](symAddr(handle, "configureWebviewRuntime"))
  if syms.configureWebviewRuntime.isNil: return some("configureWebviewRuntime")
  syms.getWindowStyle = cast[GetWindowStyleFn](symAddr(handle, "getWindowStyle"))
  if syms.getWindowStyle.isNil: return some("getWindowStyle")
  syms.createWindow = cast[CreateWindowFn](symAddr(handle, "createWindow"))
  if syms.createWindow.isNil: return some("createWindow")
  syms.createWebview = cast[CreateWebviewFn](symAddr(handle, "createWebview"))
  if syms.createWebview.isNil: return some("createWebview")
  syms.setNextWebviewAllowedProtocols = cast[SetNextWebviewAllowedProtocolsFn](symAddr(handle, "setNextWebviewAllowedProtocols"))
  if syms.setNextWebviewAllowedProtocols.isNil: return some("setNextWebviewAllowedProtocols")
  syms.createWGPUView = cast[CreateWGPUViewFn](symAddr(handle, "createWGPUView"))
  if syms.createWGPUView.isNil: return some("createWGPUView")
  syms.setWindowTitle = cast[SetWindowTitleFn](symAddr(handle, "setWindowTitle"))
  if syms.setWindowTitle.isNil: return some("setWindowTitle")
  syms.minimizeWindow = cast[WindowIdFn](symAddr(handle, "minimizeWindow"))
  if syms.minimizeWindow.isNil: return some("minimizeWindow")
  syms.restoreWindow = cast[WindowIdFn](symAddr(handle, "restoreWindow"))
  if syms.restoreWindow.isNil: return some("restoreWindow")
  syms.isWindowMinimized = cast[WindowIdBoolFn](symAddr(handle, "isWindowMinimized"))
  if syms.isWindowMinimized.isNil: return some("isWindowMinimized")
  syms.maximizeWindow = cast[WindowIdFn](symAddr(handle, "maximizeWindow"))
  if syms.maximizeWindow.isNil: return some("maximizeWindow")
  syms.unmaximizeWindow = cast[WindowIdFn](symAddr(handle, "unmaximizeWindow"))
  if syms.unmaximizeWindow.isNil: return some("unmaximizeWindow")
  syms.isWindowMaximized = cast[WindowIdBoolFn](symAddr(handle, "isWindowMaximized"))
  if syms.isWindowMaximized.isNil: return some("isWindowMaximized")
  syms.setWindowFullScreen = cast[SetWindowBoolFn](symAddr(handle, "setWindowFullScreen"))
  if syms.setWindowFullScreen.isNil: return some("setWindowFullScreen")
  syms.isWindowFullScreen = cast[WindowIdBoolFn](symAddr(handle, "isWindowFullScreen"))
  if syms.isWindowFullScreen.isNil: return some("isWindowFullScreen")
  syms.setWindowAlwaysOnTop = cast[SetWindowBoolFn](symAddr(handle, "setWindowAlwaysOnTop"))
  if syms.setWindowAlwaysOnTop.isNil: return some("setWindowAlwaysOnTop")
  syms.isWindowAlwaysOnTop = cast[WindowIdBoolFn](symAddr(handle, "isWindowAlwaysOnTop"))
  if syms.isWindowAlwaysOnTop.isNil: return some("isWindowAlwaysOnTop")
  syms.setWindowVisibleOnAllWorkspaces = cast[SetWindowBoolFn](symAddr(handle, "setWindowVisibleOnAllWorkspaces"))
  if syms.setWindowVisibleOnAllWorkspaces.isNil: return some("setWindowVisibleOnAllWorkspaces")
  syms.isWindowVisibleOnAllWorkspaces = cast[WindowIdBoolFn](symAddr(handle, "isWindowVisibleOnAllWorkspaces"))
  if syms.isWindowVisibleOnAllWorkspaces.isNil: return some("isWindowVisibleOnAllWorkspaces")
  syms.showWindow = cast[SetWindowBoolFn](symAddr(handle, "showWindow"))
  if syms.showWindow.isNil: return some("showWindow")
  syms.activateWindow = cast[WindowIdFn](symAddr(handle, "activateWindow"))
  if syms.activateWindow.isNil: return some("activateWindow")
  syms.hideWindow = cast[WindowIdFn](symAddr(handle, "hideWindow"))
  if syms.hideWindow.isNil: return some("hideWindow")
  syms.isWindowVisible = cast[WindowIdBoolFn](symAddr(handle, "isWindowVisible"))
  if syms.isWindowVisible.isNil: return some("isWindowVisible")
  syms.setWindowButtonPosition = cast[SetWindowXYFn](symAddr(handle, "setWindowButtonPosition"))
  if syms.setWindowButtonPosition.isNil: return some("setWindowButtonPosition")
  syms.getWindowButtonPosition = cast[GetWindowPointFn](symAddr(handle, "getWindowButtonPosition"))
  if syms.getWindowButtonPosition.isNil: return some("getWindowButtonPosition")
  syms.setWindowPosition = cast[SetWindowXYFn](symAddr(handle, "setWindowPosition"))
  if syms.setWindowPosition.isNil: return some("setWindowPosition")
  syms.centerWindow = cast[WindowIdFn](symAddr(handle, "centerWindow"))
  if syms.centerWindow.isNil: return some("centerWindow")
  syms.setWindowSize = cast[SetWindowXYFn](symAddr(handle, "setWindowSize"))
  if syms.setWindowSize.isNil: return some("setWindowSize")
  syms.setWindowFrame = cast[SetWindowFrameFn](symAddr(handle, "setWindowFrame"))
  if syms.setWindowFrame.isNil: return some("setWindowFrame")
  syms.getWindowFrame = cast[GetWindowFrameFn](symAddr(handle, "getWindowFrame"))
  if syms.getWindowFrame.isNil: return some("getWindowFrame")
  syms.closeWindow = cast[WindowIdFn](symAddr(handle, "closeWindow"))
  if syms.closeWindow.isNil: return some("closeWindow")
  syms.requestWindowClose = cast[WindowIdFn](symAddr(handle, "requestWindowClose"))
  if syms.requestWindowClose.isNil: return some("requestWindowClose")
  syms.resizeWebview = cast[ResizeViewFn](symAddr(handle, "resizeWebview"))
  if syms.resizeWebview.isNil: return some("resizeWebview")
  syms.loadURLInWebView = cast[IdCstringFn](symAddr(handle, "loadURLInWebView"))
  if syms.loadURLInWebView.isNil: return some("loadURLInWebView")
  syms.loadHTMLInWebView = cast[IdCstringFn](symAddr(handle, "loadHTMLInWebView"))
  if syms.loadHTMLInWebView.isNil: return some("loadHTMLInWebView")
  syms.updatePreloadScriptToWebView = cast[UpdatePreloadScriptToWebViewFn](symAddr(handle, "updatePreloadScriptToWebView"))
  if syms.updatePreloadScriptToWebView.isNil: return some("updatePreloadScriptToWebView")
  syms.webviewCanGoBack = cast[WindowIdBoolFn](symAddr(handle, "webviewCanGoBack"))
  if syms.webviewCanGoBack.isNil: return some("webviewCanGoBack")
  syms.webviewCanGoForward = cast[WindowIdBoolFn](symAddr(handle, "webviewCanGoForward"))
  if syms.webviewCanGoForward.isNil: return some("webviewCanGoForward")
  syms.webviewGoBack = cast[WindowIdFn](symAddr(handle, "webviewGoBack"))
  if syms.webviewGoBack.isNil: return some("webviewGoBack")
  syms.webviewGoForward = cast[WindowIdFn](symAddr(handle, "webviewGoForward"))
  if syms.webviewGoForward.isNil: return some("webviewGoForward")
  syms.webviewReload = cast[WindowIdFn](symAddr(handle, "webviewReload"))
  if syms.webviewReload.isNil: return some("webviewReload")
  syms.webviewRemove = cast[WindowIdFn](symAddr(handle, "webviewRemove"))
  if syms.webviewRemove.isNil: return some("webviewRemove")
  syms.setWebviewHTMLContent = cast[IdCstringFn](symAddr(handle, "setWebviewHTMLContent"))
  if syms.setWebviewHTMLContent.isNil: return some("setWebviewHTMLContent")
  syms.webviewSetTransparent = cast[SetWindowBoolFn](symAddr(handle, "webviewSetTransparent"))
  if syms.webviewSetTransparent.isNil: return some("webviewSetTransparent")
  syms.webviewSetPassthrough = cast[SetWindowBoolFn](symAddr(handle, "webviewSetPassthrough"))
  if syms.webviewSetPassthrough.isNil: return some("webviewSetPassthrough")
  syms.webviewSetHidden = cast[SetWindowBoolFn](symAddr(handle, "webviewSetHidden"))
  if syms.webviewSetHidden.isNil: return some("webviewSetHidden")
  syms.webviewSetSpellCheck = cast[SetWebviewSpellCheckFn](symAddr(handle, "webviewSetSpellCheck"))
  if syms.webviewSetSpellCheck.isNil: return some("webviewSetSpellCheck")
  syms.setWebviewNavigationRules = cast[IdCstringFn](symAddr(handle, "setWebviewNavigationRules"))
  if syms.setWebviewNavigationRules.isNil: return some("setWebviewNavigationRules")
  syms.webviewFindInPage = cast[WebviewFindInPageFn](symAddr(handle, "webviewFindInPage"))
  if syms.webviewFindInPage.isNil: return some("webviewFindInPage")
  syms.webviewStopFind = cast[WindowIdFn](symAddr(handle, "webviewStopFind"))
  if syms.webviewStopFind.isNil: return some("webviewStopFind")
  syms.sendInternalMessageToWebview = cast[SendMessageToWebviewFn](symAddr(handle, "sendInternalMessageToWebview"))
  if syms.sendInternalMessageToWebview.isNil: return some("sendInternalMessageToWebview")
  syms.sendHostMessageToWebviewViaTransport = cast[SendMessageToWebviewFn](symAddr(handle, "sendHostMessageToWebviewViaTransport"))
  if syms.sendHostMessageToWebviewViaTransport.isNil: return some("sendHostMessageToWebviewViaTransport")
  syms.popNextQueuedHostMessage = cast[PopNextQueuedHostMessageFn](symAddr(handle, "popNextQueuedHostMessage"))
  if syms.popNextQueuedHostMessage.isNil: return some("popNextQueuedHostMessage")
  syms.freeCoreString = cast[FreeCoreStringFn](symAddr(handle, "freeCoreString"))
  if syms.freeCoreString.isNil: return some("freeCoreString")
  syms.webviewOpenDevTools = cast[WindowIdFn](symAddr(handle, "webviewOpenDevTools"))
  if syms.webviewOpenDevTools.isNil: return some("webviewOpenDevTools")
  syms.webviewCloseDevTools = cast[WindowIdFn](symAddr(handle, "webviewCloseDevTools"))
  if syms.webviewCloseDevTools.isNil: return some("webviewCloseDevTools")
  syms.webviewToggleDevTools = cast[WindowIdFn](symAddr(handle, "webviewToggleDevTools"))
  if syms.webviewToggleDevTools.isNil: return some("webviewToggleDevTools")
  syms.webviewSetPageZoom = cast[WebviewSetPageZoomFn](symAddr(handle, "webviewSetPageZoom"))
  if syms.webviewSetPageZoom.isNil: return some("webviewSetPageZoom")
  syms.webviewGetPageZoom = cast[WebviewGetPageZoomFn](symAddr(handle, "webviewGetPageZoom"))
  if syms.webviewGetPageZoom.isNil: return some("webviewGetPageZoom")
  syms.setWGPUViewFrame = cast[SetWindowFrameFn](symAddr(handle, "setWGPUViewFrame"))
  if syms.setWGPUViewFrame.isNil: return some("setWGPUViewFrame")
  syms.resizeWGPUView = cast[ResizeViewFn](symAddr(handle, "resizeWGPUView"))
  if syms.resizeWGPUView.isNil: return some("resizeWGPUView")
  syms.setWGPUViewTransparent = cast[SetWindowBoolFn](symAddr(handle, "setWGPUViewTransparent"))
  if syms.setWGPUViewTransparent.isNil: return some("setWGPUViewTransparent")
  syms.setWGPUViewPassthrough = cast[SetWindowBoolFn](symAddr(handle, "setWGPUViewPassthrough"))
  if syms.setWGPUViewPassthrough.isNil: return some("setWGPUViewPassthrough")
  syms.setWGPUViewHidden = cast[SetWindowBoolFn](symAddr(handle, "setWGPUViewHidden"))
  if syms.setWGPUViewHidden.isNil: return some("setWGPUViewHidden")
  syms.removeWGPUView = cast[WindowIdFn](symAddr(handle, "removeWGPUView"))
  if syms.removeWGPUView.isNil: return some("removeWGPUView")
  syms.getWGPUViewPointer = cast[GetViewPointerFn](symAddr(handle, "getWGPUViewPointer"))
  if syms.getWGPUViewPointer.isNil: return some("getWGPUViewPointer")
  syms.getWGPUViewNativeHandle = cast[GetViewPointerFn](symAddr(handle, "getWGPUViewNativeHandle"))
  if syms.getWGPUViewNativeHandle.isNil: return some("getWGPUViewNativeHandle")
  syms.runWGPUViewTest = cast[WindowIdFn](symAddr(handle, "runWGPUViewTest"))
  if syms.runWGPUViewTest.isNil: return some("runWGPUViewTest")
  syms.toggleWGPUViewTestShader = cast[WindowIdFn](symAddr(handle, "toggleWGPUViewTestShader"))
  if syms.toggleWGPUViewTestShader.isNil: return some("toggleWGPUViewTestShader")
  syms.evaluateJavaScriptWithNoCompletion = cast[IdCstringFn](symAddr(handle, "evaluateJavaScriptWithNoCompletion"))
  if syms.evaluateJavaScriptWithNoCompletion.isNil: return some("evaluateJavaScriptWithNoCompletion")
  syms.createTray = cast[CreateTrayFn](symAddr(handle, "createTray"))
  if syms.createTray.isNil: return some("createTray")
  syms.showTray = cast[WindowIdBoolFn](symAddr(handle, "showTray"))
  if syms.showTray.isNil: return some("showTray")
  syms.hideTray = cast[WindowIdFn](symAddr(handle, "hideTray"))
  if syms.hideTray.isNil: return some("hideTray")
  syms.setTrayTitle = cast[IdCstringFn](symAddr(handle, "setTrayTitle"))
  if syms.setTrayTitle.isNil: return some("setTrayTitle")
  syms.removeTray = cast[WindowIdFn](symAddr(handle, "removeTray"))
  if syms.removeTray.isNil: return some("removeTray")
  syms.getTrayBounds = cast[GetTrayBoundsFn](symAddr(handle, "getTrayBounds"))
  if syms.getTrayBounds.isNil: return some("getTrayBounds")
  syms.setDockIconVisible = cast[SetBoolFn](symAddr(handle, "setDockIconVisible"))
  if syms.setDockIconVisible.isNil: return some("setDockIconVisible")
  syms.isDockIconVisible = cast[GetBoolFn](symAddr(handle, "isDockIconVisible"))
  if syms.isDockIconVisible.isNil: return some("isDockIconVisible")
  syms.getPrimaryDisplay = cast[GetCstringFn](symAddr(handle, "getPrimaryDisplay"))
  if syms.getPrimaryDisplay.isNil: return some("getPrimaryDisplay")
  syms.getAllDisplays = cast[GetCstringFn](symAddr(handle, "getAllDisplays"))
  if syms.getAllDisplays.isNil: return some("getAllDisplays")
  syms.getCursorScreenPoint = cast[GetCstringFn](symAddr(handle, "getCursorScreenPoint"))
  if syms.getCursorScreenPoint.isNil: return some("getCursorScreenPoint")
  syms.captureScreenRegion = cast[CaptureScreenRegionFn](symAddr(handle, "captureScreenRegion"))
  if syms.captureScreenRegion.isNil: return some("captureScreenRegion")
  syms.moveToTrash = cast[CstringToBoolFn](symAddr(handle, "moveToTrash"))
  if syms.moveToTrash.isNil: return some("moveToTrash")
  syms.showItemInFolder = cast[CstringVoidFn](symAddr(handle, "showItemInFolder"))
  if syms.showItemInFolder.isNil: return some("showItemInFolder")
  syms.openExternal = cast[CstringToBoolFn](symAddr(handle, "openExternal"))
  if syms.openExternal.isNil: return some("openExternal")
  syms.openPath = cast[CstringToBoolFn](symAddr(handle, "openPath"))
  if syms.openPath.isNil: return some("openPath")
  syms.showNotification = cast[ShowNotificationFn](symAddr(handle, "showNotification"))
  if syms.showNotification.isNil: return some("showNotification")
  syms.clipboardReadText = cast[GetCstringFn](symAddr(handle, "clipboardReadText"))
  if syms.clipboardReadText.isNil: return some("clipboardReadText")
  syms.clipboardWriteText = cast[CstringVoidFn](symAddr(handle, "clipboardWriteText"))
  if syms.clipboardWriteText.isNil: return some("clipboardWriteText")
  syms.clipboardClear = cast[VoidFn](symAddr(handle, "clipboardClear"))
  if syms.clipboardClear.isNil: return some("clipboardClear")
  syms.clipboardAvailableFormats = cast[GetCstringFn](symAddr(handle, "clipboardAvailableFormats"))
  if syms.clipboardAvailableFormats.isNil: return some("clipboardAvailableFormats")
  syms.setApplicationMenu = cast[SetMenuFn](symAddr(handle, "setApplicationMenu"))
  if syms.setApplicationMenu.isNil: return some("setApplicationMenu")
  syms.showContextMenu = cast[SetMenuFn](symAddr(handle, "showContextMenu"))
  if syms.showContextMenu.isNil: return some("showContextMenu")
  syms.openFileDialog = cast[OpenFileDialogFn](symAddr(handle, "openFileDialog"))
  if syms.openFileDialog.isNil: return some("openFileDialog")
  syms.showMessageBox = cast[ShowMessageBoxFn](symAddr(handle, "showMessageBox"))
  if syms.showMessageBox.isNil: return some("showMessageBox")
  syms.setGlobalShortcutCallback = cast[SetGlobalShortcutCallbackFn](symAddr(handle, "setGlobalShortcutCallback"))
  if syms.setGlobalShortcutCallback.isNil: return some("setGlobalShortcutCallback")
  syms.registerGlobalShortcut = cast[CstringToBoolFn](symAddr(handle, "registerGlobalShortcut"))
  if syms.registerGlobalShortcut.isNil: return some("registerGlobalShortcut")
  syms.unregisterGlobalShortcut = cast[CstringToBoolFn](symAddr(handle, "unregisterGlobalShortcut"))
  if syms.unregisterGlobalShortcut.isNil: return some("unregisterGlobalShortcut")
  syms.unregisterAllGlobalShortcuts = cast[VoidFn](symAddr(handle, "unregisterAllGlobalShortcuts"))
  if syms.unregisterAllGlobalShortcuts.isNil: return some("unregisterAllGlobalShortcuts")
  syms.isGlobalShortcutRegistered = cast[CstringToBoolFn](symAddr(handle, "isGlobalShortcutRegistered"))
  if syms.isGlobalShortcutRegistered.isNil: return some("isGlobalShortcutRegistered")
  syms.sessionGetCookies = cast[SessionGetCookiesFn](symAddr(handle, "sessionGetCookies"))
  if syms.sessionGetCookies.isNil: return some("sessionGetCookies")
  syms.sessionSetCookie = cast[SessionSetCookieFn](symAddr(handle, "sessionSetCookie"))
  if syms.sessionSetCookie.isNil: return some("sessionSetCookie")
  syms.sessionRemoveCookie = cast[SessionRemoveCookieFn](symAddr(handle, "sessionRemoveCookie"))
  if syms.sessionRemoveCookie.isNil: return some("sessionRemoveCookie")
  syms.sessionClearCookies = cast[CstringVoidFn](symAddr(handle, "sessionClearCookies"))
  if syms.sessionClearCookies.isNil: return some("sessionClearCookies")
  syms.sessionClearStorageData = cast[SessionClearStorageDataFn](symAddr(handle, "sessionClearStorageData"))
  if syms.sessionClearStorageData.isNil: return some("sessionClearStorageData")
  syms.setURLOpenHandler = cast[SetURLOpenHandlerFn](symAddr(handle, "setURLOpenHandler"))
  if syms.setURLOpenHandler.isNil: return some("setURLOpenHandler")
  syms.setAppReopenHandler = cast[SetAppReopenHandlerFn](symAddr(handle, "setAppReopenHandler"))
  if syms.setAppReopenHandler.isNil: return some("setAppReopenHandler")
  syms.setQuitRequestedHandler = cast[SetQuitRequestedHandlerFn](symAddr(handle, "setQuitRequestedHandler"))
  if syms.setQuitRequestedHandler.isNil: return some("setQuitRequestedHandler")
  syms.setExitOnLastWindowClosed = cast[SetBoolFn](symAddr(handle, "setExitOnLastWindowClosed"))
  if syms.setExitOnLastWindowClosed.isNil: return some("setExitOnLastWindowClosed")
  syms.stopEventLoop = cast[VoidFn](symAddr(handle, "stopEventLoop"))
  if syms.stopEventLoop.isNil: return some("stopEventLoop")
  syms.waitForShutdownComplete = cast[IntVoidFn](symAddr(handle, "waitForShutdownComplete"))
  if syms.waitForShutdownComplete.isNil: return some("waitForShutdownComplete")
  syms.forceExit = cast[IntVoidFn](symAddr(handle, "forceExit"))
  if syms.forceExit.isNil: return some("forceExit")
  syms.quitGracefully = cast[QuitGracefullyFn](symAddr(handle, "quitGracefully"))
  if syms.quitGracefully.isNil: return some("quitGracefully")
  syms.wgpuCreateSurfaceForView = cast[WgpuCreateSurfaceForViewFn](symAddr(handle, "wgpuCreateSurfaceForView"))
  if syms.wgpuCreateSurfaceForView.isNil: return some("wgpuCreateSurfaceForView")
  syms.wgpuCreateAdapterDeviceMainThread = cast[WgpuThreePtrVoidFn](symAddr(handle, "wgpuCreateAdapterDeviceMainThread"))
  if syms.wgpuCreateAdapterDeviceMainThread.isNil: return some("wgpuCreateAdapterDeviceMainThread")
  syms.wgpuSurfaceConfigureMainThread = cast[WgpuTwoPtrVoidFn](symAddr(handle, "wgpuSurfaceConfigureMainThread"))
  if syms.wgpuSurfaceConfigureMainThread.isNil: return some("wgpuSurfaceConfigureMainThread")
  syms.wgpuSurfaceGetCurrentTextureMainThread = cast[WgpuTwoPtrVoidFn](symAddr(handle, "wgpuSurfaceGetCurrentTextureMainThread"))
  if syms.wgpuSurfaceGetCurrentTextureMainThread.isNil: return some("wgpuSurfaceGetCurrentTextureMainThread")
  syms.wgpuSurfacePresentMainThread = cast[WgpuPresentFn](symAddr(handle, "wgpuSurfacePresentMainThread"))
  if syms.wgpuSurfacePresentMainThread.isNil: return some("wgpuSurfacePresentMainThread")
  return none(string)

type
  Renderer* = enum
    rNative
    rCef

proc rendererName*(renderer: Renderer): string =
  case renderer
  of rNative: "native"
  of rCef: "cef"

type
  AppInfo* = object
    identifier*: string
    name*: string
    channel*: string

  OwnedAppInfo* = object
    identifier*: string
    name*: string
    channel*: string

proc borrowed*(self: OwnedAppInfo): AppInfo =
  AppInfo(identifier: self.identifier, name: self.name, channel: self.channel)

proc deinit*(self: var OwnedAppInfo) =
  discard

proc appInfoIsPackaged*(appInfo: AppInfo): bool =
  appInfo.channel == "stable" or appInfo.channel == "canary"

type
  Rect* = object
    x*, y*, width*, height*: float64

const DEFAULT_RECT* = Rect(x: 0, y: 0, width: 800, height: 600)

type
  TrafficLightOffset* = object
    x*, y*: float64

  WindowStyle* = object
    borderless*, titled*, closable*, miniaturizable*, resizable*: bool
    unifiedTitleAndToolbar*, fullScreen*, fullSizeContentView*: bool
    utilityWindow*, docModalWindow*, nonactivatingPanel*, hudWindow*: bool

const DEFAULT_WINDOW_STYLE* = WindowStyle(
  titled: true, closable: true, miniaturizable: true, resizable: true)

type
  WindowCallbacks* = object
    close*: WindowCloseHandler
    shouldClose*: WindowShouldCloseHandler
    move*: WindowMoveHandler
    resize*: WindowResizeHandler
    focus*: WindowFocusHandler
    blur*: WindowBlurHandler
    key*: WindowKeyHandler

  WindowOptions* = object
    title*: string
    frame*: Rect
    style*: WindowStyle
    titleBarStyle*: string
    transparent*, hidden*, activate*, centered*: bool
    trafficLightOffset*: TrafficLightOffset
    callbacks*: WindowCallbacks

proc defaultWindowOptions*(title: string): WindowOptions =
  WindowOptions(title: title, frame: DEFAULT_RECT, style: DEFAULT_WINDOW_STYLE,
    titleBarStyle: "default", activate: true, centered: false)

type
  WebviewCallbacks* = object
    decideNavigation*: DecideNavigationHandler
    event*: WebviewEventHandler
    eventBridge*, hostBridge*, bunBridge*, internalBridge*: WebviewPostMessageHandler

  AllowedProtocols* = object
    views*, appData*: bool

  WebviewOptions* = object
    windowId*, hostWebviewId*: uint32
    renderer*: Renderer
    url*: string
    frame*: Rect
    autoResize*: bool
    partition*: string
    callbacks*: WebviewCallbacks
    secretKey*, preload*, viewsRoot*: string
    allowedProtocols*: AllowedProtocols
    sandbox*, startTransparent*, startPassthrough*, spellCheck*: bool

proc defaultWebviewOptions*(windowId: uint32): WebviewOptions =
  WebviewOptions(windowId: windowId, renderer: rNative, frame: DEFAULT_RECT,
    autoResize: true, partition: "persist:default",
    allowedProtocols: AllowedProtocols(views: true), sandbox: true)

type
  WGPUViewOptions* = object
    windowId*: uint32
    frame*: Rect
    autoResize*, startTransparent*, startPassthrough*: bool

proc defaultWGPUViewOptions*(windowId: uint32): WGPUViewOptions =
  WGPUViewOptions(windowId: windowId, frame: DEFAULT_RECT, autoResize: true)

type
  TrayOptions* = object
    title*, image*: string
    isTemplate*: bool
    width*, height*: uint32

proc defaultTrayOptions*(image: string): TrayOptions =
  TrayOptions(image: image, width: 18, height: 18)

type
  Display* = object
    id*: int64
    bounds*, workArea*: Rect
    scaleFactor*: float64
    isPrimary*: bool

  Point* = object
    x*, y*: float64

  NotificationOptions* = object
    title*, body*, subtitle*: string
    silent*: bool

  Cookie* = object
    name*, value*: string
    domain*, path*, sameSite*: Option[string]
    secure*, httpOnly*: Option[bool]
    expirationDate*: Option[float64]

  CookieFilter* = object
    url*, name*, domain*, path*: Option[string]
    secure*, session*: Option[bool]

  StorageType* = enum
    stCookies, stLocalStorage, stSessionStorage, stIndexedDB, stWebSQL, stCache, stAll

const STORAGE_TYPE_NAMES* = [
  "cookies", "localStorage", "sessionStorage", "indexedDB", "webSQL", "cache", "all"
]

type
  OpenFileDialogOptions* = object
    startingFolder*, allowedFileTypes*: string
    canChooseFiles*, canChooseDirectory*, allowsMultipleSelection*: bool

proc defaultOpenFileDialogOptions*(): OpenFileDialogOptions =
  OpenFileDialogOptions(startingFolder: "~/", allowedFileTypes: "*",
    canChooseFiles: true, canChooseDirectory: true, allowsMultipleSelection: true)

const DEFAULT_MESSAGE_BOX_BUTTONS* = @["OK"]

type
  MessageBoxOptions* = object
    boxType*, title*, message*, detail*: string
    buttons*: seq[string]
    defaultId*, cancelId*: cint

proc defaultMessageBoxOptions*(): MessageBoxOptions =
  MessageBoxOptions(boxType: "info", buttons: @["OK"], defaultId: 0, cancelId: -1)

type
  Paths* = object
    home*, appData*, config*, cache*, temp*, logs*: string
    documents*, downloads*, desktop*, pictures*, music*, videos*: string
    userData*, userCache*, userLogs*: string

type
  BundlePaths* = object
    exeDir*, resourcesDir*: string

type
  Core* = object
    symbols*: Symbols

type
  BrowserWindowRef* = object
    registry*: ptr WindowRegistry
    id*: uint32

  WindowRegistry* = object
    core*: ptr Core
    ids*: HashSet[uint32]

  SessionPartition* = object
    core*: ptr Core
    partition*: string

type
  WgpuAdapterDevice* = object
    adapter*, device*: pointer

  WgpuSymbols* = object
    handle: LibHandle
    wgpuCreateInstance: WgpuCreateInstanceFn
    wgpuDeviceGetQueue: WgpuDeviceGetQueueFn

  WgpuNative* = object
    symbols*: WgpuSymbols

  WgpuContext* = object
    viewPtr*, instancePtr*, surfacePtr*, adapterPtr*, devicePtr*: pointer

when defined(windows):
  const CORE_LIB_NAME* = "ElectrobunCore.dll"
  const WGPU_LIB_NAME* = "webgpu_dawn.dll"
elif defined(macosx):
  const CORE_LIB_NAME* = "libElectrobunCore.dylib"
  const WGPU_LIB_NAME* = "libwebgpu_dawn.dylib"
else:
  const CORE_LIB_NAME* = "libElectrobunCore.so"
  const WGPU_LIB_NAME* = "libwebgpu_dawn.so"

type ScreenCaptureLayout = object
  x, y: float64
  width, height: uint32
  byteLen: int
  byteLenU64: uint64

proc invalidCaptureFloat(v: float64): bool =
  v.isNaN or v == Inf or v == NegInf

proc screenCaptureLayout(rectangle: Rect): (ScreenCaptureLayout, EbError) =
  if invalidCaptureFloat(rectangle.x) or invalidCaptureFloat(rectangle.y) or
     invalidCaptureFloat(rectangle.width) or invalidCaptureFloat(rectangle.height):
    return (default(ScreenCaptureLayout), ebInvalidScreenCaptureRegion)
  let maxDimension = float64(high uint32)
  if rectangle.width <= 0 or rectangle.height <= 0 or
     rectangle.width != floor(rectangle.width) or rectangle.height != floor(rectangle.height) or
     rectangle.width > maxDimension or rectangle.height > maxDimension:
    return (default(ScreenCaptureLayout), ebInvalidScreenCaptureRegion)
  let width = uint32(rectangle.width)
  let height = uint32(rectangle.height)
  let pixelCount = uint64(width) * uint64(height)
  if pixelCount > uint64(high int) div 4:
    return (default(ScreenCaptureLayout), ebInvalidScreenCaptureRegion)
  let byteLenU64 = pixelCount * 4
  result[0] = ScreenCaptureLayout(
    x: floor(rectangle.x), y: floor(rectangle.y),
    width: width, height: height,
    byteLen: int(byteLenU64), byteLenU64: byteLenU64)
  result[1] = ebNone

proc dupZ(s: string): cstring =
  ## Always a non-nil 0-terminated buffer. Native wrappers `strdup` these
  ## pointers and crash on NULL; Zig/Odin already pass empty sentinels.
  result = cast[cstring](allocShared0((s.len + 1).csize_t))
  if s.len > 0:
    copyMem(result, unsafeAddr(s[0]), s.len)

proc zfree(z: cstring) =
  if not z.isNil:
    deallocShared(z)

macro withZ*(s: string, name: untyped, body: untyped): untyped =
  quote do:
    block:
      let `name` = dupZ(`s`)
      defer: zfree(`name`)
      `body`

proc cloneString*(value: string): string =
  value

proc joinPath*(parts: openArray[string]): string =
  result = ""
  for i, p in parts:
    if i == 0: result = p
    else: result = joinPath(result, p)

proc lastErrorString*(self: Core): string =
  if self.symbols.electrobun_core_last_error.isNil:
    return ""
  $self.symbols.electrobun_core_last_error()

proc errorFromLastError*(message: string): EbError =
  if message.len != 0:
    stderr.writeLine("[electrobun-nim] core error: ", message)
  ebElectrobunCoreFailure

proc ensureLastCallSucceeded*(self: Core): EbError =
  let message = self.lastErrorString()
  if message.len != 0:
    return errorFromLastError(message)
  ebNone

proc resolveBundlePaths*(): (BundlePaths, EbError) =
  let exePath = expandFilename(paramStr(0))
  let (head, _) = splitPath(exePath)
  if head.len == 0:
    return (default(BundlePaths), ebInvalidExePath)
  result[0] = BundlePaths(exeDir: head, resourcesDir: joinPath(head, "..", "Resources"))
  result[1] = ebNone

proc deinit*(self: var BundlePaths) = discard
proc deinit*(self: var Paths) = discard

proc objectString(obj: JsonNode; key: string): Option[string] =
  if key notin obj: return none(string)
  if obj[key].kind == JString: some(obj[key].getStr)
  else: none(string)

proc objectNumber(obj: JsonNode; key: string): Option[float64] =
  if key notin obj: return none(float64)
  case obj[key].kind
  of JInt: some(float64(obj[key].getInt))
  of JFloat: some(obj[key].getFloat)
  else: none(float64)

proc objectBool(obj: JsonNode; key: string): Option[bool] =
  if key notin obj: return none(bool)
  if obj[key].kind == JBool: some(obj[key].getBool)
  else: none(bool)

proc rectFromValue(value: JsonNode): Option[Rect] =
  if value.kind != JObject: return none(Rect)
  let x = objectNumber(value, "x")
  let y = objectNumber(value, "y")
  let w = objectNumber(value, "width")
  let h = objectNumber(value, "height")
  if x.isNone or y.isNone or w.isNone or h.isNone: return none(Rect)
  some(Rect(x: x.get, y: y.get, width: w.get, height: h.get))

proc parseRectJson*(text: string): (Rect, EbError) =
  try:
    let value = parseJson(text)
    let r = rectFromValue(value)
    if r.isSome: return (r.get, ebNone)
  except CatchableError:
    discard
  (default(Rect), ebInvalidRectJson)

proc displayFromValue(value: JsonNode): Option[Display] =
  if value.kind != JObject: return none(Display)
  let id = objectNumber(value, "id")
  if id.isNone: return none(Display)
  let bounds = rectFromValue(if "bounds" in value: value["bounds"] else: newJNull())
  let workArea = rectFromValue(if "workArea" in value: value["workArea"] else: newJNull())
  if bounds.isNone or workArea.isNone: return none(Display)
  let scaleFactor = objectNumber(value, "scaleFactor").get(1.0)
  let isPrimary = objectBool(value, "isPrimary").get(false)
  some(Display(id: int64(id.get), bounds: bounds.get, workArea: workArea.get,
    scaleFactor: scaleFactor, isPrimary: isPrimary))

proc parseDisplayJson*(text: string): (Display, EbError) =
  try:
    let value = parseJson(text)
    let d = displayFromValue(value)
    if d.isSome: return (d.get, ebNone)
  except CatchableError:
    discard
  (default(Display), ebInvalidJson)

proc parseDisplaysJson*(text: string): (seq[Display], EbError) =
  try:
    let value = parseJson(text)
    if value.kind != JArray: return (@[], ebInvalidJson)
    var parsed: seq[Display]
    for item in value:
      let d = displayFromValue(item)
      if d.isSome: parsed.add d.get
      else: return (@[], ebInvalidJson)
    return (parsed, ebNone)
  except CatchableError:
    discard
  (@[], ebInvalidJson)

proc parsePointJson*(text: string): (Point, EbError) =
  try:
    let value = parseJson(text)
    if value.kind != JObject: return (default(Point), ebInvalidJson)
    let x = objectNumber(value, "x")
    let y = objectNumber(value, "y")
    if x.isNone or y.isNone: return (default(Point), ebInvalidJson)
    return (Point(x: x.get, y: y.get), ebNone)
  except CatchableError:
    discard
  (default(Point), ebInvalidJson)

proc parseDialogPathsJson*(text: string): (seq[string], EbError) =
  try:
    let value = parseJson(text)
    if value.kind != JArray: return (@[], ebInvalidJson)
    var parsed: seq[string]
    for item in value:
      if item.kind != JString: return (@[], ebInvalidJson)
      parsed.add item.getStr
    return (parsed, ebNone)
  except CatchableError:
    discard
  (@[], ebInvalidJson)

proc cookieFromObject(obj: JsonNode): Cookie =
  result = Cookie()
  block:
    let v = objectString(obj, "name")
    if v.isSome: result.name = v.get
  block:
    let v = objectString(obj, "value")
    if v.isSome: result.value = v.get
  result.domain = objectString(obj, "domain")
  result.path = objectString(obj, "path")
  result.secure = objectBool(obj, "secure")
  result.httpOnly = objectBool(obj, "httpOnly")
  result.sameSite = objectString(obj, "sameSite")
  result.expirationDate = objectNumber(obj, "expirationDate")

proc parseCookiesJson*(text: string): (seq[Cookie], EbError) =
  try:
    let value = parseJson(text)
    if value.kind != JArray: return (@[], ebInvalidJson)
    var parsed: seq[Cookie]
    for item in value:
      if item.kind == JObject: parsed.add cookieFromObject(item)
    return (parsed, ebNone)
  except CatchableError:
    discard
  (@[], ebInvalidJson)

proc writeJsonString(b: var string; value: string) =
  b.add $(%value)

proc writeOptString(b: var string; value: Option[string]) =
  if value.isSome: writeJsonString(b, value.get)
  else: b.add "null"

proc writeOptBool(b: var string; value: Option[bool]) =
  if value.isSome: b.add(if value.get: "true" else: "false")
  else: b.add "null"

proc writeOptF64(b: var string; value: Option[float64]) =
  if value.isSome: b.add $value.get
  else: b.add "null"

proc marshalCookie*(cookie: Cookie): string =
  var b = ""
  b.add "{\"name\":"
  writeJsonString(b, cookie.name)
  b.add ",\"value\":"
  writeJsonString(b, cookie.value)
  b.add ",\"domain\":"
  writeOptString(b, cookie.domain)
  b.add ",\"path\":"
  writeOptString(b, cookie.path)
  b.add ",\"secure\":"
  writeOptBool(b, cookie.secure)
  b.add ",\"httpOnly\":"
  writeOptBool(b, cookie.httpOnly)
  b.add ",\"sameSite\":"
  writeOptString(b, cookie.sameSite)
  b.add ",\"expirationDate\":"
  writeOptF64(b, cookie.expirationDate)
  b.add "}"
  b

proc marshalCookieFilter*(filter: CookieFilter): string =
  var b = ""
  b.add "{\"url\":"
  writeOptString(b, filter.url)
  b.add ",\"name\":"
  writeOptString(b, filter.name)
  b.add ",\"domain\":"
  writeOptString(b, filter.domain)
  b.add ",\"path\":"
  writeOptString(b, filter.path)
  b.add ",\"secure\":"
  writeOptBool(b, filter.secure)
  b.add ",\"session\":"
  writeOptBool(b, filter.session)
  b.add "}"
  b

proc resolveAppInfoFromBundle*(bundlePaths: BundlePaths): (OwnedAppInfo, EbError) =
  let versionJsonPath = joinPath(bundlePaths.resourcesDir, "version.json")
  if not fileExists(versionJsonPath):
    return (default(OwnedAppInfo), ebFileReadFailed)
  let versionJson = readFile(versionJsonPath)
  try:
    let root = parseJson(versionJson)
    if root.kind != JObject: return (default(OwnedAppInfo), ebInvalidJson)
    let identifier = objectString(root, "identifier")
    let name = objectString(root, "name")
    let channel = objectString(root, "channel")
    if identifier.isNone or name.isNone or channel.isNone:
      return (default(OwnedAppInfo), ebInvalidJson)
    return (OwnedAppInfo(identifier: identifier.get, name: name.get, channel: channel.get), ebNone)
  except CatchableError:
    return (default(OwnedAppInfo), ebInvalidJson)

proc exitOnLastWindowClosedFromBuildConfig*(bundlePaths: BundlePaths): bool =
  let buildJsonPath = joinPath(bundlePaths.resourcesDir, "build.json")
  if not fileExists(buildJsonPath):
    return true
  try:
    let root = parseJson(readFile(buildJsonPath))
    if root.kind != JObject: return true
    if "runtime" notin root: return true
    let runtime = root["runtime"]
    if runtime.kind != JObject: return true
    if "exitOnLastWindowClosed" notin runtime: return true
    if runtime["exitOnLastWindowClosed"].kind != JBool: return true
    return runtime["exitOnLastWindowClosed"].getBool
  except CatchableError:
    true

proc isSafeInstallRootName(value: string): bool =
  if value.len == 0 or value.len > 256 or value == "." or value == "..":
    return false
  for ch in value:
    let b = ord(ch)
    if b < 0x20 or b == 0x7f or ch == '/' or ch == '\\':
      return false
  when defined(windows):
    if value[^1] == ' ' or value[^1] == '.': return false
    for invalid in "\"%*:<>?|":
      if invalid in value: return false
  true

proc effectiveInstallRootName(fallback: string): string =
  let candidate = getEnv(INSTALL_ROOT_NAME_ENVIRONMENT_VARIABLE, "")
  if candidate.len > 0 and isSafeInstallRootName(candidate):
    candidate
  else:
    fallback

proc getHomeDir*(): (string, EbError) =
  when defined(windows):
    let v = getEnv("USERPROFILE", "")
    if v.len > 0: return (v, ebNone)
  let home = getEnv("HOME", "")
  if home.len > 0: return (home, ebNone)
  ("", ebEnvVarNotFound)

proc envOrJoin(envName: string; fallbackParts: openArray[string]): string =
  let v = getEnv(envName, "")
  if v.len > 0: v else: joinPath(fallbackParts)

proc getAppDataDir(home: string): string =
  when defined(macosx):
    joinPath(home, "Library", "Application Support")
  elif defined(windows):
    envOrJoin("LOCALAPPDATA", [home, "AppData", "Local"])
  else:
    envOrJoin("XDG_DATA_HOME", [home, ".local", "share"])

proc getCacheDir(home: string): string =
  when defined(macosx):
    joinPath(home, "Library", "Caches")
  elif defined(windows):
    envOrJoin("LOCALAPPDATA", [home, "AppData", "Local"])
  else:
    envOrJoin("XDG_CACHE_HOME", [home, ".cache"])

proc getLogsDir(home: string): string =
  when defined(macosx):
    joinPath(home, "Library", "Logs")
  elif defined(windows):
    envOrJoin("LOCALAPPDATA", [home, "AppData", "Local"])
  else:
    envOrJoin("XDG_STATE_HOME", [home, ".local", "state"])

proc getConfigDir(home: string): string =
  when defined(macosx):
    joinPath(home, "Library", "Application Support")
  elif defined(windows):
    envOrJoin("APPDATA", [home, "AppData", "Roaming"])
  else:
    envOrJoin("XDG_CONFIG_HOME", [home, ".config"])

proc getTempDir(home: string): string =
  when defined(windows):
    block:
      let v = getEnv("TEMP", "")
      if v.len > 0: return v
      let t = getEnv("TMP", "")
      if t.len > 0: return t
      return joinPath(home, "AppData", "Local", "Temp")
  else:
    let v = getEnv("TMPDIR", "")
    if v.len > 0: v else: "/tmp"

proc linuxXdgUserDir(home, key, fallbackName: string): string =
  let configPath = joinPath(home, ".config", "user-dirs.dirs")
  let fallback = joinPath(home, fallbackName)
  if not fileExists(configPath): return fallback
  for line in lines(configPath):
    var trimmed = line.strip(chars={' ', '\t', '\r'})
    if trimmed.len == 0 or trimmed[0] == '#': continue
    let eq = trimmed.find('=')
    if eq < 0: continue
    if trimmed[0..<eq] != key: continue
    var value = trimmed[eq + 1 .. ^1].strip(chars={' ', '\t', '\r'})
    if value.len >= 2 and value[0] == '"' and value[^1] == '"':
      value = value[1 .. ^2]
    return value.replace("$HOME", home)
  fallback

proc getUserDir(home, macName, winName, xdgKey, fallbackName: string): string =
  when defined(macosx):
    joinPath(home, macName)
  elif defined(windows):
    joinPath(home, winName)
  else:
    linuxXdgUserDir(home, xdgKey, fallbackName)

proc buildAppScopedDir(base: string; appInfo: AppInfo): string =
  if appInfo.identifier.len == 0 or appInfo.channel.len == 0:
    base
  else:
    joinPath(base, appInfo.identifier, effectiveInstallRootName(appInfo.channel))

proc resolvePaths*(appInfo: AppInfo): (Paths, EbError) =
  let (home, err) = getHomeDir()
  if err != ebNone: return (default(Paths), err)
  var paths = Paths(
    home: home,
    appData: getAppDataDir(home),
    config: getConfigDir(home),
    cache: getCacheDir(home),
    temp: getTempDir(home),
    logs: getLogsDir(home),
    documents: getUserDir(home, "Documents", "Documents", "XDG_DOCUMENTS_DIR", "Documents"),
    downloads: getUserDir(home, "Downloads", "Downloads", "XDG_DOWNLOAD_DIR", "Downloads"),
    desktop: getUserDir(home, "Desktop", "Desktop", "XDG_DESKTOP_DIR", "Desktop"),
    pictures: getUserDir(home, "Pictures", "Pictures", "XDG_PICTURES_DIR", "Pictures"),
    music: getUserDir(home, "Music", "Music", "XDG_MUSIC_DIR", "Music"),
    videos: getUserDir(home, "Movies", "Videos", "XDG_VIDEOS_DIR", "Videos"),
  )
  paths.userData = buildAppScopedDir(paths.appData, appInfo)
  paths.userCache = buildAppScopedDir(paths.cache, appInfo)
  paths.userLogs = buildAppScopedDir(paths.logs, appInfo)
  (paths, ebNone)

proc loadWgpuSymbolsInto(handle: LibHandle; syms: var WgpuSymbols): Option[string] =
  syms.handle = handle
  syms.wgpuCreateInstance = cast[WgpuCreateInstanceFn](symAddr(handle, "wgpuCreateInstance"))
  if syms.wgpuCreateInstance.isNil: return some("wgpuCreateInstance")
  syms.wgpuDeviceGetQueue = cast[WgpuDeviceGetQueueFn](symAddr(handle, "wgpuDeviceGetQueue"))
  if syms.wgpuDeviceGetQueue.isNil: return some("wgpuDeviceGetQueue")
  none(string)

proc wgpuNativeLoad*(): (WgpuNative, EbError) =
  let (bundlePaths, bpErr) = resolveBundlePaths()
  if bpErr != ebNone: return (default(WgpuNative), bpErr)
  let libPath = joinPath(bundlePaths.exeDir, WGPU_LIB_NAME)
  let handle = loadLib(libPath, globalSymbols = false)
  if handle == nil:
    stderr.writeLine("[electrobun-nim] failed to load ", libPath)
    return (default(WgpuNative), ebLibraryLoadFailed)
  var native = WgpuNative()
  let missingWgpu = loadWgpuSymbolsInto(handle, native.symbols)
  if missingWgpu.isSome:
    stderr.writeLine("[electrobun-nim] missing wgpu symbol: ", missingWgpu.get)
    unloadLib(handle)
    return (default(WgpuNative), ebMissingCoreSymbol)
  (native, ebNone)

proc wgpuNativeClose*(self: var WgpuNative) =
  if self.symbols.handle != nil:
    unloadLib(self.symbols.handle)
    self.symbols.handle = nil

proc createInstance*(self: WgpuNative): pointer =
  self.symbols.wgpuCreateInstance(nil)

proc deviceGetQueue*(self: WgpuNative; device: pointer): pointer =
  self.symbols.wgpuDeviceGetQueue(device)

proc load*(): (Core, EbError) =
  let (bundlePaths, bpErr) = resolveBundlePaths()
  if bpErr != ebNone: return (default(Core), bpErr)
  let libPath = joinPath(bundlePaths.exeDir, CORE_LIB_NAME)
  let handle = loadLib(libPath, globalSymbols = false)
  if handle == nil:
    stderr.writeLine("[electrobun-nim] failed to load ", libPath)
    return (default(Core), ebLibraryLoadFailed)
  var core = Core()
  let missingCore = loadSymbolsInto(handle, core.symbols)
  if missingCore.isSome:
    stderr.writeLine("[electrobun-nim] missing core symbol: ", missingCore.get)
    unloadLib(handle)
    return (default(Core), ebMissingCoreSymbol)
  core.symbols.setExitOnLastWindowClosed(
    exitOnLastWindowClosedFromBuildConfig(bundlePaths))
  gQuitRequestedStopEventLoop = core.symbols.stopEventLoop
  gQuitRequestedUserHandler = nil
  core.symbols.setQuitRequestedHandler(quitRequestedTrampoline)
  (core, ebNone)

proc coreClose*(self: var Core) =
  if not self.symbols.setQuitRequestedHandler.isNil:
    self.symbols.setQuitRequestedHandler(nil)
  gQuitRequestedStopEventLoop = nil
  gQuitRequestedUserHandler = nil
  if self.symbols.handle != nil:
    unloadLib(self.symbols.handle)
    self.symbols.handle = nil

proc close*(self: var Core) = coreClose(self)
proc close*(self: var WgpuNative) = wgpuNativeClose(self)

proc readFileCstring(self: Core; path: string): (cstring, EbError) =
  if not fileExists(path): return (nil, ebFileReadFailed)
  let data = readFile(path)
  (dupZ(data), ebNone)

proc configureWebviewRuntimeFromExecutableDir*(
  self: Core; bundlePaths: BundlePaths; rpcPort: uint32): EbError =
  let fullPath = joinPath(bundlePaths.resourcesDir, "preload-full.js")
  let sandboxedPath = joinPath(bundlePaths.resourcesDir, "preload-sandboxed.js")
  let (fullPreload, fullErr) = self.readFileCstring(fullPath)
  if fullErr != ebNone: return fullErr
  defer: zfree(fullPreload)
  let (sandboxedPreload, sandErr) = self.readFileCstring(sandboxedPath)
  if sandErr != ebNone: return sandErr
  defer: zfree(sandboxedPreload)
  if not self.symbols.configureWebviewRuntime(rpcPort, fullPreload, sandboxedPreload):
    return errorFromLastError(self.lastErrorString())
  ebNone

proc defaultWindowStyle*(self: Core): uint32 =
  self.symbols.getWindowStyle(false, true, true, true, true, false, false, false, false, false, false, false)



proc createWindow*(self: Core; options: WindowOptions): (uint32, EbError) =
  withZ(options.title, titleZ):
    withZ(options.titleBarStyle, titleBarStyleZ):
      let styleMask = self.symbols.getWindowStyle(
        options.style.borderless, options.style.titled, options.style.closable,
        options.style.miniaturizable, options.style.resizable,
        options.style.unifiedTitleAndToolbar, options.style.fullScreen,
        options.style.fullSizeContentView, options.style.utilityWindow,
        options.style.docModalWindow, options.style.nonactivatingPanel,
        options.style.hudWindow)
      let windowId = self.symbols.createWindow(
        options.frame.x, options.frame.y, options.frame.width, options.frame.height,
        styleMask, titleBarStyleZ, options.transparent, titleZ,
        options.hidden, options.activate, options.centered,
        options.trafficLightOffset.x, options.trafficLightOffset.y,
        options.callbacks.close, options.callbacks.move, options.callbacks.resize,
        options.callbacks.focus, options.callbacks.blur, options.callbacks.key,
        options.callbacks.shouldClose)
      if windowId == 0:
        return (0'u32, errorFromLastError(self.lastErrorString()))
      (windowId, ebNone)

proc setWindowTitle*(self: Core; windowId: uint32; title: string): EbError =
  withZ(title, z): self.symbols.setWindowTitle(windowId, z)
  self.ensureLastCallSucceeded()

proc minimizeWindow*(self: Core; windowId: uint32): EbError =
  self.symbols.minimizeWindow(windowId); self.ensureLastCallSucceeded()

proc restoreWindow*(self: Core; windowId: uint32): EbError =
  self.symbols.restoreWindow(windowId); self.ensureLastCallSucceeded()

proc isWindowMinimized*(self: Core; windowId: uint32): bool =
  self.symbols.isWindowMinimized(windowId)

proc maximizeWindow*(self: Core; windowId: uint32): EbError =
  self.symbols.maximizeWindow(windowId); self.ensureLastCallSucceeded()

proc unmaximizeWindow*(self: Core; windowId: uint32): EbError =
  self.symbols.unmaximizeWindow(windowId); self.ensureLastCallSucceeded()

proc isWindowMaximized*(self: Core; windowId: uint32): bool =
  self.symbols.isWindowMaximized(windowId)

proc setWindowFullScreen*(self: Core; windowId: uint32; fullScreen: bool): EbError =
  self.symbols.setWindowFullScreen(windowId, fullScreen); self.ensureLastCallSucceeded()

proc isWindowFullScreen*(self: Core; windowId: uint32): bool =
  self.symbols.isWindowFullScreen(windowId)

proc setWindowAlwaysOnTop*(self: Core; windowId: uint32; alwaysOnTop: bool): EbError =
  self.symbols.setWindowAlwaysOnTop(windowId, alwaysOnTop); self.ensureLastCallSucceeded()

proc isWindowAlwaysOnTop*(self: Core; windowId: uint32): bool =
  self.symbols.isWindowAlwaysOnTop(windowId)

proc setWindowVisibleOnAllWorkspaces*(self: Core; windowId: uint32; visible: bool): EbError =
  self.symbols.setWindowVisibleOnAllWorkspaces(windowId, visible); self.ensureLastCallSucceeded()

proc isWindowVisibleOnAllWorkspaces*(self: Core; windowId: uint32): bool =
  self.symbols.isWindowVisibleOnAllWorkspaces(windowId)

proc showWindow*(self: Core; windowId: uint32; activate: bool): EbError =
  self.symbols.showWindow(windowId, activate); self.ensureLastCallSucceeded()

proc activateWindow*(self: Core; windowId: uint32): EbError =
  self.symbols.activateWindow(windowId); self.ensureLastCallSucceeded()

proc hideWindow*(self: Core; windowId: uint32): EbError =
  self.symbols.hideWindow(windowId); self.ensureLastCallSucceeded()

proc isWindowVisible*(self: Core; windowId: uint32): bool =
  self.symbols.isWindowVisible(windowId)

proc coreSetWindowButtonPosition*(self: Core; windowId: uint32; x, y: float64): EbError =
  self.symbols.setWindowButtonPosition(windowId, x, y); self.ensureLastCallSucceeded()

proc coreGetWindowButtonPosition*(self: Core; windowId: uint32): (Point, EbError) =
  var x, y: float64
  self.symbols.getWindowButtonPosition(windowId, addr x, addr y)
  let err = self.ensureLastCallSucceeded()
  if err != ebNone: return (default(Point), err)
  (Point(x: x, y: y), ebNone)

proc setWindowPosition*(self: Core; windowId: uint32; x, y: float64): EbError =
  self.symbols.setWindowPosition(windowId, x, y); self.ensureLastCallSucceeded()

proc centerWindow*(self: Core; windowId: uint32): EbError =
  self.symbols.centerWindow(windowId); self.ensureLastCallSucceeded()

proc setWindowSize*(self: Core; windowId: uint32; width, height: float64): EbError =
  self.symbols.setWindowSize(windowId, width, height); self.ensureLastCallSucceeded()

proc setWindowFrame*(self: Core; windowId: uint32; frame: Rect): EbError =
  self.symbols.setWindowFrame(windowId, frame.x, frame.y, frame.width, frame.height)
  self.ensureLastCallSucceeded()

proc getWindowFrame*(self: Core; windowId: uint32): (Rect, EbError) =
  var x, y, w, h: float64
  self.symbols.getWindowFrame(windowId, addr x, addr y, addr w, addr h)
  let err = self.ensureLastCallSucceeded()
  if err != ebNone: return (default(Rect), err)
  (Rect(x: x, y: y, width: w, height: h), ebNone)

proc closeWindow*(self: Core; windowId: uint32): EbError =
  self.symbols.closeWindow(windowId); self.ensureLastCallSucceeded()

proc requestWindowClose*(self: Core; windowId: uint32): EbError =
  self.symbols.requestWindowClose(windowId); self.ensureLastCallSucceeded()

proc createWebview*(self: Core; options: WebviewOptions): (uint32, EbError) =
  withZ(rendererName(options.renderer), rendererZ):
    withZ(options.url, urlZ):
      withZ(options.partition, partitionZ):
        withZ(options.secretKey, secretKeyZ):
          withZ(options.preload, preloadZ):
            withZ(options.viewsRoot, viewsRootZ):
              var hostBridge = options.callbacks.hostBridge
              if hostBridge.isNil:
                hostBridge = options.callbacks.bunBridge
              self.symbols.setNextWebviewAllowedProtocols(
                options.allowedProtocols.views, options.allowedProtocols.appData)
              let webviewId = self.symbols.createWebview(
                options.windowId, options.hostWebviewId, rendererZ, urlZ,
                options.frame.x, options.frame.y, options.frame.width, options.frame.height,
                options.autoResize, partitionZ,
                options.callbacks.decideNavigation, options.callbacks.event,
                options.callbacks.eventBridge, hostBridge, options.callbacks.internalBridge,
                secretKeyZ, preloadZ, viewsRootZ,
                options.sandbox, options.startTransparent, options.startPassthrough,
                options.spellCheck)
              if webviewId == 0:
                return (0'u32, errorFromLastError(self.lastErrorString()))
              (webviewId, ebNone)

proc resizeWebview*(self: Core; webviewId: uint32; frame: Rect; masksJson: string): EbError =
  withZ(masksJson, z):
    self.symbols.resizeWebview(webviewId, frame.x, frame.y, frame.width, frame.height, z)
  self.ensureLastCallSucceeded()

proc loadURLInWebview*(self: Core; webviewId: uint32; url: string): EbError =
  withZ(url, z): self.symbols.loadURLInWebView(webviewId, z)
  self.ensureLastCallSucceeded()

proc loadHTMLInWebview*(self: Core; webviewId: uint32; html: string): EbError =
  withZ(html, z): self.symbols.loadHTMLInWebView(webviewId, z)
  self.ensureLastCallSucceeded()

proc updatePreloadScriptToWebview*(
  self: Core; webviewId: uint32; scriptIdentifier, script: string; allFrames: bool): EbError =
  withZ(scriptIdentifier, idZ):
    withZ(script, scriptZ):
      self.symbols.updatePreloadScriptToWebView(webviewId, idZ, scriptZ, allFrames)
  self.ensureLastCallSucceeded()

proc canWebviewGoBack*(self: Core; webviewId: uint32): bool =
  self.symbols.webviewCanGoBack(webviewId)

proc canWebviewGoForward*(self: Core; webviewId: uint32): bool =
  self.symbols.webviewCanGoForward(webviewId)

proc webviewGoBack*(self: Core; webviewId: uint32): EbError =
  self.symbols.webviewGoBack(webviewId); self.ensureLastCallSucceeded()

proc webviewGoForward*(self: Core; webviewId: uint32): EbError =
  self.symbols.webviewGoForward(webviewId); self.ensureLastCallSucceeded()

proc reloadWebview*(self: Core; webviewId: uint32): EbError =
  self.symbols.webviewReload(webviewId); self.ensureLastCallSucceeded()

proc removeWebview*(self: Core; webviewId: uint32): EbError =
  self.symbols.webviewRemove(webviewId); self.ensureLastCallSucceeded()

proc setWebviewHTMLContent*(self: Core; webviewId: uint32; html: string): EbError =
  withZ(html, z): self.symbols.setWebviewHTMLContent(webviewId, z)
  self.ensureLastCallSucceeded()

proc setWebviewTransparent*(self: Core; webviewId: uint32; transparent: bool): EbError =
  self.symbols.webviewSetTransparent(webviewId, transparent); self.ensureLastCallSucceeded()

proc setWebviewPassthrough*(self: Core; webviewId: uint32; passthrough: bool): EbError =
  self.symbols.webviewSetPassthrough(webviewId, passthrough); self.ensureLastCallSucceeded()

proc setWebviewHidden*(self: Core; webviewId: uint32; hidden: bool): EbError =
  self.symbols.webviewSetHidden(webviewId, hidden); self.ensureLastCallSucceeded()

proc setWebviewSpellCheck*(self: Core; webviewId: uint32; enabled: bool): (bool, EbError) =
  let supported = self.symbols.webviewSetSpellCheck(webviewId, enabled)
  let err = self.ensureLastCallSucceeded()
  if err != ebNone: return (false, err)
  (supported, ebNone)

proc setWebviewNavigationRules*(self: Core; webviewId: uint32; rulesJson: string): EbError =
  withZ(rulesJson, z): self.symbols.setWebviewNavigationRules(webviewId, z)
  self.ensureLastCallSucceeded()

proc webviewFindInPage*(self: Core; webviewId: uint32; searchText: string; forward, matchCase: bool): EbError =
  withZ(searchText, z): self.symbols.webviewFindInPage(webviewId, z, forward, matchCase)
  self.ensureLastCallSucceeded()

proc webviewStopFind*(self: Core; webviewId: uint32): EbError =
  self.symbols.webviewStopFind(webviewId); self.ensureLastCallSucceeded()

proc openWebviewDevTools*(self: Core; webviewId: uint32): EbError =
  self.symbols.webviewOpenDevTools(webviewId); self.ensureLastCallSucceeded()

proc closeWebviewDevTools*(self: Core; webviewId: uint32): EbError =
  self.symbols.webviewCloseDevTools(webviewId); self.ensureLastCallSucceeded()

proc toggleWebviewDevTools*(self: Core; webviewId: uint32): EbError =
  self.symbols.webviewToggleDevTools(webviewId); self.ensureLastCallSucceeded()

proc setWebviewPageZoom*(self: Core; webviewId: uint32; zoomLevel: float64): EbError =
  self.symbols.webviewSetPageZoom(webviewId, zoomLevel); self.ensureLastCallSucceeded()

proc getWebviewPageZoom*(self: Core; webviewId: uint32): float64 =
  self.symbols.webviewGetPageZoom(webviewId)

proc createWGPUView*(self: Core; options: WGPUViewOptions): (uint32, EbError) =
  let wgpuViewId = self.symbols.createWGPUView(
    options.windowId, options.frame.x, options.frame.y,
    options.frame.width, options.frame.height,
    options.autoResize, options.startTransparent, options.startPassthrough)
  if wgpuViewId == 0:
    return (0'u32, errorFromLastError(self.lastErrorString()))
  (wgpuViewId, ebNone)

proc setWGPUViewFrame*(self: Core; wgpuViewId: uint32; frame: Rect): EbError =
  self.symbols.setWGPUViewFrame(wgpuViewId, frame.x, frame.y, frame.width, frame.height)
  self.ensureLastCallSucceeded()

proc resizeWGPUView*(self: Core; wgpuViewId: uint32; frame: Rect; masksJson: string): EbError =
  withZ(masksJson, z):
    self.symbols.resizeWGPUView(wgpuViewId, frame.x, frame.y, frame.width, frame.height, z)
  self.ensureLastCallSucceeded()

proc setWGPUViewTransparent*(self: Core; wgpuViewId: uint32; transparent: bool): EbError =
  self.symbols.setWGPUViewTransparent(wgpuViewId, transparent); self.ensureLastCallSucceeded()

proc setWGPUViewPassthrough*(self: Core; wgpuViewId: uint32; passthrough: bool): EbError =
  self.symbols.setWGPUViewPassthrough(wgpuViewId, passthrough); self.ensureLastCallSucceeded()

proc setWGPUViewHidden*(self: Core; wgpuViewId: uint32; hidden: bool): EbError =
  self.symbols.setWGPUViewHidden(wgpuViewId, hidden); self.ensureLastCallSucceeded()

proc removeWGPUView*(self: Core; wgpuViewId: uint32): EbError =
  self.symbols.removeWGPUView(wgpuViewId); self.ensureLastCallSucceeded()

proc getWGPUViewPointer*(self: Core; wgpuViewId: uint32): (pointer, EbError) =
  let handle = self.symbols.getWGPUViewPointer(wgpuViewId)
  let err = self.ensureLastCallSucceeded()
  if err != ebNone: return (nil, err)
  (handle, ebNone)

proc getWGPUViewNativeHandle*(self: Core; wgpuViewId: uint32): (pointer, EbError) =
  let handle = self.symbols.getWGPUViewNativeHandle(wgpuViewId)
  let err = self.ensureLastCallSucceeded()
  if err != ebNone: return (nil, err)
  (handle, ebNone)

proc runWGPUViewTest*(self: Core; wgpuViewId: uint32): EbError =
  self.symbols.runWGPUViewTest(wgpuViewId); self.ensureLastCallSucceeded()

proc toggleWGPUViewTestShader*(self: Core; wgpuViewId: uint32): EbError =
  self.symbols.toggleWGPUViewTestShader(wgpuViewId); self.ensureLastCallSucceeded()

proc evaluateJavaScriptWithNoCompletion*(self: Core; webviewId: uint32; js: string): EbError =
  withZ(js, z): self.symbols.evaluateJavaScriptWithNoCompletion(webviewId, z)
  self.ensureLastCallSucceeded()

proc sendHostMessageToWebviewJson*(self: Core; webviewId: uint32; message: JsonNode): EbError =
  let messageJson = $message
  withZ(messageJson, z):
    if self.symbols.sendHostMessageToWebviewViaTransport(webviewId, z):
      return ebNone
  let js = "window.__electrobun.receiveMessageFromHost(" & messageJson & ");"
  self.evaluateJavaScriptWithNoCompletion(webviewId, js)

proc sendHostMessageToWebview*[T](self: Core; webviewId: uint32; message: T): EbError =
  sendHostMessageToWebviewJson(self, webviewId, %message)

proc sendMessageToWebview*[T](self: Core; webviewId: uint32; message: T): EbError =
  sendHostMessageToWebview(self, webviewId, message)

proc popNextQueuedHostMessage*(self: Core; outWebviewId: var uint32): cstring =
  self.symbols.popNextQueuedHostMessage(addr outWebviewId)

proc freeCoreString*(self: Core; value: cstring) =
  self.symbols.freeCoreString(value)

proc sendInternalMessageToWebviewJson*(self: Core; webviewId: uint32; message: JsonNode): EbError =
  withZ($message, z):
    if not self.symbols.sendInternalMessageToWebview(webviewId, z):
      return errorFromLastError(self.lastErrorString())
  ebNone

proc sendInternalMessageToWebview*[T](self: Core; webviewId: uint32; message: T): EbError =
  sendInternalMessageToWebviewJson(self, webviewId, %message)

proc createTray*(self: Core; options: TrayOptions): (uint32, EbError) =
  withZ(options.title, titleZ):
    withZ(options.image, imageZ):
      let trayId = self.symbols.createTray(
        titleZ, imageZ, options.isTemplate, options.width, options.height, nil)
      if trayId == 0:
        return (0'u32, errorFromLastError(self.lastErrorString()))
      (trayId, ebNone)

proc setApplicationMenuJson*(self: Core; menuJson: string; handler: StatusItemHandler): EbError =
  withZ(menuJson, z): self.symbols.setApplicationMenu(z, handler)
  self.ensureLastCallSucceeded()

proc showContextMenuJson*(self: Core; menuJson: string; handler: StatusItemHandler): EbError =
  withZ(menuJson, z): self.symbols.showContextMenu(z, handler)
  self.ensureLastCallSucceeded()

proc showTray*(self: Core; trayId: uint32): EbError =
  if not self.symbols.showTray(trayId):
    return errorFromLastError(self.lastErrorString())
  ebNone

proc hideTray*(self: Core; trayId: uint32): EbError =
  self.symbols.hideTray(trayId); self.ensureLastCallSucceeded()

proc setTrayTitle*(self: Core; trayId: uint32; title: string): EbError =
  withZ(title, z): self.symbols.setTrayTitle(trayId, z)
  self.ensureLastCallSucceeded()

proc getTrayBounds*(self: Core; trayId: uint32): (Rect, EbError) =
  let boundsJson = self.symbols.getTrayBounds(trayId)
  parseRectJson($boundsJson)

proc removeTray*(self: Core; trayId: uint32): EbError =
  self.symbols.removeTray(trayId); self.ensureLastCallSucceeded()

proc setDockIconVisible*(self: Core; visible: bool): EbError =
  self.symbols.setDockIconVisible(visible); self.ensureLastCallSucceeded()

proc isDockIconVisible*(self: Core): bool =
  self.symbols.isDockIconVisible()

proc getPrimaryDisplay*(self: Core): (Display, EbError) =
  let jsonText = self.symbols.getPrimaryDisplay()
  if jsonText.isNil: return (default(Display), ebElectrobunCoreFailure)
  parseDisplayJson($jsonText)

proc getAllDisplays*(self: Core): (seq[Display], EbError) =
  let jsonText = self.symbols.getAllDisplays()
  if jsonText.isNil: return (@[], ebElectrobunCoreFailure)
  parseDisplaysJson($jsonText)

proc getCursorScreenPoint*(self: Core): (Point, EbError) =
  let jsonText = self.symbols.getCursorScreenPoint()
  if jsonText.isNil: return (default(Point), ebElectrobunCoreFailure)
  parsePointJson($jsonText)

proc captureScreenRegion*(self: Core; rectangle: Rect): (seq[byte], EbError) =
  let (layout, layoutErr) = screenCaptureLayout(rectangle)
  if layoutErr != ebNone: return (@[], layoutErr)
  var result = newSeq[byte](layout.byteLen)
  if not self.symbols.captureScreenRegion(
    layout.x, layout.y, layout.width, layout.height,
    addr result[0], layout.byteLenU64):
    return (@[], ebElectrobunCoreFailure)
  (result, ebNone)

proc moveToTrash*(self: Core; path: string): bool =
  withZ(path, z): self.symbols.moveToTrash(z)

proc showItemInFolder*(self: Core; path: string): EbError =
  withZ(path, z): self.symbols.showItemInFolder(z)
  self.ensureLastCallSucceeded()

proc openExternal*(self: Core; url: string): bool =
  withZ(url, z): self.symbols.openExternal(z)

proc openPath*(self: Core; path: string): bool =
  withZ(path, z): self.symbols.openPath(z)

proc openFileDialog*(self: Core; options: OpenFileDialogOptions): string =
  withZ(options.startingFolder, startZ):
    withZ(options.allowedFileTypes, typesZ):
      let result = self.symbols.openFileDialog(
        startZ, typesZ,
        if options.canChooseFiles: 1 else: 0,
        if options.canChooseDirectory: 1 else: 0,
        if options.allowsMultipleSelection: 1 else: 0)
      if result.isNil: "" else: $result

proc openFileDialogPaths*(self: Core; options: OpenFileDialogOptions): (seq[string], EbError) =
  let payload = self.openFileDialog(options)
  if payload.len == 0: return (@[], ebNone)
  parseDialogPathsJson(payload)

proc freeDialogPaths*(paths: seq[string]) = discard

proc showMessageBox*(self: Core; options: MessageBoxOptions): (cint, EbError) =
  let buttonsJoined = options.buttons.join(",")
  withZ(options.boxType, boxZ):
    withZ(options.title, titleZ):
      withZ(options.message, messageZ):
        withZ(options.detail, detailZ):
          withZ(buttonsJoined, buttonsZ):
            let response = self.symbols.showMessageBox(
              boxZ, titleZ, messageZ, detailZ, buttonsZ,
              options.defaultId, options.cancelId)
            let err = self.ensureLastCallSucceeded()
            if err != ebNone: return (0, err)
            (response, ebNone)

proc showNotification*(self: Core; options: NotificationOptions): EbError =
  withZ(options.title, titleZ):
    withZ(options.body, bodyZ):
      withZ(options.subtitle, subtitleZ):
        self.symbols.showNotification(titleZ, bodyZ, subtitleZ, options.silent)
  self.ensureLastCallSucceeded()

proc setGlobalShortcutCallback*(self: Core; callback: GlobalShortcutHandler): EbError =
  self.symbols.setGlobalShortcutCallback(callback); self.ensureLastCallSucceeded()

proc registerGlobalShortcut*(self: Core; accelerator: string): bool =
  withZ(accelerator, z): self.symbols.registerGlobalShortcut(z)

proc unregisterGlobalShortcut*(self: Core; accelerator: string): bool =
  withZ(accelerator, z): self.symbols.unregisterGlobalShortcut(z)

proc unregisterAllGlobalShortcuts*(self: Core): EbError =
  self.symbols.unregisterAllGlobalShortcuts(); self.ensureLastCallSucceeded()

proc isGlobalShortcutRegistered*(self: Core; accelerator: string): bool =
  withZ(accelerator, z): self.symbols.isGlobalShortcutRegistered(z)

proc clipboardReadText*(self: Core): (string, bool) =
  let value = self.symbols.clipboardReadText()
  if value.isNil: ("", false) else: ($value, true)

proc clipboardWriteText*(self: Core; text: string): EbError =
  withZ(text, z): self.symbols.clipboardWriteText(z)
  self.ensureLastCallSucceeded()

proc clipboardClear*(self: Core): EbError =
  self.symbols.clipboardClear(); self.ensureLastCallSucceeded()

proc clipboardAvailableFormatsCsv*(self: Core): string =
  let formats = self.symbols.clipboardAvailableFormats()
  if formats.isNil: "" else: $formats

proc sessionGetCookies*(self: Core; partition, filterJson: string): (seq[Cookie], EbError) =
  withZ(partition, partZ):
    withZ(filterJson, filterZ):
      let jsonText = self.symbols.sessionGetCookies(partZ, filterZ)
      if jsonText.isNil: return (@[], ebNone)
      parseCookiesJson($jsonText)

proc sessionSetCookie*(self: Core; partition, cookieJson: string): bool =
  withZ(partition, partZ):
    withZ(cookieJson, cookieZ):
      self.symbols.sessionSetCookie(partZ, cookieZ)

proc sessionRemoveCookie*(self: Core; partition, url, name: string): bool =
  withZ(partition, partZ):
    withZ(url, urlZ):
      withZ(name, nameZ):
        self.symbols.sessionRemoveCookie(partZ, urlZ, nameZ)

proc sessionClearCookies*(self: Core; partition: string): EbError =
  withZ(partition, z): self.symbols.sessionClearCookies(z)
  self.ensureLastCallSucceeded()

proc sessionClearStorageData*(self: Core; partition, storageTypesJson: string): EbError =
  withZ(partition, partZ):
    withZ(storageTypesJson, typesZ):
      self.symbols.sessionClearStorageData(partZ, typesZ)
  self.ensureLastCallSucceeded()

proc setURLOpenHandler*(self: Core; handler: URLOpenHandler): EbError =
  self.symbols.setURLOpenHandler(handler); self.ensureLastCallSucceeded()

proc setAppReopenHandler*(self: Core; handler: AppReopenHandler): EbError =
  self.symbols.setAppReopenHandler(handler); self.ensureLastCallSucceeded()

proc setQuitRequestedHandler*(self: Core; handler: QuitRequestedHandler): EbError =
  gQuitRequestedUserHandler = handler
  self.symbols.setQuitRequestedHandler(quitRequestedTrampoline)
  self.ensureLastCallSucceeded()

proc setExitOnLastWindowClosed*(self: Core; enabled: bool): EbError =
  self.symbols.setExitOnLastWindowClosed(enabled); self.ensureLastCallSucceeded()

proc stopEventLoop*(self: Core): EbError =
  self.symbols.stopEventLoop(); self.ensureLastCallSucceeded()

proc waitForShutdownComplete*(self: Core; timeoutMs: cint): EbError =
  self.symbols.waitForShutdownComplete(timeoutMs); self.ensureLastCallSucceeded()

proc forceExit*(self: Core; code: cint) {.noreturn.} =
  self.symbols.forceExit(code)
  system.quit(int(code))

proc quitGracefully*(self: Core; code: cint) {.noreturn.} =
  self.symbols.quitGracefully(code, 5000)
  forceExit(self, code)

proc wgpuCreateSurfaceForView*(self: Core; instancePtr, viewPtr: pointer): (pointer, EbError) =
  let surfacePtr = self.symbols.wgpuCreateSurfaceForView(instancePtr, viewPtr)
  let err = self.ensureLastCallSucceeded()
  if err != ebNone: return (nil, err)
  (surfacePtr, ebNone)

proc wgpuCreateAdapterDeviceMainThread*(
  self: Core; instancePtr, surfacePtr, outAdapterDevice: pointer): EbError =
  self.symbols.wgpuCreateAdapterDeviceMainThread(instancePtr, surfacePtr, outAdapterDevice)
  self.ensureLastCallSucceeded()

proc wgpuSurfaceConfigureMainThread*(self: Core; surfacePtr, configPtr: pointer): EbError =
  self.symbols.wgpuSurfaceConfigureMainThread(surfacePtr, configPtr)
  self.ensureLastCallSucceeded()

proc wgpuSurfaceGetCurrentTextureMainThread*(self: Core; surfacePtr, surfaceTexturePtr: pointer): EbError =
  self.symbols.wgpuSurfaceGetCurrentTextureMainThread(surfacePtr, surfaceTexturePtr)
  self.ensureLastCallSucceeded()

proc wgpuSurfacePresentMainThread*(self: Core; surfacePtr: pointer): (int32, EbError) =
  let result = self.symbols.wgpuSurfacePresentMainThread(surfacePtr)
  let err = self.ensureLastCallSucceeded()
  if err != ebNone: return (0, err)
  (result, ebNone)

proc runMainThread*(self: Core; appInfo: AppInfo): EbError =
  withZ(appInfo.identifier, idZ):
    withZ(appInfo.name, nameZ):
      withZ(appInfo.channel, channelZ):
        let status = self.symbols.electrobun_core_run_main_thread(idZ, nameZ, channelZ, 0)
        if status != 0:
          return errorFromLastError(self.lastErrorString())
  ebNone

proc quitApp*(code: int) {.noreturn.} = system.quit(code)

proc allowAllNavigation*(_: uint32; _: cstring): uint32 {.cdecl, raises: [].} = 1

proc noopWebviewEvent*(_: uint32; _: cstring; _: cstring) {.cdecl, raises: [].} = discard

proc noopWebviewPostMessage*(_: uint32; _: cstring) {.cdecl, raises: [].} = discard

proc windowRegistryInit*(core: ptr Core): WindowRegistry =
  WindowRegistry(core: core, ids: initHashSet[uint32]())

proc deinit*(self: var WindowRegistry) = self.ids.clear()

proc createBrowserWindow*(self: var WindowRegistry; options: WindowOptions): (BrowserWindowRef, EbError) =
  let (id, err) = self.core[].createWindow(options)
  if err != ebNone: return (default(BrowserWindowRef), err)
  self.ids.incl id
  (BrowserWindowRef(registry: addr self, id: id), ebNone)

proc getById*(self: WindowRegistry; id: uint32): (BrowserWindowRef, bool) =
  if id notin self.ids: (default(BrowserWindowRef), false)
  else: (BrowserWindowRef(registry: addr self, id: id), true)

proc windowClose*(self: BrowserWindowRef): EbError =
  let err = self.registry[].core[].closeWindow(self.id)
  if err == ebNone: self.registry[].ids.excl self.id
  err

proc close*(self: BrowserWindowRef): EbError = windowClose(self)

proc windowRequestClose*(self: BrowserWindowRef): EbError =
  self.registry[].core[].requestWindowClose(self.id)

proc getFrame*(self: BrowserWindowRef): (Rect, EbError) =
  self.registry[].core[].getWindowFrame(self.id)

proc windowSetWindowButtonPosition*(self: BrowserWindowRef; x, y: float64): EbError =
  self.registry[].core[].coreSetWindowButtonPosition(self.id, x, y)

proc windowGetWindowButtonPosition*(self: BrowserWindowRef): (Point, EbError) =
  self.registry[].core[].coreGetWindowButtonPosition(self.id)

proc sessionFromPartition*(core: ptr Core; partition: string): SessionPartition =
  SessionPartition(core: core, partition: partition)

proc defaultSession*(core: ptr Core): SessionPartition =
  sessionFromPartition(core, "persist:default")

proc getCookies*(self: SessionPartition; filter: Option[CookieFilter] = none(CookieFilter)): (seq[Cookie], EbError) =
  let filterValue = if filter.isSome: filter.get else: default(CookieFilter)
  let filterJson = marshalCookieFilter(filterValue)
  self.core[].sessionGetCookies(self.partition, filterJson)

proc setCookie*(self: SessionPartition; cookie: Cookie): bool =
  self.core[].sessionSetCookie(self.partition, marshalCookie(cookie))

proc removeCookie*(self: SessionPartition; url, name: string): bool =
  self.core[].sessionRemoveCookie(self.partition, url, name)

proc clearCookies*(self: SessionPartition): EbError =
  self.core[].sessionClearCookies(self.partition)

proc clearStorageData*(self: SessionPartition; storageTypes: seq[StorageType]): EbError =
  if storageTypes.len == 0:
    return self.core[].sessionClearStorageData(self.partition, "[\"all\"]")
  var b = "["
  for i, st in storageTypes:
    if i > 0: b.add ','
    b.add '"'
    b.add STORAGE_TYPE_NAMES[ord(st)]
    b.add '"'
  b.add ']'
  self.core[].sessionClearStorageData(self.partition, b)

proc createForView*(core: Core; native: WgpuNative; viewPtr: pointer): (WgpuContext, EbError) =
  let instancePtr = native.createInstance()
  if instancePtr.isNil: return (default(WgpuContext), ebElectrobunCoreFailure)
  let (surfacePtr, surfErr) = core.wgpuCreateSurfaceForView(instancePtr, viewPtr)
  if surfErr != ebNone: return (default(WgpuContext), surfErr)
  var adapterDevice: array[2, uint] = [0'u, 0'u]
  let adErr = core.wgpuCreateAdapterDeviceMainThread(instancePtr, surfacePtr, addr adapterDevice[0])
  if adErr != ebNone: return (default(WgpuContext), adErr)
  let devicePtr = cast[pointer](adapterDevice[1])
  if devicePtr.isNil: return (default(WgpuContext), ebElectrobunCoreFailure)
  (WgpuContext(
    viewPtr: viewPtr, instancePtr: instancePtr, surfacePtr: surfacePtr,
    adapterPtr: cast[pointer](adapterDevice[0]), devicePtr: devicePtr), ebNone)

proc createForWgpuView*(core: Core; native: WgpuNative; wgpuViewId: uint32): (WgpuContext, EbError) =
  let (viewPtr, err) = core.getWGPUViewPointer(wgpuViewId)
  if err != ebNone: return (default(WgpuContext), err)
  createForView(core, native, viewPtr)

proc getQueue*(self: WgpuContext; native: WgpuNative): pointer =
  native.deviceGetQueue(self.devicePtr)
