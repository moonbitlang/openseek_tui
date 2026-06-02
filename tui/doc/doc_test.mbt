///|
test "doc layout wraps styled text by display width" {
  inspect(
    @doc.Doc::Doc([@doc.Text::plain("abcdef")])
    .layout(width=3)
    .map(line => line.text())
    .join("|"),
    content="abc|def",
  )
  inspect(
    @doc.Doc::Doc([@doc.Text::plain("你好世界")])
    .layout(width=4)
    .map(line => line.text())
    .join("|"),
    content="你好|世界",
  )
}

///|
test "layout expands tabs to the next stop and drops other control chars" {
  // `\t` expands to spaces up to the next 8-column tab stop so following text
  // is not shoved to a terminal tab stop we never accounted for.
  inspect(
    @doc.Doc::Doc([@doc.Text::plain("a\tb")])
    .layout(width=40)
    .map(line => line.text())
    .join("|"),
    content="a       b",
  )
  inspect(
    @doc.Doc::Doc([@doc.Text::plain("abcdef\tg")])
    .layout(width=40)
    .map(line => line.text())
    .join("|"),
    content="abcdef  g",
  )
  // `\r\n` (a single grapheme cluster) and a lone `\r` are line breaks, so they
  // split rows instead of being dropped — CRLF content keeps its lines.
  inspect(
    @doc.Doc::Doc([@doc.Text::plain("x\r\ny")])
    .layout(width=40)
    .map(line => line.text())
    .join("|"),
    content="x|y",
  )
  // Other C0 controls (here `ESC`) are dropped entirely.
  inspect(
    @doc.Doc::Doc([@doc.Text::plain("x\u{1b}y")])
    .layout(width=40)
    .map(line => line.text())
    .join("|"),
    content="xy",
  )
}

///|
test "split_lines splits CRLF and CR so no stray carriage return remains" {
  // The trailing `\r` the old splitter left on the first block would make
  // `wrap` emit an extra blank row, so each split block must lay out to exactly
  // one row.
  let blocks = @doc.Text::plain("a\r\nb").split_lines()
  inspect(blocks.length(), content="2")
  let mut total_rows = 0
  for block in blocks {
    total_rows = total_rows + @doc.Doc::Doc([block]).layout(width=40).length()
  }
  inspect(total_rows, content="2")
}

///|
test "doc constructors copy mutable arrays" {
  let spans = [@doc.Span::plain("a")]
  let text = @doc.Text::Text(spans)
  spans.push(@doc.Span::plain("b"))
  inspect(
    @doc.Doc::Doc([text]).layout(width=20).map(line => line.text()).join("|"),
    content="a",
  )
  let texts = [@doc.Text::plain("a")]
  let doc = @doc.Doc::Doc(texts)
  texts.push(@doc.Text::plain("b"))
  inspect(doc.layout(width=20).map(line => line.text()).join("|"), content="a")
}
