///|
/// The default engine's pinned release must be the one this module compiles
/// against: the UI decodes that release's `serve` events and reads its session
/// files, so bumping the `moon.mod` import without the constant (or the reverse)
/// would pair the UI with an engine speaking a different protocol. Moon runs
/// tests from the module root, where `moon.mod` lives.
async test "EngineModuleVersion matches the moonbitlang/openseek import in moon.mod" {
  let manifest = @fs.read_file("moon.mod").text()
  let prefix = "\"moonbitlang/openseek@"
  let imported = manifest
    .split("\n")
    .filter_map(line => {
      let line = line.trim()
      guard line.has_prefix(prefix) else { return None }
      let rest = line[prefix.length():]
      rest.split("\"").next().map(version => version.to_owned())
    })
    .to_array()
  @debug.assert_eq(imported, [EngineModuleVersion])
}
