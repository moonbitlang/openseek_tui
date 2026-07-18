// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// User-visible command description shown in the completion menu.
pub fn SlashCommandSpec::description(self : SlashCommandSpec) -> String {
  self.description
}

///|
/// Command name without the leading slash.
pub fn SlashCommandSpec::name(self : SlashCommandSpec) -> String {
  self.name
}

///|
/// Command whose name equals `name`, case-insensitively, if any.
pub fn SlashCommands::get(
  self : SlashCommands,
  name : String,
) -> SlashCommandSpec? {
  for command in self.0 {
    if command.name().equal_ignore_ascii_case(name) {
      return Some(command)
    }
  }
  None
}
