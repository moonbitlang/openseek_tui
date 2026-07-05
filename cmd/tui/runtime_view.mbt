///|
/// Render a runtime notice stored in session history. Runtime notices are
/// already model-facing text, so the TUI presents them without tool-specific
/// parsing.
fn runtime_notice_item(content : String) -> @ui.TranscriptItem {
  Notice(
    ToolCall(
      @doc.Text::plain("runtime notice"),
      details=detail_texts(compact_lines(content, ToolOutputLineLimit)),
    ),
  )
}
