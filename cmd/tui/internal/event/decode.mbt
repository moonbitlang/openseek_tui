// Mapping from the engine's decoded JSONL values to typed `AgentEvent`s. Reading
// lines, skipping blanks, and parsing each as JSON is `bobzhang/jsonl`'s job
// (`@jsonl.each` in `cmd/tui`); this module only maps an already-parsed value,
// keyed by its `"event"` discriminator.

///|
/// Map one decoded JSONL value from the engine into an `AgentEvent`.
///
/// Returns `None` for a non-object value or an unrecognized `"event"` string so
/// a noisy or newer engine never crashes the UI; the caller simply drops it.
pub fn decode_event(object : Json) -> AgentEvent? {
  match @jsonx.string(object, "event") {
    "agent_step" => Some(AgentStep)
    "assistant_delta" => Some(AssistantDelta(@jsonx.string(object, "content")))
    "reasoning_delta" => Some(ReasoningDelta(@jsonx.string(object, "content")))
    "reasoning_message" =>
      Some(ReasoningMessage(@jsonx.string(object, "content")))
    "steer_applied" => {
      let content = @jsonx.string(object, "content")
      match @jsonx.string(object, "kind") {
        "command" => Some(SteerApplied(Command(content)))
        _ => Some(SteerApplied(Prompt(content)))
      }
    }
    "steer_dropped" => Some(SteerDropped(@jsonx.string(object, "content")))
    "assistant_message" =>
      Some(AssistantMessage(@jsonx.string(object, "content")))
    "runtime_update" => Some(RuntimeUpdate(@jsonx.string(object, "content")))
    "session_error" => Some(SessionError(@jsonx.string(object, "error")))
    "usage" => {
      let prompt = @jsonx.int(object, "prompt_tokens")
      let completion = @jsonx.int(object, "completion_tokens")
      Some(Usage({ total_tokens: prompt + completion }))
    }
    "tool_result" =>
      Some(
        ToolResult({
          name: @jsonx.string(object, "tool_name"),
          content: @jsonx.string(object, "content"),
          is_error: @jsonx.bool(object, "is_error"),
        }),
      )
    "tool_call_decode_error" =>
      Some(
        ToolResult({
          name: @jsonx.string(object, "tool_name"),
          content: "error: \{@jsonx.string(object, "error")}",
          is_error: true,
        }),
      )
    "agent_finished" => Some(AgentFinished(@jsonx.string(object, "answer")))
    "agent_aborted" => Some(AgentAborted(@jsonx.string(object, "reason")))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "agent_setup_failed" =>
      Some(AgentError("agent setup failed: \{@jsonx.string(object, "error")}"))
    // A serve-mode turn that died with a non-cancellation error. Terminal for
    // the run even though the engine process lives on.
    "turn_failed" =>
      Some(AgentError("turn failed: \{@jsonx.string(object, "error")}"))
    // The engine rejected a command and keeps serving (no terminal event of its
    // own). Whether this should end a run depends on which command was rejected
    // — only the controller knows the active operation — so this stays a
    // non-terminal event the loop resolves (see `CommandRejected` handling).
    "command_error" => Some(CommandRejected(@jsonx.string(object, "error")))
    // Compaction lifecycle on a serve engine. `compaction_started` carries no
    // controller-visible state — the run is already shown busy — so it is left
    // to drop as an unknown event. The two outcomes are terminal for the
    // compaction run: success carries the summary (the new context) for a
    // preview, failure folds into the general agent-error category like a
    // failed turn.
    "compaction_finished" =>
      Some(CompactionFinished(@jsonx.string(object, "summary")))
    "compaction_failed" =>
      Some(AgentError("compaction failed: \{@jsonx.string(object, "error")}"))
    _ => None
  }
}
