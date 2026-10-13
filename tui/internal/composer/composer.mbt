///|
const MinTextRows : Int32 = 1

///|
/// Default cap on how many editable rows the composer grows to before it
/// scrolls instead of growing further.
pub const DefaultMaxTextRows : Int32 = 4

///|
/// Display width of the prompt prefix (`> `, `! `, or the `  ` continuation),
/// which is always two columns. Every wrapped composer row reserves this much.
const PromptWidth : Int32 = 2

///|
/// Editable content width for a composer rendered at `cols` terminal columns,
/// i.e. the room left once the two-column prompt prefix is reserved.
fn compute_content_width(cols~ : Int32) -> Int32 {
  let width = cols - PromptWidth
  width.max(1)
}

///|
/// Content width assumed before the composer has been laid out against a real
/// terminal. The renderer calls `Model::resize` on every frame, so this only
/// governs editing that happens before the first draw.
const DefaultContentWidth : Int32 = 78

///|
/// Semantic mode for the live composer.
///
/// `Input` is normal agent-steering text. `Shell` changes the first prompt to
/// `! ` and makes the submitted text become a shell command.
enum Mode {
  Input
  Shell
} derive(Eq)

///|
pub extend Mode with Eq::{equal, not_equal}

///|
let exclaimation_prefix : @displaytext.DisplayText = DisplayText("! ")

///|
fn Mode::prompt_prefix(self : Mode) -> @displaytext.DisplayText {
  match self {
    Input => @core.prompt_prefix
    Shell => exclaimation_prefix
  }
}

///|
/// Whether the composer is in normal agent-steering input mode.
pub fn Mode::is_input(self : Mode) -> Bool {
  self == Input
}

///|
/// Whether the composer is in shell mode, where submitted text runs as a
/// shell command and the first prompt shows `! `.
pub fn Mode::is_shell(self : Mode) -> Bool {
  self == Shell
}

///|
/// Mutable state model for the multiline composer.
///
/// The text, the cursor, soft wrapping and every editing operation belong to
/// the `Editor` from `moonbit-community/tui`. `Model` adds what is specific to
/// this prompt: the semantic mode with its `! ` marker, the two-column prompt
/// prefix that narrows the editable width, and the cap on how many rows the
/// composer shows before it scrolls.
struct Model {
  editor : @editor.Editor
  mut mode : Mode
  max_text_rows : Int32
  // The editable columns of a row and the rows shown, as of the last `resize`.
  mut content_width : Int32
  mut visible_cap : Int32
}

///|
/// Build a composer holding `text`, in input mode, with the cursor at the end.
/// `max_text_rows` caps how many rows it grows to.
pub fn Model::Model(
  text : String,
  max_text_rows~ : Int32 = DefaultMaxTextRows,
) -> Model {
  let max_text_rows = max_text_rows.max(MinTextRows)
  {
    editor: Editor(text~),
    mode: Input,
    max_text_rows,
    content_width: DefaultContentWidth,
    visible_cap: max_text_rows,
  }
}

///|
/// Clear the composer back to an empty input-mode prompt.
pub fn Model::reset(self : Model) -> Unit {
  self.replace("", mode=Input)
}

///|
/// Replace the text and the mode, putting the cursor at the end. Used to load
/// a recalled history entry.
pub fn Model::replace(self : Model, text : String, mode~ : Mode) -> Unit {
  self.editor.set_text(text)
  self.mode = mode
}

///|
/// The text being edited, without the shell-mode marker.
pub fn Model::text(self : Model) -> String {
  self.editor.text()
}

///|
/// The current semantic mode.
pub fn Model::mode(self : Model) -> Mode {
  self.mode
}

///|
/// The visible rows and the cursor among them, at the current size.
///
/// The editor keeps the last column of a row free for the cursor, so a row
/// holds one column less than the width it is laid out at. The composer lets a
/// row fill its whole content width, so it asks for one column more.
fn Model::layout(self : Model) -> @editor.Layout {
  self.editor.layout(width=self.content_width + 1, height=self.visible_cap)
}

///|
/// How many editable rows the composer currently shows: the wrapped rows of
/// the text, at least one and at most the cap.
pub fn Model::visible_text_rows(self : Model) -> Int32 {
  self.editor.height(width=self.content_width + 1, max=self.visible_cap)
}

///|
/// The text of visible row `row`, or `None` when there is no such row.
pub fn Model::visible_line(
  self : Model,
  row : Int32,
) -> @displaytext.DisplayText? {
  self.layout().rows.get(row).map(text => DisplayText(text))
}

///|
/// The prefix drawn before visible row `row`: the mode's prompt marker on the
/// very first row of the text, and two blank columns on every other row.
pub fn Model::input_prefix(
  self : Model,
  row : Int32,
) -> @displaytext.DisplayText {
  if self.layout().top + row == 0 {
    self.mode.prompt_prefix()
  } else {
    DisplayText("  ")
  }
}

