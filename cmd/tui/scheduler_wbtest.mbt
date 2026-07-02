///|
test "loop interval grammar" {
  // Bare seconds and unit suffixes.
  assert_true(parse_loop_interval("300") is Some(300))
  assert_true(parse_loop_interval("30s") is Some(30))
  assert_true(parse_loop_interval("5m") is Some(300))
  assert_true(parse_loop_interval("2h") is Some(7200))
  assert_true(parse_loop_interval("10") is Some(10))
  // Rejected: empty, zero, garbage, mixed, negative-looking, over the bound.
  assert_true(parse_loop_interval("") is None)
  assert_true(parse_loop_interval("0") is None)
  assert_true(parse_loop_interval("0s") is None)
  assert_true(parse_loop_interval("abc") is None)
  assert_true(parse_loop_interval("5m3") is None)
  assert_true(parse_loop_interval("-5") is None)
  assert_true(parse_loop_interval("m") is None)
  assert_true(parse_loop_interval("999999999") is None)
  assert_true(parse_loop_interval("200h") is None)
  // Would overflow Int if multiplied before the ceiling check.
  assert_true(parse_loop_interval("604800h") is None)
  assert_true(parse_loop_interval("604800m") is None)
  // The exact ceiling itself is accepted.
  assert_true(parse_loop_interval("604800") is Some(604_800))
  assert_true(parse_loop_interval("168h") is Some(604_800))
}

///|
test "loop command grammar: arm forms" {
  guard parse_loop_command("5m check CI status")
    is Ok(Arm(interval_secs~, max_fires~, prompt~)) else {
    fail("expected Arm")
  }
  assert_eq(interval_secs, 300)
  assert_eq(max_fires, DefaultMaxLoopFires)
  assert_eq(prompt, "check CI status")

  // --max before the interval is an option…
  guard parse_loop_command("--max 5 30s do the thing")
    is Ok(Arm(interval_secs=interval2, max_fires=max2, prompt=prompt2)) else {
    fail("expected Arm with --max")
  }
  assert_eq(interval2, 30)
  assert_eq(max2, 5)
  assert_eq(prompt2, "do the thing")

  // …but after the interval it is literal prompt text.
  guard parse_loop_command("30s run --max 5 times")
    is Ok(Arm(prompt=prompt3, ..)) else {
    fail("expected Arm with literal --max in prompt")
  }
  assert_eq(prompt3, "run --max 5 times")
}

///|
test "loop command grammar: subcommands" {
  assert_true(parse_loop_command("off") is Ok(Off))
  assert_true(parse_loop_command("status") is Ok(Status))
  assert_true(parse_loop_command("pause") is Ok(Pause))
  assert_true(parse_loop_command("resume") is Ok(Resume))
  assert_true(parse_loop_command("  off  ") is Ok(Off))
}

///|
fn scheduler_test_state() -> State {
  State::new({
    api_key: "k",
    api_url: Some("https://proxy.example/v1/chat/completions"),
    model: V4Pro,
    cwd: ".",
    max_steps: 10,
    thinking: Max,
    session_id: SessionId("loop-test"),
    session_root: ".openseek",
    engine: "openseek",
    engine_mode: Serve,
  })
}

///|
fn armed_state(arguments : String) -> State {
  let state = scheduler_test_state()
  let _ = update(state, UiInput(SlashCommand(name="loop", arguments~)))
  state
}

///|
fn notice_count(cmds : Array[Cmd]) -> Int {
  [ for cmd in cmds if cmd is AppendItem(Notice(_)) => cmd ].length()
}

///|
fn error_count(cmds : Array[Cmd]) -> Int {
  [ for cmd in cmds if cmd is AppendItem(Error(_)) => cmd ].length()
}

