///|
test "viewport remembers stale frame footprint after resize invalidates frame" {
  let viewport = Viewport::{
    size: TerminalSize(rows=10, cols=80),
    size_source: Ioctl,
    geometry: @geometry.Geometry::new(top=6, height=4),
    cache: Drawn(
      @surface.Surface::new(
        width=80,
        rows=[
          @surface.Line::new([]),
          @surface.Line::new([]),
          @surface.Line::new([]),
          @surface.Line::new([]),
          @surface.Line::new([]),
        ],
        cursor=@surface.Cursor::new(row=1, col=0),
      ),
    ),
  }
  viewport.set_size(TerminalSize(rows=8, cols=40))
  let (stale_top, stale_height) = match viewport.cache {
    Stale(top~, height~) => (top, height)
    _ => (-1, -1)
  }
  inspect(stale_top, content="6")
  inspect(stale_height, content="5")
  inspect(viewport.top(), content="5")
  inspect(
    viewport.cache.placed_surface(live_top=viewport.top()) is None,
    content="true",
  )
}

///|
test "enter geometry keeps ioctl size when CPR fits" {
  let geometry = choose_enter_geometry_for_cursor(
    TerminalSize(rows=24, cols=80),
    cursor_row=23,
    cursor_col=80,
  )
  inspect(geometry.source is Ioctl, content="true")
  inspect(geometry.size.rows(), content="24")
  inspect(geometry.size.cols(), content="80")
  inspect(geometry.cursor_row, content="23")
}

///|
test "enter geometry uses protocol size when CPR is outside ioctl" {
  let geometry = choose_enter_geometry_for_cursor(
    TerminalSize(rows=24, cols=80),
    cursor_row=40,
    cursor_col=120,
    protocol_size=TerminalSize(rows=50, cols=160),
  )
  inspect(geometry.source is Protocol, content="true")
  inspect(geometry.size.rows(), content="50")
  inspect(geometry.size.cols(), content="160")
  inspect(geometry.cursor_row, content="40")
}

///|
test "enter geometry rejects CPR outside ioctl when protocol probe fails" {
  try
    choose_enter_geometry_for_cursor(
      TerminalSize(rows=24, cols=80),
      cursor_row=40,
      cursor_col=120,
    )
  catch {
    Failure::Failure(message) => {
      inspect(message.contains("protocol probe failed"), content="true")
      inspect(message.contains("CPR cursor=40x120"), content="true")
      inspect(message.contains("ioctl=24x80"), content="true")
    }
    _ => fail("unexpected geometry error")
  } noraise {
    _ => fail("mismatched geometry accepted")
  }
}

///|
test "terminal cursor comparison includes viewport top" {
  let rows = [@surface.Line::new([]), @surface.Line::new([])]
  let left = @surface.Surface::new(
    width=10,
    rows~,
    cursor=@surface.Cursor::new(row=1, col=3),
  )
  let same = @surface.Surface::new(
    width=10,
    rows~,
    cursor=@surface.Cursor::new(row=0, col=3),
  )
  let moved_row = @surface.Surface::new(
    width=10,
    rows~,
    cursor=@surface.Cursor::new(row=1, col=3),
  )
  let moved_col = @surface.Surface::new(
    width=10,
    rows~,
    cursor=@surface.Cursor::new(row=0, col=4),
  )
  let left = PlacedSurface::{ surface: left, top: 4 }
  let same = PlacedSurface::{ surface: same, top: 5 }
  let moved_row = PlacedSurface::{ surface: moved_row, top: 5 }
  let moved_col = PlacedSurface::{ surface: moved_col, top: 5 }
  inspect(left.same_terminal_cursor(same), content="true")
  inspect(left.same_terminal_cursor(moved_row), content="false")
  inspect(left.same_terminal_cursor(moved_col), content="false")
}
