import std/os
import electrobun

const DefaultSecretKey =
  "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32"

var gCore: Core
var gBundlePaths: BundlePaths

proc createUi() {.thread.} =
  {.cast(gcsafe).}:
    sleep(150)

    let cfgErr = gCore.configureWebviewRuntimeFromExecutableDir(gBundlePaths, 0)
    if cfgErr != ebNone:
      stderr.writeLine("[hello] failed to configure webview runtime: ", cfgErr)
      return

    var windowOptions = defaultWindowOptions("Hello Electrobun")
    windowOptions.frame = Rect(x: 160.0, y: 100.0, width: 800.0, height: 600.0)
    let (windowId, windowErr) = gCore.createWindow(windowOptions)
    if windowErr != ebNone:
      stderr.writeLine("[hello] failed to create window: ", windowErr)
      return

    var webviewOptions = defaultWebviewOptions(windowId)
    webviewOptions.url = "views://mainview/index.html"
    webviewOptions.frame = Rect(x: 0.0, y: 0.0, width: 800.0, height: 600.0)
    webviewOptions.secretKey = DefaultSecretKey
    webviewOptions.sandbox = false
    webviewOptions.callbacks.decideNavigation = allowAllNavigation
    webviewOptions.callbacks.event = noopWebviewEvent
    webviewOptions.callbacks.eventBridge = noopWebviewPostMessage

    let (_, webviewErr) = gCore.createWebview(webviewOptions)
    if webviewErr != ebNone:
      stderr.writeLine("[hello] failed to create webview: ", webviewErr)
      discard gCore.closeWindow(windowId)

proc main() =
  var core: Core
  var coreErr: EbError
  (core, coreErr) = load()
  if coreErr != ebNone:
    stderr.writeLine("[hello] failed to load Electrobun core: ", coreErr)
    return
  defer: core.close()

  var bundlePaths: BundlePaths
  var bundleErr: EbError
  (bundlePaths, bundleErr) = resolveBundlePaths()
  if bundleErr != ebNone:
    stderr.writeLine("[hello] failed to resolve bundle paths: ", bundleErr)
    return
  defer: bundlePaths.deinit()

  var ownedAppInfo: OwnedAppInfo
  var appInfoErr: EbError
  (ownedAppInfo, appInfoErr) = resolveAppInfoFromBundle(bundlePaths)
  if appInfoErr != ebNone:
    stderr.writeLine("[hello] failed to resolve app info: ", appInfoErr)
    return
  defer: ownedAppInfo.deinit()
  let appInfo = ownedAppInfo.borrowed()

  gCore = core
  gBundlePaths = bundlePaths

  var uiThread: Thread[void]
  createThread(uiThread, createUi)

  let runErr = core.runMainThread(appInfo)
  if runErr != ebNone:
    stderr.writeLine("[hello] main thread exited with error: ", runErr)

when isMainModule:
  main()
