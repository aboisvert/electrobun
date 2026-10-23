## Owns worker Thread objects at stable addresses until they have been joined.
## Task arguments must remain valid until the task returns. Tasks own any
## argument cleanup; the registry owns only the worker and its Thread object.

import std/[atomics, locks, typedthreads]

type
  Worker[T] = object
    thread: Thread[ptr Worker[T]]
    task: proc (arg: T) {.nimcall, gcsafe.}
    arg: T
    finished: Atomic[bool]

  WorkerThreads*[T] = object
    mutex: Lock
    workers: seq[ptr Worker[T]]

proc initWorkerThreads*[T](self: var WorkerThreads[T]) =
  initLock(self.mutex)

proc runWorker[T](worker: ptr Worker[T]) {.thread.} =
  try:
    worker.task(worker.arg)
  finally:
    worker.finished.store(true, moRelease)

proc startWorker*[T](self: var WorkerThreads[T];
    task: proc (arg: T) {.nimcall, gcsafe.}; arg: T) =
  let worker = cast[ptr Worker[T]](allocShared0(sizeof(Worker[T])))
  worker.task = task
  worker.arg = arg
  withLock self.mutex:
    try:
      createThread(worker.thread, runWorker[T], worker)
    except:
      deallocShared(worker)
      raise
    self.workers.add worker

proc reapFinishedWorkers*[T](self: var WorkerThreads[T]): int =
  withLock self.mutex:
    var index = 0
    while index < self.workers.len:
      let worker = self.workers[index]
      if not worker.finished.load(moAcquire):
        inc index
        continue
      # The task is done, but Nim's wrapper still writes to worker.thread.
      # Join before freeing it; no task can be waiting on the UI at this point.
      joinThread(worker.thread)
      deallocShared(worker)
      self.workers.delete(index)
      inc result

proc pendingWorkerCount*[T](self: var WorkerThreads[T]): int =
  withLock self.mutex:
    result = self.workers.len

proc deinitWorkerThreads*[T](self: var WorkerThreads[T]) =
  ## Call only after producers stop. Unlike reaping, shutdown waits for tasks.
  for worker in self.workers:
    joinThread(worker.thread)
    deallocShared(worker)
  self.workers.setLen(0)
  deinitLock(self.mutex)
