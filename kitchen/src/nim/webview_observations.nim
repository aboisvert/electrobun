## Webview callback evidence store (ported from kitchen/src/rust/webview_observations.rs).

import std/[options, strutils]

type
  WebviewEvent* = object
    webviewId*: uint32
    name*, detail*: string

  WebviewObservations* = object
    events*: seq[WebviewEvent]

proc newWebviewObservations*(): WebviewObservations =
  WebviewObservations()

proc clear*(self: var WebviewObservations) =
  self.events.setLen(0)

proc record*(self: var WebviewObservations; webviewId: uint32; name, detail: string) =
  for event in self.events:
    if event.webviewId == webviewId and event.name == name and event.detail == detail:
      return
  self.events.add WebviewEvent(webviewId: webviewId, name: name, detail: detail)

proc contains*(self: WebviewObservations; webviewId: uint32; name: string; detail: Option[string] = none(string)): bool =
  for event in self.events:
    if event.webviewId == webviewId and event.name == name:
      if detail.isNone or event.detail.contains(detail.get()):
        return true
  false

when isMainModule:
  import std/unittest

  suite "webview callback isolation":
    test "an old view's late callback cannot complete the next test":
      var observations = newWebviewObservations()
      observations.record(15, "will-navigate", "about:blank")
      observations.clear()
      observations.record(15, "dom-ready", "about:blank")
      check not observations.contains(16, "dom-ready")
      observations.record(16, "dom-ready", "views://test-harness/index.html")
      check observations.contains(16, "dom-ready")

    test "a later event cannot erase the navigation commit url":
      var observations = newWebviewObservations()
      observations.record(18, "did-commit-navigation", "views://zig/index.html")
      observations.record(18, "dom-ready", "views://test-harness/index.html")
      check observations.contains(18, "did-commit-navigation", some("views://zig"))

    test "another view's same event cannot replace the target evidence":
      var observations = newWebviewObservations()
      observations.record(18, "did-commit-navigation", "views://zig/index.html")
      observations.record(17, "did-commit-navigation", "views://test-harness/index.html")
      check observations.contains(18, "did-commit-navigation", some("views://zig"))
      check not observations.contains(17, "did-commit-navigation", some("views://zig"))

    test "a late same-event from an old document cannot erase observed evidence":
      var observations = newWebviewObservations()
      observations.record(18, "did-commit-navigation", "views://zig/index.html")
      observations.record(18, "did-commit-navigation", "views://test-harness/index.html")
      check observations.contains(18, "did-commit-navigation", some("views://zig"))
      observations.record(18, "did-commit-navigation", "views://zig/index.html")
      check observations.events.len == 2

    test "navigation requires the target event and url together":
      var observations = newWebviewObservations()
      observations.record(18, "did-commit-navigation", "views://test-harness/index.html")
      observations.record(18, "will-navigate", "views://zig/index.html")
      check not observations.contains(18, "did-commit-navigation", some("views://zig"))
      observations.record(18, "did-commit-navigation", "views://zig/index.html")
      check observations.contains(18, "did-commit-navigation", some("views://zig"))

    test "reset removes prior evidence for the same view":
      var observations = newWebviewObservations()
      observations.record(18, "did-navigate", "views://zig/index.html")
      observations.clear()
      check not observations.contains(18, "did-navigate", some("views://zig"))
