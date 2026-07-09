///|
priv struct LogicLine {
  display : @displaytext.DisplayText
  mut row_start : Int
  mut row_end : Int
}

///|
fn split_logical_lines(text : StringView) -> Array[LogicLine] {
  [
    for display in @displaytext.split_lines(text) => LogicLine::new(display)
  ]
}

///|
fn LogicLine::new(display : @displaytext.DisplayText) -> LogicLine {
  { display, row_start: 0, row_end: 0 }
}

///|
fn LogicLine::text(self : LogicLine) -> String {
  self.display.text()
}

///|
fn LogicLine::is_empty(self : LogicLine) -> Bool {
  self.display.start() == self.display.end()
}

///|
fn LogicLine::position_at_display_column(
  self : LogicLine,
  column~ : Int,
) -> @displaytext.TextualPosition {
  self.display.textual_position_at_or_before(
    @displaytext.DisplayPosition::new(column~),
  )
}

///|
fn LogicLine::display_column(
  self : LogicLine,
  position~ : @displaytext.TextualPosition,
) -> Int {
  self.display.display_position(position).column()
}

///|
fn LogicLine::unit_text_at(
  self : LogicLine,
  position~ : @displaytext.TextualPosition,
) -> StringView? {
  if self.display.next(position) is Some(next) {
    Some(self.display.view(position, next))
  } else {
    None
  }
}

///|
fn LogicLine::unit_text_before(
  self : LogicLine,
  position~ : @displaytext.TextualPosition,
) -> StringView? {
  if self.display.prev(position) is Some(previous) {
    Some(self.display.view(previous, position))
  } else {
    None
  }
}

///|
fn join_logical_lines(logical_lines : Array[LogicLine]) -> String {
  let builder = StringBuilder()
  for index, line in logical_lines {
    if index > 0 {
      builder <+ "\n"
    }
    builder <+ "\{line.text()}"
  }
  builder.to_string()
}

///|
fn splice_logical_lines(
  lines : Array[LogicLine],
  start~ : Int,
  delete_count~ : Int,
  inserted~ : Array[LogicLine],
) -> Array[LogicLine] {
  let start = start.clamp(min=0, max=lines.length())
  let delete_count = delete_count.max(0)
  let tail_start = (start + delete_count).clamp(min=start, max=lines.length())
  [..lines[:start], ..inserted, ..lines[tail_start:]]
}