///|
test "loop arm/off/status/pause/resume lifecycle" {
  let state = scheduler_test_state()
  // Arm: schedule set, notice appended, full countdown.
  let armed = update(
    state,
    UiInput(SlashCommand(name="loop", arguments="5m check CI")),
  )
  assert_eq(notice_count(armed), 1)
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  assert_eq(schedule.remaining_secs, 300)
  assert_eq(schedule.fires, 0)
  assert_false(schedule.paused)
  // Re-arm replaces.
  let replaced = update(
    state,
    UiInput(SlashCommand(name="loop", arguments="30s other task")),
  )
  assert_eq(notice_count(replaced), 1)
  guard state.schedule is Some(second) else { fail("expected a schedule") }
  assert_eq(second.interval_secs, 30)
  // Status reports without mutating.
  let status = update(
    state,
    UiInput(SlashCommand(name="loop", arguments="status")),
  )
  assert_eq(notice_count(status), 1)
  assert_eq(second.remaining_secs, 30)
  // Pause stops the countdown; resume restarts a full interval.
  let _ = update(state, UiInput(SlashCommand(name="loop", arguments="pause")))
  assert_true(second.paused)
  let _ = update(state, Tick)
  assert_eq(second.remaining_secs, 30)
  let _ = update(state, UiInput(SlashCommand(name="loop", arguments="resume")))
  assert_false(second.paused)
  // Off clears; off again errors.
  let _ = update(state, UiInput(SlashCommand(name="loop", arguments="off")))
  assert_true(state.schedule is None)
  let again = update(state, UiInput(SlashCommand(name="loop", arguments="off")))
  assert_eq(error_count(again), 1)
}

///|
test "loop countdown ticks only while armed, unpaused, and not mid-fire" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  let _ = update(state, Tick)
  let _ = update(state, Tick)
  assert_eq(schedule.remaining_secs, 28)
  // A fire in flight holds the countdown even at zero.
  schedule.remaining_secs = 0
  schedule.fired_run_id = Some(41)
  let _ = update(state, Tick)
  assert_eq(schedule.remaining_secs, 0)
  // Held at zero once due (never negative).
  schedule.fired_run_id = None
  let _ = update(state, Tick)
  assert_eq(schedule.remaining_secs, 0)
}

///|
test "loop re-arms after its own run finishes and pauses on failures" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  // Simulate the choke point having fired: the loop owns the run in flight.
  let run_id = state.start_run(0)
  schedule.remaining_secs = 0
  schedule.fired_run_id = Some(run_id)
  // Success re-arms a full interval and counts the fire.
  let done = update(state, AgentProgress(run_id~, AgentFinished("ok")))
  assert_eq(schedule.remaining_secs, 30)
  assert_eq(schedule.fires, 1)
  assert_true(schedule.fired_run_id is None)
  assert_false(schedule.paused)
  ignore(done)
  // A failing fire pauses instead of re-arming.
  let run2 = state.start_run(0)
  schedule.fired_run_id = Some(run2)
  let failed = update(state, AgentProgress(run_id=run2, AgentError("boom")))
  assert_true(schedule.paused)
  assert_true(schedule.fired_run_id is None)
  assert_eq(notice_count(failed), 1)
  // An interrupt of a resumed fire also pauses.
  schedule.paused = false
  let run3 = state.start_run(0)
  schedule.fired_run_id = Some(run3)
  let _ = update(state, AgentCancelled(run_id=run3))
  assert_true(schedule.paused)
}

///|
test "loop cap disarms after the last fire" {
  let state = armed_state("--max 2 30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  schedule.fires = 1
  let run_id = state.start_run(0)
  schedule.fired_run_id = Some(run_id)
  let done = update(state, AgentProgress(run_id~, AgentFinished("ok")))
  assert_true(state.schedule is None)
  assert_eq(notice_count(done), 1)
}

///|
test "user runs never touch the schedule" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  // A user prompt runs and fails; the schedule is not the owner, so nothing
  // pauses and nothing re-arms.
  let _ = update(state, UiInput(Steer(Prompt("user task"))))
  guard state.run is Running(_) else { fail("expected a user run") }
  let before = schedule.remaining_secs
  let _ = update(state, AgentProgress(run_id=state.run_id, AgentError("boom")))
  assert_false(schedule.paused)
  assert_eq(schedule.remaining_secs, before)
  assert_eq(schedule.fires, 0)
}

///|
test "background command counter tracks spawn and completion" {
  let state = scheduler_test_state()
  // Start a user run, then a background `!` alongside it.
  let _ = update(state, UiInput(Steer(Prompt("task"))))
  let cmds = update(state, UiInput(Steer(Command("ls"))))
  assert_true(
    [ for cmd in cmds if cmd is RunCommand(run_id=None, _) => cmd ].length() ==
    1,
  )
  assert_eq(state.background_commands, 1)
  let _ = update(
    state,
    CommandResult(command="ls", run_id=None, Err(Failure::Failure("boom"))),
  )
  assert_eq(state.background_commands, 0)
}

