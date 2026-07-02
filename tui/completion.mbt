///|
priv struct CompletionMenu {
  key : String
  items : Array[@completion.CompletionItem]
}

///|
/// Mutable state backing the input-completion menu: `key` identifies the
/// current menu context (so the selection resets when it changes), `selected`
/// is the highlighted item index, and `dismissed` records an Esc dismissal.
priv struct CompletionState {
  mut key : String
  mut selected : Int
  mut dismissed : Bool
}

///|
fn CompletionState::new() -> CompletionState {
  { key: "", selected: 0, dismissed: false }
}

///|
/// Forget the current menu context, clearing the selection and any dismissal.
fn CompletionState::reset(self : CompletionState) -> Unit {
  self.key = ""
  self.selected = 0
  self.dismissed = false
}

///|
/// The composer's text when it holds a single-line entry in input mode — the
/// precondition shared by completion, slash-command parsing, and slash-entry
/// detection. None in shell mode or for multi-line input, neither of which is a
/// slash context.
fn single_line_input_text(composer : @composer.Model) -> String? {
  guard composer.mode().is_input() else { return None }
  let text = composer.text()
  guard !text.contains("\n") else { return None }
  Some(text)
}

///|
fn completion_menu_for_composer(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
) -> CompletionMenu? {
  guard single_line_input_text(composer) is Some(text) else { return None }
  guard text.strip_prefix("/") is Some(rest) else { return None }
  let rest = rest.to_owned()
  // A doubled leading slash (`//`, `//e`) is not a command-name prefix: the
  // filter would otherwise match a command by its `/`-prefixed display label
  // (e.g. `/` matches `/exit`), so reject it rather than show a menu.
  if rest.has_prefix("/") {
    return None
  }
  // Complete the command name from the configured set. Past the command name
  // there is nothing to complete: the configured commands take no arguments.
  if @slash.has_arguments(rest) {
    return None
  }
  if commands.is_empty() {
    return None
  }
  Some({
    key: "command:\{rest.to_lower()}",
    items: @completion.completion_item_matches(
      commands.completion_items(),
      rest,
    ),
  })
}

///|
/// The slash command syntactically present in the composer, if any.
///
/// Returns None when no slash commands are configured, so a consumer that has
/// not opted into the feature keeps submitting `/`-prefixed lines as ordinary
/// input. When the feature is enabled, parsing is independent of whether the
/// specific name is registered — an unknown command still dispatches so the
/// handler reports it rather than the agent receiving it as a prompt or it
/// being swallowed as a no-completion notice.
fn slash_command_invocation_for_composer(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
) -> @slash.SlashCommandInvocation? {
  if commands.is_empty() {
    return None
  }
  guard single_line_input_text(composer) is Some(text) else { return None }
  @slash.SlashCommandInvocation::parse(text)
}

///|
fn Ui::completion_menu(self : Self) -> CompletionMenu? {
  completion_menu_for_composer(self.config.slash_commands, self.composer)
}

///|
fn Ui::sync_completion_menu(self : Self) -> Unit {
  match self.completion_menu() {
    Some(menu) => {
      if menu.key != self.completion.key {
        self.completion.key = menu.key
        self.completion.selected = 0
      }
      if menu.items.length() == 0 {
        self.completion.selected = 0
      } else if self.completion.selected >= menu.items.length() {
        self.completion.selected = menu.items.length() - 1
      }
    }
    None => self.completion.reset()
  }
}

///|
/// Whether the terminal is tall enough to draw the completion menu. A menu that
/// cannot be rendered must not capture keys, so this gates `completion_menu_open`
/// (and the Enter decision) on the same row budget the renderer uses.
fn Ui::completion_menu_visible(self : Self) -> Bool {
  guard self.viewport is Some(viewport) else { return true }
  @render.completion_menu_fits(max_rows=viewport.rows())
}

///|
fn Ui::completion_menu_open(self : Self) -> Bool {
  !self.completion.dismissed &&
  self.completion_menu_visible() &&
  self.completion_menu() is Some(_)
}

///|
async fn Ui::redraw_after_completion_selection(self : Self) -> Unit {
  self.notice = None
  self.redraw()
}

///|
async fn Ui::move_completion_selection(self : Self, delta : Int) -> Unit {
  let len = match self.completion_menu() {
    Some(menu) => menu.items.length()
    None => 0
  }
  if len > 0 {
    if delta < 0 {
      self.completion.selected = if self.completion.selected <= 0 {
        len - 1
      } else {
        self.completion.selected - 1
      }
    } else {
      self.completion.selected = if self.completion.selected + 1 >= len {
        0
      } else {
        self.completion.selected + 1
      }
    }
  }
  self.redraw_after_completion_selection()
}

///|
/// The canonical `/name arguments` text for a dispatched slash command, used
/// for history so recall repeats what actually ran rather than the half-typed
/// prefix in the composer.
fn slash_command_text(name~ : String, arguments~ : String) -> String {
  if arguments.is_empty() {
    "/\{name}"
  } else {
    "/\{name} \{arguments}"
  }
}

