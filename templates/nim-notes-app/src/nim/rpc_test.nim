{.define: nimNotesRpcTest.}
include main
import std/[tempfiles, unittest]

var lastResponse: string
var releasedMessages: int

proc responseStub(webviewId: uint32; message: cstring): bool {.cdecl, raises: [].} =
  lastResponse = $message
  true

proc releaseStub(message: cstring) {.cdecl, raises: [].} =
  inc releasedMessages

suite "notes RPC failures":
  test "failed saves return an error, unlock storage and release queued packets":
    let root = createTempDir("nim-notes-rpc-", "")
    defer: removeDir(root)
    let blocker = root / "not-a-directory"
    writeFile(blocker, "file")
    var state = AppState(store: NotesStore(dir: blocker), rng: initRand(42))
    state.core.symbols.sendHostMessageToWebviewViaTransport = responseStub
    state.core.symbols.freeCoreString = releaseStub
    initLock(state.mutex)
    gState = addr state
    defer:
      gState = nil
      deinitLock(state.mutex)

    let packet = $(%*{"type": "request", "id": 1, "method": "saveNote",
      "params": {"id": "note", "title": "Hello", "content": "Body"}})
    releasedMessages = 0
    processQueuedHostMessage(1, packet.cstring)
    check parseJson(lastResponse)["success"].getBool == false
    check parseJson(lastResponse)["id"].getInt == 1
    check releasedMessages == 1
    let unlocked = tryAcquire(state.mutex)
    check unlocked
    if unlocked:
      release(state.mutex)
      state.store.dir = root / "notes"
      ensureNotesDir(state.store)
      processQueuedHostMessage(1, packet.cstring)
      check parseJson(lastResponse)["success"].getBool == true
      check releasedMessages == 2
      check loadNote(state.store, "note").isSome
