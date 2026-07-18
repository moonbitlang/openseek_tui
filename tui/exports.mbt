// The semantic model types live in tui/core; re-export them so the tui package
// remains the single public facade for consumers (e.g. cmd/tui) that construct
// inputs and transcript items.

///|
pub using @core {type Input, type Event, type ToolStatus, type TranscriptItem}

///|
pub using @completion {type CompletionItem}

///|
pub using @slash {type SlashCommandSpec}

///|
/// Set or clear the transient activity label and redraw.
#deprecated("use Ui::set_live_view — it sets the whole live view with a single redraw")
pub async fn Ui::set_activity(self : Self, activity : @doc.Text?) -> Unit {
  self.commands.wait(() => {
    self.activity = activity
    self.redraw()
  })
}

///|
/// Replace the queued-inputs preview (copied defensively) and redraw.
#deprecated("use Ui::set_live_view — it sets the whole live view with a single redraw")
pub async fn Ui::set_queued_inputs(self : Self, inputs : Array[Input]) -> Unit {
  self.commands.wait(() => {
    self.queued_inputs = inputs.copy()
    self.redraw()
  })
}

///|
/// Set the persistent status line and redraw.
#deprecated("use Ui::set_live_view — it sets the whole live view with a single redraw")
pub async fn Ui::set_status(self : Self, status : @doc.Text) -> Unit {
  self.commands.wait(() => {
    self.status = status
    self.redraw()
  })
}
