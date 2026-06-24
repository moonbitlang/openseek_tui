///|
test "submitted input marks prompt and shell command" {
  let input = @composer.Model::new("")
  let shell = @composer.Model::new("")
  shell.insert_user_text("!")
  assert_true(submitted_input("hello", input.mode()) == Prompt("hello"))
  assert_true(submitted_input("pwd ", shell.mode()) == Command("pwd"))
  assert_true(submitted_input("", shell.mode()) == Command(""))
}

///|
test "completion menu only opens for single-line slash input contexts" {
  let slash = @composer.Model::new("")
  slash.insert_user_text("/co")
  guard completion_menu_for_composer(command_specs(), slash)
    is Some(command_menu) else {
    fail("expected command completion menu")
  }
  assert_eq(command_menu.key, "command:co")
  assert_eq(command_menu.items.length(), 1)
  assert_eq(command_menu.items[0].label(), "/compact")

  let plain = @composer.Model::new("")
  plain.insert_user_text("co")
  assert_true(completion_menu_for_composer(command_specs(), plain) is None)

  // Past the command name there is nothing to complete: the configured commands
  // take no arguments, so a separator closes the menu.
  let spaced = @composer.Model::new("")
  spaced.insert_user_text("/compact now")
  assert_true(completion_menu_for_composer(command_specs(), spaced) is None)

  // Multi-line input never opens a menu.
  let multiline = @composer.Model::new("")
  multiline.insert_user_text("/compact\n")
  assert_true(completion_menu_for_composer(command_specs(), multiline) is None)
}

///|
fn command_specs() -> Array[@slash.SlashCommandSpec] {
  [
    @slash.SlashCommandSpec::new(name="exit", description="exit the TUI"),
    @slash.SlashCommandSpec::new(
      name="compact",
      description="compact the conversation",
    ),
  ]
}

///|
fn composer_with(text : String) -> @composer.Model {
  let composer = @composer.Model::new("")
  composer.insert_user_text(text)
  composer
}

///|
test "enter dispatches the accepted command name with no arguments" {
  // Typing `/compact` (exact) or `/comp` (partial) and pressing Enter dispatches
  // `compact` with empty args; the handler runs it.
  for typed in ["/compact", "/comp"] {
    guard ui_enter_decision(
        command_specs(),
        composer_with(typed),
        CompletionState::new(),
        menu_visible=true,
      )
      is RunSlashCommand(name~, arguments~) else {
      fail("expected \{typed} to dispatch the compact command")
    }
    assert_eq(name, "compact")
    assert_eq(arguments, "")
  }
}

///|
test "enter dispatches a command with typed arguments verbatim" {
  // Past the command name there is no menu; the typed invocation dispatches as-is
  // (here the handler will reject the argument, but the decision still routes it).
  guard ui_enter_decision(
      command_specs(),
      composer_with("/compact extra"),
      CompletionState::new(),
      menu_visible=true,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected /compact to dispatch with the typed arguments")
  }
  assert_eq(name, "compact")
  assert_eq(arguments, "extra")
}

///|
test "accepted slash completion is recorded so recall re-runs it" {
  // Accepting `/comp` dispatches `compact`; history stores the canonical command
  // (via `slash_command_text`) so recall repeats it rather than the typed prefix.
  assert_eq(slash_command_text(name="compact", arguments=""), "/compact")
  assert_eq(slash_command_text(name="exit", arguments="now"), "/exit now")
  guard ui_enter_decision(
      command_specs(),
      composer_with("/comp"),
      CompletionState::new(),
      menu_visible=true,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected the completed command to run")
  }
  assert_eq(name, "compact")
  assert_eq(arguments, "")
}

///|
test "enter ignores the completion menu when it cannot be rendered" {
  // Menu hidden (terminal too short): the typed prefix dispatches as-is rather
  // than silently accepting the highlighted command.
  guard ui_enter_decision(
      command_specs(),
      composer_with("/comp"),
      CompletionState::new(),
      menu_visible=false,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected the typed prefix to dispatch when the menu is hidden")
  }
  assert_eq(name, "comp")
  assert_eq(arguments, "")
  // Visible, the same input accepts the highlighted command instead.
  guard ui_enter_decision(
      command_specs(),
      composer_with("/comp"),
      CompletionState::new(),
      menu_visible=true,
    )
    is RunSlashCommand(name=completed, ..) else {
    fail("expected the visible menu to complete the command")
  }
  assert_eq(completed, "compact")
}

///|
test "a malformed slash entry is not submitted as a prompt" {
  let specs = command_specs()
  // Menu dismissed (Esc): a lone `/` or `/ ` parses to no command, but must not
  // be submitted — that would leak the raw slash text into the agent.
  let dismissed = CompletionState::new()
  dismissed.dismissed = true
  for typed in ["/", "/ "] {
    assert_true(
      ui_enter_decision(
        specs,
        composer_with(typed),
        dismissed,
        menu_visible=true,
      )
      is NoCompletionMatch,
    )
  }
  // Same protection when the terminal is too short to draw the menu.
  assert_true(
    ui_enter_decision(
      specs,
      composer_with("/"),
      CompletionState::new(),
      menu_visible=false,
    )
    is NoCompletionMatch,
  )
  // Ordinary (non-slash) input is still submitted normally.
  assert_true(
    ui_enter_decision(
      specs,
      composer_with("hello"),
      dismissed,
      menu_visible=true,
    )
    is SubmitInput,
  )
}

