## File-backed note storage for the notes RPC handlers.

import std/[json, os, options, random, strutils, times, algorithm]

const Base36Chars = "0123456789abcdefghijklmnopqrstuvwxyz"

type
  Note* = object
    id*, title*, content*, updatedAt*: string

  NotesStore* = object
    dir*: string

proc toBase36*(n: int64): string =
  if n == 0:
    return "0"
  var x = n
  result = ""
  while x > 0:
    result = Base36Chars[x mod 36] & result
    x = x div 36

proc randomBase36Suffix*(r: var Rand; len: int): string =
  result = newString(len)
  for i in 0 ..< len:
    result[i] = Base36Chars[r.rand(0 .. Base36Chars.high)]

proc nowMillis(): int64 =
  let t = getTime()
  t.toUnix() * 1000 + int64(t.nanosecond div 1_000_000)

proc generateNoteId*(r: var Rand): string =
  toBase36(nowMillis()) & randomBase36Suffix(r, 5)

proc iso8601Now*(): string =
  format(getTime().utc(), "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'")

proc ensureNotesDir*(store: NotesStore) =
  createDir(store.dir)

proc notePath*(store: NotesStore; id: string): string =
  store.dir / (id & ".json")

proc noteFromJson*(value: JsonNode): Option[Note] =
  if value.kind != JObject:
    return none(Note)
  template field(name: string): Option[string] =
    if name notin value or value[name].kind != JString:
      none(string)
    else:
      some(value[name].getStr())
  let id = field("id")
  let title = field("title")
  let content = field("content")
  let updatedAt = field("updatedAt")
  if id.isNone or title.isNone or content.isNone or updatedAt.isNone:
    return none(Note)
  some(Note(
    id: id.get,
    title: title.get,
    content: content.get,
    updatedAt: updatedAt.get,
  ))

proc noteToJson*(note: Note): JsonNode =
  %*{
    "id": note.id,
    "title": note.title,
    "content": note.content,
    "updatedAt": note.updatedAt,
  }

proc loadNote*(store: NotesStore; id: string): Option[Note] =
  let path = notePath(store, id)
  if not fileExists(path):
    return none(Note)
  try:
    let text = readFile(path)
    return noteFromJson(parseJson(text))
  except CatchableError:
    return none(Note)

proc loadAllNotes*(store: NotesStore): seq[Note] =
  if not dirExists(store.dir):
    return @[]
  var notes: seq[Note] = @[]
  for entry in walkDir(store.dir):
    if entry.kind != pcFile:
      continue
    if not entry.path.endsWith(".json"):
      continue
    let id = splitFile(entry.path).name
    if id.len == 0:
      continue
    let note = loadNote(store, id)
    if note.isSome:
      notes.add note.get
  notes.sort do (a, b: Note) -> int:
    cmp(b.updatedAt, a.updatedAt)
  notes

proc writeNote*(store: NotesStore; note: Note) =
  writeFile(notePath(store, note.id), $noteToJson(note))

proc saveNote*(
  store: NotesStore;
  r: var Rand;
  id: Option[string];
  title, content: string,
): Note =
  let noteId =
    if id.isSome and id.get.len > 0:
      id.get
    else:
      generateNoteId(r)
  let displayTitle =
    if title.len == 0:
      "Untitled"
    else:
      title
  result = Note(
    id: noteId,
    title: displayTitle,
    content: content,
    updatedAt: iso8601Now(),
  )
  writeNote(store, result)

proc deleteNote*(store: NotesStore; id: string): bool =
  let path = notePath(store, id)
  if not fileExists(path):
    return false
  try:
    removeFile(path)
    true
  except CatchableError:
    false