///|
/// Drive the countdown to due and invoke the choke point once, mirroring the
/// message loop's `update`-then-`scheduler_maybe_fire` shape for a `Tick`.
fn tick_and_fire(state : State, composer_empty~ : Bool) -> Array[Cmd] {
  let cmds = update(state, Tick)
  scheduler_maybe_fire(state, composer_empty~, cmds)
  cmds
}

///|
test "a due loop fires exactly once at an idle tick" {
  let state = armed_state("30s do the rounds")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  // 29 ticks: armed but not due; the choke point stays silent.
  for _ in 0..<29 {
    let cmds = tick_and_fire(state, composer_empty=true)
    assert_eq(start_agent_count(cmds), 0)
  }
  assert_eq(schedule.remaining_secs, 1)
  // The 30th tick fires: notice + verbatim prompt echo + StartAgent.
  let fired = tick_and_fire(state, composer_empty=true)
  assert_eq(start_agent_count(fired), 1)
  assert_eq(notice_count(fired), 1)
  let echoes = [
    for cmd in fired if cmd is AppendItem(Input(Prompt("do the rounds"))) => cmd
  ]
  assert_eq(echoes.length(), 1)
  guard fired[fired.length() - 1] is StartAgent(run_id~, "do the rounds") else {
    fail("expected the fire's StartAgent last")
  }
  assert_true(schedule.fired_run_id is Some(fired_id) && fired_id == run_id)
  guard state.run is Running(_) else {
    fail("expected the fired run in flight")
  }
  // Still due-held, not counting, while its own run is in flight.
  let during = tick_and_fire(state, composer_empty=true)
  assert_eq(start_agent_count(during), 0)
}

///|
test "a due loop defers while anything is busy and fires at the idle boundary" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  // A user prompt occupies the run slot; the countdown reaches due beneath it.
  let _ = update(state, UiInput(Steer(Prompt("user work"))))
  schedule.remaining_secs = 1
  let held = tick_and_fire(state, composer_empty=true)
  assert_eq(start_agent_count(held), 0)
  assert_eq(schedule.remaining_secs, 0)
  // More ticks while busy: still exactly zero fires (no accumulation).
  for _ in 0..<5 {
    assert_eq(start_agent_count(tick_and_fire(state, composer_empty=true)), 0)
  }
  // The user run's terminal is an idle boundary: the deferred fire dispatches
  // in the very same update cycle, no Tick needed.
  let boundary = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done")),
  )
  scheduler_maybe_fire(state, composer_empty=true, boundary)
  assert_eq(start_agent_count(boundary), 1)
  assert_true(schedule.fired_run_id is Some(id) && id == state.run_id)
}

///|
test "each busy source individually holds a due fire" {
  // Draft text under the cursor.
  let drafting = armed_state("30s do x")
  guard drafting.schedule is Some(draft_schedule) else { fail("no schedule") }
  draft_schedule.remaining_secs = 0
  let held = update(drafting, Tick)
  scheduler_maybe_fire(drafting, composer_empty=false, held)
  assert_eq(start_agent_count(held), 0)
  scheduler_maybe_fire(drafting, composer_empty=true, held)
  assert_eq(start_agent_count(held), 1)

  // A background `!` command whose context is still owed to the engine.
  let waiting = armed_state("30s do x")
  guard waiting.schedule is Some(wait_schedule) else { fail("no schedule") }
  let _ = update(waiting, UiInput(Steer(Prompt("user work"))))
  let _ = update(waiting, UiInput(Steer(Command("ls"))))
  let _ = update(
    waiting,
    AgentProgress(run_id=waiting.run_id, AgentFinished("done")),
  )
  wait_schedule.remaining_secs = 0
  // Run slot idle, but the background command is still out.
  assert_eq(waiting.background_commands, 1)
  let blocked = tick_and_fire(waiting, composer_empty=true)
  assert_eq(start_agent_count(blocked), 0)
  // Its completion is itself an idle boundary: the fire rides the same cycle,
  // ordered after the command-context steer.
  let after = update(
    waiting,
    CommandResult(command="ls", run_id=None, Err(Failure::Failure("x"))),
  )
  scheduler_maybe_fire(waiting, composer_empty=true, after)
  assert_eq(start_agent_count(after), 1)
  let steer_index = for index, cmd in after {
    if cmd is SteerAgent(_) {
      break index
    }
  } nobreak {
    fail("expected the command-context steer")
  }
  let start_index = for index, cmd in after {
    if cmd is StartAgent(_, ..) {
      break index
    }
  } nobreak {
    fail("expected the fire's StartAgent")
  }
  assert_true(steer_index < start_index)

  // A paused loop never fires, even when due and idle.
  let paused = armed_state("30s do x")
  guard paused.schedule is Some(pause_schedule) else { fail("no schedule") }
  pause_schedule.remaining_secs = 0
  pause_schedule.paused = true
  assert_eq(start_agent_count(tick_and_fire(paused, composer_empty=true)), 0)
}

