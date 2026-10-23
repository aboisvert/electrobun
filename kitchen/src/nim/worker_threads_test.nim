import std/[atomics, monotimes, os, times, unittest]
import ./worker_threads

type Gate = object
  released: Atomic[bool]
  completed: Atomic[int]

proc gatedTask(gate: ptr Gate) {.gcsafe.} =
  while not gate.released.load(moAcquire):
    sleep(1)
  discard gate.completed.fetchAdd(1, moRelease)

proc startFromReturningFrame(workers: var WorkerThreads[ptr Gate]; gate: ptr Gate) {.noinline.} =
  workers.startWorker(gatedTask, gate)

proc waitForCompletion(gate: var Gate; count: int): bool =
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while gate.completed.load(moAcquire) != count:
    if getMonoTime() >= deadline:
      return false
    sleep(1)
  true

suite "worker thread lifetimes":
  test "workers survive the starting frame and registry growth":
    var workers: WorkerThreads[ptr Gate]
    initWorkerThreads(workers)
    var gate: Gate
    defer:
      gate.released.store(true, moRelease)
      deinitWorkerThreads(workers)

    for _ in 0 ..< 64:
      startFromReturningFrame(workers, addr gate)
    check workers.pendingWorkerCount() == 64
    # An unfinished task may need the UI, so reaping must not join it.
    check workers.reapFinishedWorkers() == 0
    gate.released.store(true, moRelease)
    check waitForCompletion(gate, 64)

    var reaped = 0
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while workers.pendingWorkerCount() > 0 and getMonoTime() < deadline:
      reaped += workers.reapFinishedWorkers()
      sleep(1)
    check reaped == 64
    check workers.pendingWorkerCount() == 0
    check workers.reapFinishedWorkers() == 0

  test "shutdown joins and releases workers not yet reaped":
    var workers: WorkerThreads[ptr Gate]
    initWorkerThreads(workers)
    var gate: Gate
    startFromReturningFrame(workers, addr gate)
    gate.released.store(true, moRelease)
    deinitWorkerThreads(workers)
    check gate.completed.load(moAcquire) == 1
