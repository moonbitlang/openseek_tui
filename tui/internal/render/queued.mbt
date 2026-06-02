// Render queued follow-up inputs as a compact, numbered preview block drawn
// above the composer. This is a surface-level rendering (not a logical `Doc`),
// so it lives here rather than as a `@core` projection.

///|
fn input_preview_text(input : @core.Input) -> String {
  // Defense-in-depth: queued previews are written straight to the terminal, so
  // strip any control bytes the input may carry (composer input is already
  // sanitized, but other sources — e.g. an initial CLI task — are not).
  let lines = @text.split_lines(@text.sanitize(input.text()))
  let first = @text.line_at(lines, 0)
  if lines.length() > 1 {
    first + " …"
  } else {
    first
  }
}

///|
fn queued_input_line(
  input : @core.Input,
  index~ : Int,
  cols~ : Int,
  indent~ : Int,
) -> @surface.Line {
  let marker = String::make(indent, ' ') + "\{index + 1}. "
  let prefix = input.prefix()
  @surface.Line::new([
    @surface.Span::new(marker, style=@doc.Style::dim().to_surface()),
    @surface.Span::new(prefix, style=@doc.Style::prompt().to_surface()),
    @surface.Span::new(
      @text.truncate_line(
        input_preview_text(input),
        cols - @text.display_width(marker) - @text.display_width(prefix),
      ),
      style=@doc.Style::dim().to_surface(),
    ),
  ])
}

///|
fn indented_dim_line(
  text : String,
  cols~ : Int,
  indent~ : Int,
) -> @surface.Line {
  @surface.Line::new([
    @surface.Span::new(
      String::make(indent, ' ') + @text.truncate_line(text, cols - indent),
      style=@doc.Style::dim().to_surface(),
    ),
  ])
}

///|
/// Render the queued-input preview block, bounded to `max_rows` rows so the
/// composer below it is never clipped on a short terminal.
///
/// The block is a header plus one row per input; when the inputs do not all fit
/// in the budget, the tail is collapsed into a `… N more` line. A budget too
/// small for even a header and one row drops the block entirely.
fn queued_input_rows(
  inputs : Array[@core.Input],
  cols~ : Int,
  indent~ : Int,
  max_rows~ : Int,
) -> Array[@surface.Line] {
  let rows : Array[@surface.Line] = []
  let count = inputs.length()
  if count == 0 || max_rows < 2 {
    return rows
  }
  rows.push(indented_dim_line("Queued follow-up inputs:", cols~, indent~))
  let item_budget = max_rows - 1
  if count <= item_budget {
    for index in 0..<count {
      rows.push(queued_input_line(inputs[index], index~, cols~, indent~))
    }
  } else {
    // Reserve the last row for the summary of everything that did not fit.
    let shown = item_budget - 1
    for index in 0..<shown {
      rows.push(queued_input_line(inputs[index], index~, cols~, indent~))
    }
    rows.push(indented_dim_line("… \{count - shown} more", cols~, indent~))
  }
  rows
}