///|
test "a fired loop run steers like any other run" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  schedule.remaining_secs = 0
  let fired = tick_and_fire(state, composer_empty=true)
  assert_eq(start_agent_count(fired), 1)
  // The fired run is a normal engine turn: a typed prompt steers it rather
  // than being rejected — the ownership discipline is shared, not special.
  let steered = update(state, UiInput(Steer(Prompt("also check the docs"))))
  assert_true(
    [ for cmd in steered if cmd is SteerAgent(_) => cmd ].length() == 1,
  )
}

///|
test "loop command grammar: rejections name the problem" {
  guard parse_loop_command("") is Err(usage) else { fail("expected usage") }
  assert_true(usage.contains("usage:"))
  guard parse_loop_command("5m") is Err(no_prompt) else {
    fail("expected prompt-required")
  }
  assert_true(no_prompt.contains("prompt is required"))
  guard parse_loop_command("9s do x") is Err(too_short) else {
    fail("expected minimum-interval rejection")
  }
  assert_true(too_short.contains("at least 10s"))
  guard parse_loop_command("soon do x") is Err(bad_interval) else {
    fail("expected invalid-interval rejection")
  }
  assert_true(bad_interval.contains("invalid interval 'soon'"))
  guard parse_loop_command("--max nope 5m do x") is Err(bad_count) else {
    fail("expected bad --max rejection")
  }
  assert_true(bad_count.contains("--max"))
  guard parse_loop_command("--max 0 5m do x") is Err(zero_count) else {
    fail("expected zero --max rejection")
  }
  assert_true(zero_count.contains("--max"))
}

///|
test "loop status segment mirrors schedule state" {
  // No loop: the segment is empty and leaves no dangling separator.
  assert_eq(loop_segment_text(None), "")
  // Counting: a compact countdown.
  let schedule : Schedule = {
    prompt: "do x",
    interval_secs: 300,
    max_fires: 20,
    remaining_secs: 277,
    fires: 0,
    paused: false,
    fired_run_id: None,
  }
  assert_eq(loop_segment_text(Some(schedule)), "⟳ 4m 37s")
  schedule.remaining_secs = 45
  assert_eq(loop_segment_text(Some(schedule)), "⟳ 45s")
  schedule.remaining_secs = 3725
  assert_eq(loop_segment_text(Some(schedule)), "⟳ 1h 02m 05s")
  // Due but deferred, its own fire in flight, and paused.
  schedule.remaining_secs = 0
  assert_eq(loop_segment_text(Some(schedule)), "⟳ due")
  schedule.fired_run_id = Some(7)
  assert_eq(loop_segment_text(Some(schedule)), "⟳ running")
  schedule.fired_run_id = None
  schedule.paused = true
  assert_eq(loop_segment_text(Some(schedule)), "⟳ paused")
}

///|
test "loop segment precedes the clippable variable-length fields" {
  // The status line clips at terminal width from the right; an armed loop's
  // countdown must sit ahead of a long cwd so it cannot be pushed off-screen.
  let state = armed_state("5m do x")
  let segments = status_segments(state)
  let loop_index = for index, segment in segments {
    if segment.text.has_prefix("⟳") {
      break index
    }
  } nobreak {
    fail("expected the loop segment")
  }
  let cwd_index = for index, segment in segments {
    if segment.text == state.config.cwd {
      break index
    }
  } nobreak {
    fail("expected the cwd segment")
  }
  assert_true(loop_index < cwd_index)
}