///|
async fn Ui::submit_slash_command(
  self : Self,
  name~ : String,
  arguments~ : String,
) -> Event? {
  // Record what ran, not `composer.text()`: accepting a completion can dispatch
  // arguments that differ from the typed prefix, and recalling the prefix would
  // re-select the first match and run a different command.
  let text = slash_command_text(name~, arguments~)
  self.history.push(@history.Entry::new(text, self.composer.mode()))
  // Mid-flight until the app's queue receives the event (the redraw below
  // awaits); see `pending_submissions`.
  self.pending_submissions += 1
  self.composer.reset()
  self.history.reset_navigation()
  self.notice = None
  self.completion.reset()
  self.redraw()
  Some(SlashCommand(name~, arguments~))
}

///|
/// The composer text that accepting the highlighted menu item produces: a
/// completed command name (`/comp` → `/compact`). None when the menu is empty
/// (e.g. an unknown command), so there is nothing to accept. The candidates are
/// command names from the configured spec — trusted text, so no sanitization is
/// needed here.
fn completion_acceptance_text(menu : CompletionMenu, selected : Int) -> String? {
  guard menu.items.get(selected) is Some(item) else { return None }
  Some("/\{item.insert_text()}")
}

///|
/// Accept the highlighted completion into the composer without submitting; Tab
/// completes the text where Enter would submit it.
async fn Ui::accept_completion(self : Self) -> Event? {
  guard self.completion_menu() is Some(menu) else { return None }
  guard completion_acceptance_text(menu, self.completion.selected) is Some(text) else {
    return None
  }
  self.composer.replace(text, mode=self.composer.mode())
  self.redraw_after_text_change()
  None
}

///|
/// Whether the composer holds a slash-command entry: the feature is enabled and
/// the single-line input begins with `/`. Such a line is completed or dispatched
/// on Enter, never queued as a prompt — not even a lone `/`, which is not yet a
/// valid invocation but must not be queued as literal text.
fn composer_is_slash_entry(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
) -> Bool {
  if commands.is_empty() {
    return false
  }
  guard single_line_input_text(composer) is Some(text) else { return false }
  text.has_prefix("/")
}

///|
/// What pressing Enter in the composer should do, decided purely from the
/// command set, the composer text, and the menu state.
priv enum EnterDecision {
  /// Dispatch a slash command with these arguments.
  RunSlashCommand(name~ : String, arguments~ : String)
  /// Submit the composer text as ordinary input (prompt or shell command).
  SubmitInput
  /// The menu is open but nothing matches; show a notice and do nothing.
  NoCompletionMatch
}

///|
/// Decide what Enter does. Accepting a highlighted command name dispatches it
/// with no arguments — the handler runs it or rejects it. An unknown command
/// still dispatches so the handler can reject it, and anything else is submitted
/// as ordinary input.
///
/// `menu_visible` is false when the terminal is too short to draw the menu, in
/// which case it must not influence the decision even though it is logically
/// open.
fn ui_enter_decision(
  commands : @slash.SlashCommands,
  composer : @composer.Model,
  completion : CompletionState,
  menu_visible~ : Bool,
) -> EnterDecision {
  let menu = if completion.dismissed || !menu_visible {
    None
  } else {
    completion_menu_for_composer(commands, composer)
  }
  let invocation = slash_command_invocation_for_composer(commands, composer)
  guard menu is Some(menu) else {
    return match invocation {
      Some(inv) => RunSlashCommand(name=inv.name(), arguments=inv.arguments())
      // No menu and nothing to dispatch. A slash entry that does not parse into
      // a command (a lone `/`, `/ `, after the menu was dismissed or is too
      // short to draw) must not be submitted as a prompt — that would leak
      // malformed slash input into the agent conversation. Leave it as a
      // no-match instead; only genuine non-slash input is submitted.
      None =>
        if composer_is_slash_entry(commands, composer) {
          NoCompletionMatch
        } else {
          SubmitInput
        }
    }
  }
  // Require a typed command name before accepting the highlighted item. A bare
  // `/` opens a menu of every command with index 0 highlighted, and Enter there
  // must not silently run the first one (e.g. `/exit`, quitting the app) — it is
  // an unfinished entry, not a chosen command.
  guard invocation is Some(invocation) else { return NoCompletionMatch }
  // Command-name menu: accept the highlighted command and dispatch it with no
  // arguments (the only commands take none); the handler runs or rejects it.
  match menu.items.get(completion.selected) {
    Some(item) => RunSlashCommand(name=item.insert_text(), arguments="")
    // Nothing matches the typed name: dispatch it (an unknown command) so the
    // handler can reject it instead of swallowing it as a notice.
    None =>
      RunSlashCommand(name=invocation.name(), arguments=invocation.arguments())
  }
}
