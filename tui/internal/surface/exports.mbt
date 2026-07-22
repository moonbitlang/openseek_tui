// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// The line's text content with styling stripped. The render-assertion
/// seam: test suites across tui (core, composer, render, history, doc) and
/// the surface tests themselves read rendered lines back as plain text.
pub fn Line::text(self : Line) -> String {
  let builder = StringBuilder()
  for span in self.spans {
    builder <+ "\{span.text.text()}"
  }
  builder.to_string()
}
