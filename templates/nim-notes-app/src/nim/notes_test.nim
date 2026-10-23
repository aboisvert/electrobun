import std/[options, os, random, unittest]
import notes

suite "notes storage":
  test "generateNoteId uses base36 prefix and suffix length":
    var r = initRand(42)
    let id = generateNoteId(r)
    check id.len >= 6

  test "loadAllNotes sorts by updatedAt descending":
    let root = getTempDir() / "nim-notes-test-sort"
    removeDir(root)
    createDir(root)
    defer: removeDir(root)
    let store = NotesStore(dir: root)
    writeNote(store, Note(
      id: "older",
      title: "Older",
      content: "a",
      updatedAt: "2020-01-01T00:00:00.000Z",
    ))
    writeNote(store, Note(
      id: "newer",
      title: "Newer",
      content: "b",
      updatedAt: "2025-01-01T00:00:00.000Z",
    ))
    let notes = loadAllNotes(store)
    check notes.len == 2
    check notes[0].title == "Newer"
    check notes[1].title == "Older"

  test "save load and delete round trip":
    let root = getTempDir() / "nim-notes-test-roundtrip"
    removeDir(root)
    createDir(root)
    defer: removeDir(root)
    let store = NotesStore(dir: root)
    var r = initRand(7)
    let saved = saveNote(store, r, none(string), "Hello", "Body")
    let loaded = loadNote(store, saved.id)
    check loaded.isSome
    check loaded.get.title == "Hello"
    check loaded.get.content == "Body"
    check deleteNote(store, saved.id)
    check loadNote(store, saved.id).isNone

  test "saveNote defaults empty title to Untitled":
    let root = getTempDir() / "nim-notes-test-untitled"
    removeDir(root)
    createDir(root)
    defer: removeDir(root)
    let store = NotesStore(dir: root)
    var r = initRand(3)
    let saved = saveNote(store, r, none(string), "", "x")
    check saved.title == "Untitled"