///|
/// The visible row the cursor is on.
pub fn Model::cursor_row(self : Model) -> Int32 {
  self.layout().cursor.row
}

///|
/// Whether the cursor is on the first wrapped row of the text, where moving up
/// recalls history instead.
pub fn Model::cursor_at_first_visual_row(self : Model) -> Bool {
  let layout = self.layout()
  layout.top + layout.cursor.row == 0
}

///|
/// Whether the cursor is on the last wrapped row of the text, where moving
/// down recalls history instead.
pub fn Model::cursor_at_last_visual_row(self : Model) -> Bool {
  let layout = self.layout()
  layout.top + layout.cursor.row == layout.total - 1
}

///|
/// The cursor's display column on its row, counting the prompt prefix.
pub fn Model::cursor_offset(self : Model) -> Int32 {
  PromptWidth + self.layout().cursor.col
}

///|
/// Lay the composer out for a terminal `cols` columns wide. `max_rows` lowers
/// the cap on visible rows for this frame, for a terminal too short to show
/// them all.
pub fn Model::resize(self : Model, cols~ : Int32, max_rows? : Int32) -> Unit {
  self.visible_cap = match max_rows {
    Some(max_rows) => max_rows.clamp(min=MinTextRows, max=self.max_text_rows)
    None => self.max_text_rows
  }
  self.content_width = compute_content_width(cols~)
}

///|
/// Insert `text` at the cursor. It may contain line breaks.
pub fn Model::insert(self : Model, text : String) -> Unit {
  self.editor.insert(text)
}

///|
/// Insert text that came from the user: typed, or pasted.
///
/// A leading `!` typed into an empty input-mode prompt switches to shell mode
/// instead of being inserted.
pub fn Model::insert_user_text(self : Model, text : String) -> Unit {
  // Drop terminal-control bytes (pasted ANSI escapes, stray `\r`, tabs) before
  // they reach the model, so the live echo can never mutate the terminal and
  // the cursor math stays consistent with what is drawn.
  let text = @text.sanitize(text)
  if self.mode.is_input() && self.editor.is_empty() && text is ['!', .. rest] {
    self.mode = Shell
    self.editor.insert(rest)
  } else {
    self.editor.insert(text)
  }
}

///|
/// Delete the unit before the cursor. At the very start of the text there is
/// nothing to delete, and it leaves shell mode instead.
pub fn Model::delete_before(self : Model) -> Unit {
  if self.editor.position() == (0, 0) {
    self.mode = Input
  } else {
    self.editor.delete_before()
  }
}

///|
/// Delete the unit after the cursor.
pub fn Model::delete_after(self : Model) -> Unit {
  self.editor.delete_after()
}

///|
/// Move the cursor one unit left.
pub fn Model::move_left(self : Model) -> Unit {
  self.editor.move_left()
}

///|
/// Move the cursor one unit right.
pub fn Model::move_right(self : Model) -> Unit {
  self.editor.move_right()
}

///|
/// Move the cursor to the end of the word after it.
pub fn Model::move_word_right(self : Model) -> Unit {
  self.editor.move_word_right()
}

///|
/// Move the cursor to the start of the word before it.
pub fn Model::move_word_left(self : Model) -> Unit {
  self.editor.move_word_left()
}

///|
/// Move the cursor to the start of its logical line.
pub fn Model::move_home(self : Model) -> Unit {
  self.editor.move_home()
}

///|
/// Move the cursor to the end of its logical line.
pub fn Model::move_end(self : Model) -> Unit {
  self.editor.move_end()
}

///|
/// Delete from the start of the logical line up to the cursor.
pub fn Model::kill_before(self : Model) -> Unit {
  self.editor.kill_before()
}

///|
/// Delete from the cursor to the end of the logical line. At the end of a
/// line it deletes the line break, so the next line joins up, matching
/// readline/emacs kill-line.
pub fn Model::kill_after(self : Model) -> Unit {
  let (line, _) = self.editor.position()
  let lines = self.editor.text().split("\n").collect()
  if line > 0 && line == lines.length() - 1 && lines[line].is_empty() {
    // A trailing empty line has no forward content to kill; remove the line
    // itself by deleting the line break that precedes it.
    self.editor.delete_before()
  } else {
    self.editor.kill_after()
  }
}

///|
/// Move the cursor `delta` wrapped rows down, or up when negative, stopping at
/// the first or last row.
pub fn Model::move_vertical(self : Model, delta : Int32) -> Unit {
  // Laying out tells the editor the width its rows wrap at.
  ignore(self.layout())
  for _ in 0..<delta.abs() {
    let moved = if delta < 0 {
      self.editor.move_up()
    } else {
      self.editor.move_down()
    }
    if !moved {
      break
    }
  }
}
