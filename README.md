# moonbitlang/openseek_tui

The interactive terminal UI for [OpenSeek](https://github.com/moonbitlang/openseek):
the `openseek_tui` binary. It is a scrolling transcript with a live composer
that drives the headless `openseek` engine over its JSONL protocol — streamed
answer text appears live on the activity line, each turn's reasoning is kept as
a dim `✻` transcript aside above its answer, and tool results land as `⏺`
blocks. Pressing Enter while a task runs steers it mid-turn; Ctrl-C cancels the
turn.

The UI runs no agent code itself. The engine is the separate `openseek` binary
from the [moonbitlang/openseek](https://github.com/moonbitlang/openseek)
repository; this module depends on that repository's published module
(`moonbitlang/openseek` on mooncakes) for the agent, session, and provider
packages, and on `moonbitlang/openseek_protocol` for the wire contract.

## Running it

You need the [MoonBit toolchain](https://www.moonbitlang.com/download), which
provides `moon` and `moonx`. The engine is not installed separately: the UI runs
the `moonbitlang/openseek` release it was built against through `moonx`.

```bash
git clone https://github.com/moonbitlang/openseek_tui && cd openseek_tui
moon build --release cmd/openseek_tui
cp _build/native/release/build/moonbitlang/openseek_tui/cmd/openseek_tui/openseek_tui.exe ~/.moon/bin/openseek_tui

export DEEPSEEK=sk-...
openseek_tui
```

**The engine.** With no `--engine`, the UI spawns
`moonx moonbitlang/openseek@<version> serve …`, where `<version>` is the
`moonbitlang/openseek` release imported in `moon.mod` (a test keeps the two
equal), so the engine always speaks the protocol and session format the UI was
compiled against. The first launch downloads that release's published
linear-Wasm build from mooncakes.io (so it needs the network) and caches it;
later launches start from the cache. The engine is probed with `--help` before
the UI takes over the terminal, so a missing `moonx` or a failed download is
reported up front. Pass `--engine <path>` to run a different engine binary
instead, such as a local openseek build.

**Sessions.** Every launch converses in a durable session under
`--session-root` (default `.openseek/`), interoperable with the CLI's own
sessions:

- `openseek_tui --continue` resumes the most recently active session.
- `openseek_tui --session <id>` resumes (or creates) a specific one.
- `openseek_tui --prompt "…"` sends an initial prompt once the UI opens.
- `openseek sessions list` (the engine CLI) shows what is resumable.

The shared engine options (`--api-key`, `--model`, `--api-url`, `--max-steps`,
`--thinking`, `--session`, `--session-root`) are the same ones `openseek run`
takes; `openseek_tui --help` lists them all.

## Packages

| Package | Purpose | README |
| --- | --- | --- |
| `moonbitlang/openseek_tui/cmd/openseek_tui` | The executable: parses argv and hands the parsed matches to `cmd/tui`. | — |
| `moonbitlang/openseek_tui/cmd/tui` | The OpenSeek terminal UI: engine spawn and protocol handling, transcript model, slash commands, session resume. | [`cmd/tui/README.md`](cmd/tui/README.md) |
| `moonbitlang/openseek_tui/tui` (+ `core`, `doc`, `style`, `slash`, `completion`) | Reusable terminal-UI framework (transcript, composer, rendering) the OpenSeek UI is built on. Agent-agnostic. | [`tui/README.md`](tui/README.md) |

## Development

```bash
moon check --target native --deny-warn
moon test --target native
moon cram test tests/cram          # verified CLI docs: tests/cram/tui.md
moon fmt
moon info                          # regenerate pkg.generated.mbti after API changes
```

`tests/cram/tui.md` is executable documentation of the `openseek_tui` command
line (help banner, argument errors, the engine preflight). It runs offline and
needs no API key.

**Developing against a local openseek checkout.** `moonbitlang/openseek` comes
from mooncakes by default. To build against an unpublished checkout, add a
`moon.work` (git-ignored) that lists this module and the checkout's workspace
members:

```
members = [
  ".",
  "../openseek",
  "../openseek/protocol",
  "../openseek/editor",
  "../openseek/editor/server",
]
```

The editor members are needed because `moonbitlang/openseek` itself depends on
`moonbitlang/editor`, and the checkout's editor is the one it is developed
against.

The workspace only changes what the UI compiles against. To also *run* the
checkout's engine, build it there (`moon build --release cmd/openseek`) and pass
its binary with `--engine <path>`; otherwise the UI still spawns the pinned
release through `moonx`.

## Publishing

The module is published to mooncakes as `moonbitlang/openseek_tui` by the
`publish-package` workflow (`.github/workflows/publish.yml`, run manually via
workflow dispatch) using the organization's mooncakes token. Bump `version` in
`moon.mod` first. When bumping the `moonbitlang/openseek` import, bump
`EngineModuleVersion` in `cmd/tui/main.mbt` with it (`moon test` fails until
they match) and check that the release has a published linear-Wasm build, since
that is what `moonx` downloads.

## History

This repository was extracted from
[moonbitlang/openseek](https://github.com/moonbitlang/openseek) on 2026-09-03
with `git filter-repo`, keeping the history of `tui/`, `cmd/tui/`,
`cmd/openseek_tui/`, and `tests/cram/tui.md`.

## License

Apache-2.0, see [LICENSE](LICENSE).
