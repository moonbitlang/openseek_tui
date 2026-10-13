///|
fn Ui::composer_surface(
  self : Ui,
  cols~ : Int32,
  rows~ : Int32,
) -> @surface.Surface {
  let completion = match self.completion_menu() {
    Some(menu) if !self.completion.dismissed =>
      @completion.Model::open(
        items=menu.items,
        selected=self.completion.selected,
      )
    _ => @completion.Model::closed()
  }
  @render.composer_surface(
    self.composer,
    activity=self.activity,
    queued_inputs=self.queued_inputs,
    completion~,
    status=self.status,
    notice=self.notice,
    cols~,
    max_rows=rows,
  )
}

///|
/// Convert a laid-out row to the terminal library's line type. The two differ
/// only in vocabulary: the same text in the same colors.
fn to_line(line : @surface.Line) -> @term.Line {
  Line(
    line
    .spans()
    .map(span => {
      let style = span.style()
      Span(
        span.text(),
        style=Style(
          fg=style.foreground,
          bg=style.background,
          underline=style.underline,
        ),
      )
    }),
  )
}

///|
/// Lay out one transcript item, prefixed with a blank separator row so items
/// are visually spaced apart (matching the Codex TUI). The separator is plain,
/// outside any item background block.
fn item_lines(doc : @doc.Doc, cols~ : Int32) -> Array[@term.Line] {
  [Line([]), ..doc.layout(width=cols).map(to_line)]
}

///|
/// Make `transcript_lines` hold the whole transcript laid out for `cols`
/// columns. Nothing to do unless the width changed since it was last built.
fn Ui::layout_transcript(self : Self, cols~ : Int32) -> Unit {
  if cols == self.transcript_cols {
    return
  }
  self.transcript_lines.clear()
  for doc in self.transcript {
    self.transcript_lines.append(item_lines(doc, cols~))
  }
  self.transcript_cols = cols
}

///|
/// Draw the whole screen: the transcript in a scrolling area on top, and the
/// live input area — queued inputs, activity, composer, completion menu and
/// status — in as many rows as it needs at the bottom.
async fn Ui::redraw(self : Self) -> Unit {
  let size = self.terminal.size()
  let frame = @term.Frame(width=size.width, height=size.height)
  let surface = self.composer_surface(cols=size.width, rows=size.height)
  let rows = @term.Layout::vertical([Fill(1), Length(surface.height())])
  guard rows.split(frame.area()) is [transcript, live] else { return }
  self.layout_transcript(cols=size.width)
  frame.lines(
    transcript,
    self.transcript_lines,
    scroll=self.scroll,
    selection=self.selection,
  )
  let rows = Array::makei(surface.height(), row => to_line(surface.line_at(row)))
  frame.lines(live, rows)
  frame.set_cursor(live, row=surface.cursor().row(), col=surface.cursor().col())
  self.terminal.draw(frame)
}

///|
/// Append a styled `Doc` to the transcript and redraw. Runs on the command
/// queue so it serializes with other redraws.
async fn Ui::append_transcript(self : Self, doc : @doc.Doc) -> Unit {
  self.commands.wait(() => {
    self.transcript.push(doc)
    // Extend the laid-out transcript in place. Before the first draw there is
    // no width to lay it out for; the draw builds it from `transcript`.
    if self.transcript_cols > 0 {
      self.transcript_lines.append(item_lines(doc, cols=self.transcript_cols))
    }
    self.redraw()
  })
}

///|
/// Project a semantic `TranscriptItem` to a `Doc` and append it to the
/// transcript via `append_transcript`.
pub async fn Ui::append_item(self : Self, item : TranscriptItem) -> Unit {
  self.append_transcript(@doc.ToDoc::to_doc(item))
}

///|
/// The terminal width in columns. Lets callers fit transient content (e.g. a
/// streaming tail preview) to the row the renderer will clip it to.
pub fn Ui::columns(self : Self) -> Int32 {
  self.terminal.size().width
}

///|
/// Whether the user is not interacting with the input surface at all: no
/// draft text, plain input mode, and no submitted event still in flight
/// toward the app's queue. Shell mode counts as engaged even with an empty
/// buffer — a user sitting at a bare `! ` prompt is mid-composition — and so
/// does the reset-to-delivery window of a just-pressed Enter (the submit
/// helpers await a redraw between clearing the composer and returning the
/// event, so an empty composer alone can lie about pending input). Lets a
/// scheduler (e.g. `/loop`) avoid starting a turn under, or ahead of, the
/// user — the composer is private to the UI, so the update loop cannot see
/// any of this directly.
pub fn Ui::input_idle(self : Self) -> Bool {
  self.pending_submissions == 0 &&
  self.composer.text().is_empty() &&
  self.composer.mode().is_input()
}

///|
/// The app's event reader confirms one submitted event has reached its
/// message queue and is visible to queue drains. Called once per delivered
/// *submission* event (a prompt, queued input, or slash command) — rapid
/// submits can stack several in the UI's internal event queue while the app
/// loop is busy, so deliveries and submissions must pair one-to-one. The
/// floor guards a spurious call; it must never mask a real pending submit.
pub fn Ui::submission_delivered(self : Self) -> Unit {
  self.pending_submissions = (self.pending_submissions - 1).max(0)
}

///|
/// Replace the live view around the composer — the persistent status line
/// below it, the transient activity line above it (`None` hides it; it never
/// enters the transcript), and the queued-inputs preview (copied defensively)
/// — then redraw the frame once.
///
/// The whole view is set together because that is how an update loop works:
/// it derives every live element from its state each turn. Per-field setters
/// would queue one full-frame repaint each — three per loop turn — which
/// during a streaming burst is the difference between a calm frame and a
/// flickering one. Transient input notices may temporarily override the
/// status display until the next input event.
pub async fn Ui::set_live_view(
  self : Self,
  status~ : @doc.Text,
  activity~ : @doc.Text?,
  queued_inputs~ : Array[Input],
) -> Unit {
  self.commands.wait(() => {
    self.status = status
    self.activity = activity
    self.queued_inputs = queued_inputs.copy()
    self.redraw()
  })
}
