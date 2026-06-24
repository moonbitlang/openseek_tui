///|
/// A user-driven UI event handed to the application loop.
pub(all) enum Event {
  Queue(Input)
  Steer(Input)
  SlashCommand(name~ : String, arguments~ : String)
  Interrupt
  Quit
} derive(Eq, Debug)
