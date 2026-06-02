///|
/// Display width of `text` in terminal cells, accounting for East-Asian wide
/// characters.
pub fn display_width(text : String) -> Int {
  @unicodewidth.str_width(text)
}

///|
/// Truncate `text` to fit within `cols` display cells, appending an ellipsis
/// (`…`) when content is dropped. Returns `""` for `cols <= 0` and the input
/// unchanged when it already fits. Breaks on grapheme boundaries.
pub fn truncate_line(text : String, cols : Int) -> String {
  if cols <= 0 {
    ""
  } else if display_width(text) <= cols {
    text
  } else {
    let suffix = "…"
    let suffix_width = @unicodewidth.str_width(suffix)
    let content_cols = cols - suffix_width
    let builder = StringBuilder()
    let mut width = 0
    for grapheme in @grapheme.grapheme_iter(text) {
      let next_width = @unicodewidth.str_width(grapheme)
      if width + next_width > content_cols {
        break
      }
      builder.write_stringview(grapheme)
      width = width + next_width
    }
    builder.write_string(suffix)
    builder.to_string()
  }
}

///|
/// Split `text` into lines on any line-ending form, always returning at least
/// one element.
///
/// `\r\n` is a single grapheme cluster (Unicode CR×LF) and a lone `\r` is its
/// own, so iterating graphemes splits CRLF/CR/LF alike — no stray `\r` is left
/// on a line to be mishandled downstream (it would otherwise become an extra
/// blank row once the doc renderer treats it as a break).
pub fn split_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  let mut current = StringBuilder()
  for grapheme in @grapheme.grapheme_iter(text) {
    let g = grapheme.to_owned()
    if g == "\n" || g == "\r\n" || g == "\r" {
      lines.push(current.to_string())
      current = StringBuilder()
    } else {
      current.write_string(g)
    }
  }
  lines.push(current.to_string())
  lines
}

///|
/// Whether a grapheme is a C0 control character or DEL.
fn is_control(grapheme : String) -> Bool {
  match grapheme.get_char(0) {
    Some(c) => {
      let code = c.to_int()
      code < 0x20 || code == 0x7f
    }
    None => false
  }
}

///|
/// Terminal tab stop width: tabs expand to the next multiple of this.
const TabWidth : Int = 8

///|
/// Normalize user-provided text so it can be echoed live — in the composer or
/// queued previews — without mutating the terminal or confusing the cursor math.
///
/// Carriage returns become newlines so pasted line breaks survive; every other
/// C0 control and `DEL` is dropped — including `ESC`, and therefore every ANSI
/// escape sequence that could move or clear the cursor. Tabs are expanded to
/// spaces at the next `TabWidth` stop so the stored width matches what is drawn
/// (a raw `\t` counts as one column but renders as a jump). `\n` is preserved.
pub fn sanitize(text : String) -> String {
  let builder = StringBuilder()
  // Display column within the current line, used to place tab stops.
  let mut col = 0
  for grapheme in @grapheme.grapheme_iter(text) {
    let g = grapheme.to_owned()
    // `\r\n` is a single grapheme cluster (Unicode CR×LF); a lone `\r` is its
    // own cluster. Either way, keep the line break as a plain `\n` and drop the
    // raw CR, which would otherwise return the cursor to column 1.
    if g == "\r" || g == "\r\n" || g == "\n" {
      builder.write_string("\n")
      col = 0
    } else if g == "\t" {
      let spaces = TabWidth - col % TabWidth
      builder.write_string(String::make(spaces, ' '))
      col = col + spaces
    } else if !is_control(g) {
      builder.write_string(g)
      col = col + display_width(g)
    }
    // else: ESC, DEL, and the remaining C0 controls are dropped.
  }
  builder.to_string()
}

///|
/// The line at `index`, or `""` when `index` is out of range.
pub fn line_at(lines : Array[String], index : Int) -> String {
  if index < 0 || index >= lines.length() {
    ""
  } else {
    lines[index]
  }
}

///|
/// Number of grapheme clusters in `text`.
pub fn grapheme_count(text : String) -> Int {
  @grapheme.graphemes(text).length()
}

///|
/// Slice `text` by grapheme cluster index over `[start, end)`. Bounds are
/// clamped into range, so out-of-range indices never error.
pub fn grapheme_slice(text : String, start : Int, end : Int) -> String {
  let graphemes = @grapheme.graphemes(text)
  let length = graphemes.length()
  let start = start.clamp(min=0, max=length)
  let end = end.clamp(min=start, max=length)
  graphemes[start:end].to_string()
}