///|
test "enter on a bare or doubled slash does not run the first command" {
  // A bare `/` opens a menu of every command with index 0 highlighted, and a
  // doubled `//`/`//e` would otherwise match a command by its `/`-prefixed
  // label. Enter must treat both as unfinished entries, not silently run the
  // first command (`/exit` is registered first, so this would quit the app).
  for typed in ["/", "//", "//e"] {
    assert_true(
      ui_enter_decision(
        command_specs(),
        composer_with(typed),
        CompletionState::new(),
        menu_visible=true,
      )
      is NoCompletionMatch,
    )
  }
  // No completion menu is offered for a doubled slash either.
  assert_true(
    completion_menu_for_composer(command_specs(), composer_with("//")) is None,
  )
}

///|
test "enter submits ordinary input outside a slash context" {
  assert_true(
    ui_enter_decision(
      command_specs(),
      composer_with("hello world"),
      CompletionState::new(),
      menu_visible=true,
    )
    is SubmitInput,
  )
}

///|
test "tab completes a command name" {
  // `/comp` completes to the highlighted command name.
  guard completion_menu_for_composer(command_specs(), composer_with("/comp"))
    is Some(name_menu) else {
    fail("expected command menu")
  }
  assert_true(completion_acceptance_text(name_menu, 0) is Some("/compact"))

  // A bare `/` completes to the first command, never queuing the slash.
  guard completion_menu_for_composer(command_specs(), composer_with("/"))
    is Some(all_menu) else {
    fail("expected command menu for bare slash")
  }
  assert_true(completion_acceptance_text(all_menu, 0) is Some("/exit"))

  // An unknown command has no item to accept.
  guard completion_menu_for_composer(command_specs(), composer_with("/nope"))
    is Some(empty_menu) else {
    fail("expected an (empty) command menu")
  }
  assert_true(completion_acceptance_text(empty_menu, 0) is None)
}

///|
test "a slash-command line is never queued as a prompt" {
  let specs = command_specs()
  // Both a partial command and a lone `/` are slash entries (not queued).
  assert_true(composer_is_slash_entry(specs, composer_with("/comp")))
  assert_true(composer_is_slash_entry(specs, composer_with("/")))
  // Ordinary text is not.
  assert_false(composer_is_slash_entry(specs, composer_with("hello")))
  // Multi-line input is never a slash entry.
  assert_false(composer_is_slash_entry(specs, composer_with("/compact\nx")))
  // With the feature disabled, a slash line is ordinary input (queueable).
  let no_commands : @slash.SlashCommands = []
  assert_false(composer_is_slash_entry(no_commands, composer_with("/path")))
}

///|
test "slash command invocation parses any single-line slash entry" {
  let specs = command_specs()
  let with_args = @composer.Model::new("")
  with_args.insert_user_text("/compact now")
  guard slash_command_invocation_for_composer(specs, with_args)
    is Some(invocation) else {
    fail("expected compact slash invocation")
  }
  assert_eq(invocation.name(), "compact")
  assert_eq(invocation.arguments(), "now")

  let trailing_space = @composer.Model::new("")
  trailing_space.insert_user_text("/compact   ")
  guard slash_command_invocation_for_composer(specs, trailing_space)
    is Some(invocation) else {
    fail("expected compact slash invocation")
  }
  assert_eq(invocation.arguments(), "")

  // Unknown commands still parse — dispatch is independent of registration.
  let unknown = @composer.Model::new("")
  unknown.insert_user_text("/unknown focus")
  guard slash_command_invocation_for_composer(specs, unknown)
    is Some(unknown_inv) else {
    fail("expected unknown command to parse syntactically")
  }
  assert_eq(unknown_inv.name(), "unknown")
  assert_eq(unknown_inv.arguments(), "focus")

  // With no commands configured the feature is off: a slash line is not an
  // invocation, so it stays ordinary input.
  let no_commands : @slash.SlashCommands = []
  let disabled = @composer.Model::new("")
  disabled.insert_user_text("/path/to/file")
  assert_true(
    slash_command_invocation_for_composer(no_commands, disabled) is None,
  )
}

///|
test "enter submits slash-prefixed input when no commands are configured" {
  let no_commands : @slash.SlashCommands = []
  assert_true(
    ui_enter_decision(
      no_commands,
      composer_with("/path"),
      CompletionState::new(),
      menu_visible=true,
    )
    is SubmitInput,
  )
}

///|
test "enter dispatches unknown slash commands to the handler" {
  // An unknown command must reach the handler (which reports the error) rather
  // than being sent to the agent as a prompt or swallowed as a notice.
  guard ui_enter_decision(
      command_specs(),
      composer_with("/doesnotexist test"),
      CompletionState::new(),
      menu_visible=true,
    )
    is RunSlashCommand(name~, arguments~) else {
    fail("expected unknown command with arguments to dispatch")
  }
  assert_eq(name, "doesnotexist")
  assert_eq(arguments, "test")
  guard ui_enter_decision(
      command_specs(),
      composer_with("/doesnotexist"),
      CompletionState::new(),
      menu_visible=true,
    )
    is RunSlashCommand(name=bare_name, arguments=bare_args) else {
    fail("expected bare unknown command to dispatch")
  }
  assert_eq(bare_name, "doesnotexist")
  assert_eq(bare_args, "")
}
