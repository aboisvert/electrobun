import std/[os, unittest]
import electrobun

# Compile with `nim cpp`: the native callback header uses C++ includes.
# Use the real callback typedef so signature drift fails native compilation too.
{.passC: "-I" & currentSourcePath().parentDir() / "../../native/shared".}
type NativeWindowKeyHandler {.importc: "WindowKeyHandler", header: "callbacks.h".} =
  proc (windowId, keyCode, modifiers, isDown, isRepeat: uint32) {.cdecl, raises: [].}

var observed: array[5, uint32]
proc onKey(windowId, keyCode, modifiers, isDown, isRepeat: uint32) {.cdecl, raises: [].} =
  observed = [windowId, keyCode, modifiers, isDown, isRepeat]

suite "callback ABI":
  test "keyboard callback matches the native five-argument typedef":
    let sdkHandler: WindowKeyHandler = onKey
    let nativeHandler: NativeWindowKeyHandler = sdkHandler
    nativeHandler(10, 20, 30, 1, 0)
    check observed == [10'u32, 20, 30, 1, 0]
