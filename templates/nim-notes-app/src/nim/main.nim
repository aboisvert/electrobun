import std/[atomics, json, locks, options, os, random]
import electrobun
import notes

const DefaultSecretKey =
  "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32"

type AppState = object
  core: Core
  bundlePaths: BundlePaths
  store: NotesStore
  homeDir: string
  rng: Rand
  mutex: Lock
  webviewId: uint32

var
  gState: ptr AppState
  gQueueRunning: Atomic[bool]
  gShuttingDown: Atomic[bool]

proc requestShutdown() =
  if gShuttingDown.exchange(true):
    return
  gQueueRunning.store(false)

proc mainWindowClosed(_: uint32) {.cdecl, raises: [].} =
  requestShutdown()

proc appState(): ptr AppState =
  if gState.isNil:
    raise newException(CatchableError, "nim-notes state not initialized")
  gState

proc objString(obj: JsonNode; name: string): Option[string] =
  if name notin obj or obj[name].kind != JString:
    none(string)
  else:
    some(obj[name].getStr())

proc rpcRequestId(value: JsonNode): (uint64, bool) =
  case value.kind
  of JInt:
    let v = value.getInt
    if v < 0:
      (0'u64, false)
    else:
      (uint64(v), true)
  else:
    (0'u64, false)

proc sendRpcResponse(webviewId: uint32; requestId: uint64; payload: JsonNode) =
  let state = appState()
  let err = state.core.sendHostMessageToWebviewJson(
    webviewId,
    %*{"type": "response", "id": requestId, "success": true, "payload": payload},
  )
  if err != ebNone:
    stderr.writeLine("[nim-notes] failed to send RPC response: ", err)

proc sendRpcError(webviewId: uint32; requestId: uint64; message: string) =
  let state = appState()
  let err = state.core.sendHostMessageToWebviewJson(
    webviewId,
    %*{"type": "response", "id": requestId, "success": false, "error": message},
  )
  if err != ebNone:
    stderr.writeLine("[nim-notes] failed to send RPC error: ", err)

proc notesToJson(notes: seq[Note]): JsonNode =
  var items = newJArray()
  for note in notes:
    items.add noteToJson(note)
  items

proc handleRpcRequest(webviewId: uint32; requestId: uint64; rpcMethod: string; params: JsonNode) =
  let state = appState()
  case rpcMethod
  of "getNotes":
    let notes = block:
      acquire(state.mutex)
      defer: release(state.mutex)
      loadAllNotes(state.store)
    sendRpcResponse(webviewId, requestId, notesToJson(notes))
  of "getNote":
    if params.kind != JObject:
      sendRpcError(webviewId, requestId, "Invalid getNote params")
      return
    let id = objString(params, "id")
    if id.isNone or id.get.len == 0:
      sendRpcError(webviewId, requestId, "Missing note id")
      return
    let note = block:
      acquire(state.mutex)
      defer: release(state.mutex)
      loadNote(state.store, id.get)
    if note.isNone:
      sendRpcResponse(webviewId, requestId, newJNull())
    else:
      sendRpcResponse(webviewId, requestId, noteToJson(note.get))
  of "saveNote":
    if params.kind != JObject:
      sendRpcError(webviewId, requestId, "Invalid saveNote params")
      return
    var noteId = objString(params, "id")
    if noteId.isSome and noteId.get.len == 0:
      noteId = none(string)
    let title =
      if "title" in params and params["title"].kind == JString:
        params["title"].getStr()
      else:
        ""
    let content =
      if "content" in params and params["content"].kind == JString:
        params["content"].getStr()
      else:
        ""
    let saved = block:
      acquire(state.mutex)
      defer: release(state.mutex)
      saveNote(state.store, state.rng, noteId, title, content)
    sendRpcResponse(
      webviewId,
      requestId,
      %*{"success": true, "note": noteToJson(saved)},
    )
  of "deleteNote":
    if params.kind != JObject:
      sendRpcError(webviewId, requestId, "Invalid deleteNote params")
      return
    let id = objString(params, "id")
    if id.isNone or id.get.len == 0:
      sendRpcError(webviewId, requestId, "Missing note id")
      return
    let ok = block:
      acquire(state.mutex)
      defer: release(state.mutex)
      deleteNote(state.store, id.get)
    sendRpcResponse(webviewId, requestId, %*{"success": ok})
  of "exportNote":
    if params.kind != JObject:
      sendRpcError(webviewId, requestId, "Invalid exportNote params")
      return
    let id = objString(params, "id")
    if id.isNone or id.get.len == 0:
      sendRpcError(webviewId, requestId, "Missing note id")
      return
    let note = block:
      acquire(state.mutex)
      defer: release(state.mutex)
      loadNote(state.store, id.get)
    if note.isNone:
      sendRpcResponse(webviewId, requestId, %*{"success": false})
      return
    var options = defaultOpenFileDialogOptions()
    options.startingFolder =
      if state.homeDir.len > 0:
        state.homeDir
      else:
        "~/"
    options.canChooseFiles = false
    options.canChooseDirectory = true
    options.allowsMultipleSelection = false
    let (paths, dialogErr) = state.core.openFileDialogPaths(options)
    if dialogErr != ebNone or paths.len == 0 or paths[0].len == 0:
      sendRpcResponse(webviewId, requestId, %*{"success": false})
      return
    let exportPath = paths[0] / (note.get.title & ".txt")
    try:
      writeFile(exportPath, note.get.content)
      sendRpcResponse(
        webviewId,
        requestId,
        %*{"success": true, "path": exportPath},
      )
    except CatchableError:
      sendRpcResponse(webviewId, requestId, %*{"success": false})
  else:
    sendRpcError(webviewId, requestId, "Unknown RPC request")

proc handleHostMessage(webviewId: uint32; message: string) =
  if message.len == 0:
    return
  let parsed =
    try:
      parseJson(message)
    except CatchableError:
      stderr.writeLine("[nim-notes] failed to parse RPC packet")
      return
  if parsed.kind != JObject:
    return
  let packetType = objString(parsed, "type")
  if packetType.isNone:
    return
  if packetType.get == "request":
    if "id" notin parsed:
      return
    let rpcMethod = objString(parsed, "method")
    if rpcMethod.isNone:
      return
    let (requestId, hasRequestId) = rpcRequestId(parsed["id"])
    if not hasRequestId:
      return
    let params =
      if "params" in parsed:
        parsed["params"]
      else:
        newJNull()
    try:
      handleRpcRequest(webviewId, requestId, rpcMethod.get, params)
    except CatchableError:
      sendRpcError(webviewId, requestId, "Could not complete notes request")

proc hostBridge(webviewId: uint32; message: cstring) {.cdecl, raises: [].} =
  try:
    handleHostMessage(webviewId, $message)
  except CatchableError:
    discard

proc processQueuedHostMessage(webviewId: uint32; message: cstring) =
  try:
    handleHostMessage(webviewId, $message)
  except CatchableError:
    stderr.writeLine("[nim-notes] failed to process queued RPC packet")
  finally:
    gState.core.freeCoreString(message)

proc drainHostMessageQueueImpl() =
  while gQueueRunning.load():
    if gState.isNil:
      sleep(10)
      continue
    var drainedAny = false
    while gQueueRunning.load():
      var webviewId: uint32
      let message = gState.core.popNextQueuedHostMessage(webviewId)
      if message.isNil:
        break
      processQueuedHostMessage(webviewId, message)
      drainedAny = true
    if not drainedAny:
      sleep(10)

proc drainHostMessageQueue() {.thread.} =
  {.cast(gcsafe).}:
    drainHostMessageQueueImpl()

proc createUiImpl() =
  let state = appState()
  sleep(150)
  if state.core.configureWebviewRuntimeFromExecutableDir(state.bundlePaths, 0) != ebNone:
    stderr.writeLine("[nim-notes] failed to configure webview runtime")
    return

  var windowOptions = defaultWindowOptions("Notes")
  windowOptions.frame = Rect(x: 200.0, y: 200.0, width: 900.0, height: 650.0)
  windowOptions.callbacks.close = mainWindowClosed
  let (windowId, windowErr) = state.core.createWindow(windowOptions)
  if windowErr != ebNone:
    stderr.writeLine("[nim-notes] failed to create window: ", windowErr)
    return

  var webviewOptions = defaultWebviewOptions(windowId)
  webviewOptions.url = "views://mainview/index.html"
  webviewOptions.frame = Rect(x: 0.0, y: 0.0, width: 900.0, height: 650.0)
  webviewOptions.secretKey = DefaultSecretKey
  webviewOptions.sandbox = false
  webviewOptions.callbacks = WebviewCallbacks(
    decideNavigation: allowAllNavigation,
    event: noopWebviewEvent,
    eventBridge: noopWebviewPostMessage,
    hostBridge: hostBridge,
  )

  let (webviewId, webviewErr) = state.core.createWebview(webviewOptions)
  if webviewErr != ebNone:
    stderr.writeLine("[nim-notes] failed to create webview: ", webviewErr)
    discard state.core.closeWindow(windowId)
    return

  acquire(state.mutex)
  state.webviewId = webviewId
  release(state.mutex)

  echo "[nim-notes] Notes stored in: ", state.store.dir

proc createUi() {.thread.} =
  {.cast(gcsafe).}:
    createUiImpl()

proc runMainProcess() =
  gQueueRunning.store(true)
  gShuttingDown.store(false)

  var core: Core
  var coreErr: EbError
  (core, coreErr) = load()
  if coreErr != ebNone:
    stderr.writeLine("[nim-notes] failed to load Electrobun core: ", coreErr)
    quit 1
  defer: core.close()

  var bundlePaths: BundlePaths
  var bundleErr: EbError
  (bundlePaths, bundleErr) = resolveBundlePaths()
  if bundleErr != ebNone:
    stderr.writeLine("[nim-notes] failed to resolve bundle paths: ", bundleErr)
    quit 1
  defer: bundlePaths.deinit()

  var ownedAppInfo: OwnedAppInfo
  var appInfoErr: EbError
  (ownedAppInfo, appInfoErr) = resolveAppInfoFromBundle(bundlePaths)
  if appInfoErr != ebNone:
    stderr.writeLine("[nim-notes] failed to resolve app info: ", appInfoErr)
    quit 1
  defer: ownedAppInfo.deinit()
  let appInfo = ownedAppInfo.borrowed()

  let (paths, pathsErr) = resolvePaths(appInfo)
  if pathsErr != ebNone:
    stderr.writeLine("[nim-notes] failed to resolve paths: ", pathsErr)
    quit 1

  var store = NotesStore(dir: paths.userData / "notes")
  ensureNotesDir(store)

  var state = AppState(
    core: core,
    bundlePaths: bundlePaths,
    store: store,
    homeDir: paths.home,
    rng: initRand(),
  )
  initLock(state.mutex)
  gState = addr state
  defer:
    gState = nil
    deinitLock(state.mutex)

  var uiThread: Thread[void]
  var queueThread: Thread[void]
  createThread(uiThread, createUi)
  createThread(queueThread, drainHostMessageQueue)
  defer: requestShutdown()

  let runErr = state.core.runMainThread(appInfo)
  if runErr != ebNone:
    stderr.writeLine("[nim-notes] main thread exited with error: ", runErr)

when isMainModule and not defined(nimNotesRpcTest):
  runMainProcess()
