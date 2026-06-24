// The decoded, in-memory form of the engine's JSONL event stream. The `openseek`
// engine writes one JSON object per line to stdout; `decode_event` (see
// `decode.mbt`) maps each into an `AgentEvent`. The `cmd/tui` rendering loop
// pattern-matches on these types and never touches the wire format.

///|
/// Token accounting decoded from a `usage` event.
///
/// The engine reports prompt/completion/cache counts; only the derived total
/// (`prompt + completion`) is shown in the status line, so that is all we keep.
pub(all) struct UsageInfo {
  total_tokens : Int
}

///|
/// The result of a tool call after the engine ran it.
pub(all) struct ToolResultEvent {
  name : String
  content : String
  is_error : Bool
}

///|
/// Decoded agent progress events, one per JSONL line from the engine.
///
/// Variant names mirror the engine's wire `event` strings (`agent_step` →
/// `AgentStep`, `tool_result` → `ToolResult`, …) so decoding is a near-identity
/// map. `AgentError` is the exception: it carries both the engine's
/// `agent_setup_failed` and the TUI-synthesized "engine exited without a result"
/// error, so it stays a general category rather than a single wire event.
///
/// Terminal events (`AgentFinished`, `AgentAborted`, `MaxStepsExhausted`,
/// `AgentError`) leave the agent idle so the message loop can drain the next
/// queued input.
pub(all) enum AgentEvent {
  AgentStep
  AssistantDelta(String)
  ReasoningDelta(String)
  ReasoningMessage(String)
  SteerApplied(@agent_runtime.SteerInput)
  SteerDropped(String)
  AssistantMessage(String)
  RuntimeUpdate(String)
  SessionError(String)
  Usage(UsageInfo)
  ToolResult(ToolResultEvent)
  AgentFinished(String)
  AgentAborted(String)
  MaxStepsExhausted
  AgentError(String)
  // The engine rejected a control command and keeps serving (no terminal event
  // of its own). It carries no identity for which command was rejected, so the
  // loop only surfaces it — it never ends the run in flight, which a delayed
  // rejection of an earlier command must not do.
  CommandRejected(String)
  // The serve engine finished compacting the conversation: a terminal event for
  // the controller's compaction run. Carries the summary the engine appended to
  // the durable session — now the conversation's context — so the controller can
  // preview it.
  CompactionFinished(String)
}
