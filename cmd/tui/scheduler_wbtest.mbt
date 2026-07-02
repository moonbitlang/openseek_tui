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
