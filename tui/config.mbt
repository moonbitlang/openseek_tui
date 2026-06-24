///|
const DefaultEscTimeoutMs : Int = 50

///|
const DefaultComposerMaxRows : Int = @composer.DefaultMaxTextRows

///|
struct Config {
  esc_timeout_ms : Int
  composer_max_rows : Int
  slash_commands : @slash.SlashCommands
}

///|
/// Build a UI `Config`. `esc_timeout_ms` bounds how long the reader waits to
/// disambiguate a lone `Esc` from a CSI escape sequence, and `composer_max_rows`
/// caps how tall the editable input area grows. `slash_commands` configures the
/// optional slash-command completion menu. Non-positive numeric values fall back
/// to the defaults (`50` ms and `@composer.DefaultMaxTextRows`).
pub fn Config::new(
  esc_timeout_ms? : Int = DefaultEscTimeoutMs,
  composer_max_rows? : Int = DefaultComposerMaxRows,
  slash_commands? : Array[@slash.SlashCommandSpec] = [],
) -> Config {
  let esc_timeout_ms = if esc_timeout_ms < 1 {
    DefaultEscTimeoutMs
  } else {
    esc_timeout_ms
  }
  let composer_max_rows = if composer_max_rows < 1 {
    DefaultComposerMaxRows
  } else {
    composer_max_rows
  }
  { esc_timeout_ms, composer_max_rows, slash_commands: slash_commands.copy() }
}
