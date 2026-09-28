///|
/// Tie the engine's whole process tree to the lifetime of its root process.
///
/// On Unix this is a no-op: the default `moonx` engine `exec`s `moonrun`, so
/// the spawned PID *is* the engine and the process library's cancellation
/// (SIGTERM, then SIGKILL) reaches it directly.
///
/// On Windows `moonx` instead runs `moonrun` as a child and waits for it, and
/// the process library's hard kill is `TerminateProcess` on the root PID
/// alone. A `moonrun` that outlives it would keep holding the stdout/stderr
/// pipes (stalling the reader's EOF) and the session lock. So the root is
/// placed in a dedicated Job Object that disallows breakaway — everything it
/// starts stays inside — and a watcher terminates the job as soon as the root
/// exits, for whatever reason: a graceful exit finds the job already empty,
/// while a killed `moonx` takes its orphaned children down with it. The job
/// also kills its members if the TUI itself dies without cleaning up.
///
/// Containment is best effort: if the job cannot be set up, the engine runs
/// exactly as it would without it.
#cfg(platform="windows")
fn[G] contain_engine_tree(
  group : @async.TaskGroup[G],
  proc : @process.Process,
) -> Unit {
  let job = engine_tree_contain(proc.pid)
  guard job != 0UL else { return }
  group.spawn_bg(no_wait=true) <| () => {
    // Also runs if the watcher is cancelled by the group's teardown.
    defer engine_tree_terminate(job)
    proc.wait() |> ignore
  }
}

///|
#cfg(not(platform="windows"))
fn[G] contain_engine_tree(
  _group : @async.TaskGroup[G],
  _proc : @process.Process,
) -> Unit {
  ()
}

///|
/// Put process `pid` and its existing descendants in a new kill-on-close Job
/// Object; returns the job handle, or 0 when containment is unavailable.
#cfg(platform="windows")
extern "C" fn engine_tree_contain(pid : Int) -> UInt64 = "moonbitlang_openseek_tui_engine_tree_contain"

///|
/// Terminate every process in the job and close its handle.
#cfg(platform="windows")
extern "C" fn engine_tree_terminate(job : UInt64) = "moonbitlang_openseek_tui_engine_tree_terminate"
