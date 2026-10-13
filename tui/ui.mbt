///|
struct Ui {
  terminal : @term.Terminal
  config : Config
  composer : @composer.Model
  history : @history.History
  completion : CompletionState
  transcript : Array[@doc.Doc]
  // The transcript laid out for a screen `transcript_cols` wide: what the
  // transcript area scrolls over. It is extended as items are appended and
  // rebuilt only when the width changes, so a redraw does not lay the whole
  // transcript out again. Zero columns means not laid out yet.
  transcript_lines : Array[@term.Line]
  mut transcript_cols : Int32
  // Where the transcript is scrolled to. It follows new items until the user
  // scrolls up, and follows again once they scroll back to the end.
  scroll : @term.Scroll
  // The mouse selection over the transcript.
  selection : @term.Selection
  mut activity : @doc.Text?
  mut queued_inputs : Array[Input]
  mut status : @doc.Text
  mut notice : @doc.Text?
  commands : @task.Queue
  events : @aqueue.Queue[Result[Event, Error]]
  // Submitted inputs mid-flight: the composer was reset but the events have
  // not yet been delivered to the app's message queue (the submit helpers
  // await a redraw, and the internal `events` queue can hold several
  // submissions while the app loop is busy). Consumers that infer "the user
  // is not interacting" from an empty composer (see `Ui::input_idle`) must
  // treat this window as engaged, or they can act past input that is about
  // to arrive. A count, not a flag: rapid submits stack, and the app confirms
  // each delivery with `submission_delivered`.
  mut pending_submissions : Int32
}

///|
fn Ui::Ui(terminal : @term.Terminal, config : Config) -> Ui {
  let composer = @composer.Model("", max_text_rows=config.composer_max_rows)
  {
    terminal,
    config,
    composer,
    history: History(),
    completion: CompletionState(),
    transcript: [],
    transcript_lines: [],
    transcript_cols: 0,
    scroll: Scroll(stick_to_bottom=true),
    selection: Selection(),
    activity: None,
    queued_inputs: [],
    status: @doc.Text::plain(""),
    notice: None,
    commands: Queue(kind=Unbounded),
    events: Queue(kind=Unbounded),
    pending_submissions: 0,
  }
}

///|
async fn[T] run_ui_session(ui : Ui, body : async (Ui) -> T) -> T {
  @async.with_task_group() <| g => {
    g.spawn_bg(no_wait=true) <| () => { ui.commands.run() }
    // Draw the first frame before anything else can ask for a redraw.
    ui.commands.wait(() => ui.redraw())
    g.spawn_bg(no_wait=true) <| () => { ui.read_tty_events() }
    body(ui)
  }
}

///|
async fn Ui::put_event_result(self : Ui, result : Result[Event, Error]) -> Unit {
  self.events.put(result) catch {
    @aqueue.QueueAlreadyClosed => ()
    error => raise error
  }
}

///|
async fn Ui::read_tty_events(self : Ui) -> Unit {
  for ;; {
    let tty_event = self.terminal.read_event(
      esc_timeout_ms=self.config.esc_timeout_ms,
    ) catch {
      @async/io.ReaderClosed => {
        self.put_event_result(Ok(Quit))
        self.events.close()
        return
      }
      error => {
        self.put_event_result(Err(error))
        self.events.close()
        return
      }
    }
    let event = self.commands.wait(() => self.handle_tty_event(tty_event)) catch {
      error => {
        self.put_event_result(Err(error))
        self.events.close()
        return
      }
    }
    if event is Some(event) {
      self.put_event_result(Ok(event))
    }
  }
}

///|
/// Open a full-screen terminal session, run `body` with a live `Ui`, and always
/// restore the terminal afterwards. The session uses raw mode and the
/// alternate screen, requests the kitty keyboard "disambiguate" level
/// (gracefully ignored where unsupported) so modified keys the legacy encoding
/// cannot represent — Shift+Enter, Alt+F/Alt+B — arrive as distinct events,
/// and enables bracketed paste and mouse reporting. It draws the first frame,
/// then runs the command queue and the event reader for the duration of
/// `body`.
pub async fn[T] with_ui(
  config~ : Config = Config(),
  body : async (Ui) -> T,
) -> T {
  @term.with_terminal(mouse=true, terminal => {
    run_ui_session(Ui(terminal, config), body)
  })
}
