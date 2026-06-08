// Present a `runtime_update` event (the engine's coalesced `moon_check --watch`
// snapshot) for the human transcript and status bar.
//
// The engine emits one model-facing text blob: a `[moon_check update]` header, a
// `key=value` metadata preamble (events/id/cwd/command/status/seq/…), then the
// watcher's captured `moon check` output. The model needs all of it; a human
// reading the TUI does not. So the frontend strips the metadata and renders the
// watcher status plus the actual diagnostics as a tool-style item (the same
// `└`-indented detail layout as `tool_item`), flagged with a `↻` marker.

///|
/// Metadata keys the engine writes one-per-line as `key=value` ahead of the
/// watcher's captured output. These are dropped from the human view; `status` is
/// also lifted out for the status bar. Kept in sync with
/// `@moon_check`'s update-text format.
let runtime_metadata_keys : Array[String] = [
  "events", "id", "key", "cwd", "command", "status", "seq", "exit", "truncated",
  "max_output_chars", "restart_count", "restart_limit", "restart_reason",
]

///|
/// A `runtime_update` body parsed for display: the watcher `status` (lifted from
/// the metadata, `""` if absent) and the `diagnostics` lines that remain once the
/// `[moon_check update]` header and `key=value` preamble are stripped.
priv struct RuntimeUpdateView {
  status : String
  diagnostics : Array[String]
}

///|
/// Strip the model-facing metadata from a `runtime_update` body, keeping the
/// watcher status and the captured diagnostics. A line is metadata when it is the
/// `[moon_check update]` header or a `key=value` whose key is a known metadata key
/// (so a diagnostic line that merely contains `=`, e.g. `let buf = ...`, is kept,
/// since its key would carry a space and match no metadata key).
fn parse_runtime_update(content : String) -> RuntimeUpdateView {
  // A single update can carry several watcher sections (one per key), each with
  // its own `status=` line. Aggregate as running-if-any-running so a watcher
  // that is still checking is not masked by another that has stopped; with no
  // running watcher, keep the last status seen (e.g. "stopped").
  let mut last_status = ""
  let mut any_running = false
  let diagnostics : Array[String] = []
  for raw in content.split("\n") {
    let line = raw.to_owned()
    if line == "[moon_check update]" {
      continue
    }
    let is_metadata = if line.split_once("=") is Some((key, value)) {
      let key = key.to_owned()
      if runtime_metadata_keys.contains(key) {
        if key == "status" {
          last_status = value.to_owned()
          if last_status == "running" {
            any_running = true
          }
        }
        true
      } else {
        false
      }
    } else {
      false
    }
    if !is_metadata {
      diagnostics.push(line)
    }
  }
  let status = if any_running { "running" } else { last_status }
  { status, diagnostics }
}

///|
/// Build the tool-style transcript item for a parsed `runtime_update`: a
/// `moon_check`/status title with the captured diagnostics as compacted detail
/// lines, rendered under the `↻` notice marker.
fn runtime_item(update : RuntimeUpdateView) -> @ui.TranscriptItem {
  let title = if update.status.is_empty() {
    "moon_check"
  } else {
    "moon_check · \{update.status}"
  }
  let body = update.diagnostics.join("\n")
  Notice(
    ToolCall(
      @doc.Text::plain(title),
      details=detail_texts(compact_lines(body, ToolOutputLineLimit)),
    ),
  )
}

///|
/// The status-bar text for the latest watcher state, or `""` when no watcher
/// update has been seen yet (so the segment is skipped).
fn watcher_segment_text(status : String) -> String {
  if status.is_empty() {
    ""
  } else {
    "moon_check \{status}"
  }
}
