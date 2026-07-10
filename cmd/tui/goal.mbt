///|
/// `/goal` — show, set, or clear the session's standing goal.
///
/// Bare `/goal` shows the mirrored state locally. `set <text>` and `clear`
/// go to the serve engine as a wire command; the transcript confirmation
/// arrives with the engine's `goal_updated` event, after the durable append,
/// so the TUI never claims a goal that was not persisted. The explicit `set`
/// keyword keeps a goal whose text starts with "clear" expressible.
fn handle_goal_command(
  state : State,
  arguments : String,
  cmds : Array[Cmd],
) -> Unit {
  let trimmed = arguments.trim().to_owned()
  if trimmed.is_empty() {
    let text = match state.goal {
      Some(goal) => "goal: \{goal}"
      None => "no standing goal — set one with /goal set <text>"
    }
    cmds.push(AppendItem(command_notice(text)))
    return
  }
  // The goal is durable session state on the persistent serve engine; a
  // oneshot engine is spawned per prompt and keeps no session to anchor it.
  if state.config.engine_mode is OneShot {
    cmds.push(
      AppendItem(
        Error("The goal command is not supported by a oneshot engine."),
      ),
    )
    return
  }
  if trimmed == "clear" {
    // Always send the clear: the mirror lags the engine by one ack, so a
    // clear typed while a set is still in flight must not be dropped on the
    // mirror's say-so. A tombstone on a goalless session is a harmless
    // no-op the engine still confirms.
    cmds.push(UpdateGoal(None))
    return
  }
  if trimmed == "set" || trimmed.has_prefix("set ") {
    let text = trimmed["set".length():].trim().to_owned()
    if text.is_empty() {
      cmds.push(AppendItem(Error("usage: /goal set <text>")))
    } else {
      cmds.push(UpdateGoal(Some(text)))
    }
    return
  }
  cmds.push(AppendItem(Error("usage: /goal | /goal set <text> | /goal clear")))
}

///|
/// Mirror an engine-confirmed goal update into local state and the
/// transcript. The engine's durable-append confirmation is the only writer
/// of the mirror — both the serve path (`EngineGoalUpdated`) and the
/// oneshot path (`GoalUpdated`) land here.
fn apply_goal_update(state : State, goal : String?, cmds : Array[Cmd]) -> Unit {
  state.goal = goal
  let title = match goal {
    Some(text) => "goal set: \{text}"
    None => "goal cleared"
  }
  cmds.push(AppendItem(Input(Notice(title))))
}
