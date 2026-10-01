# moonbitlang/openseek_tui/cmd/tui

The OpenSeek terminal UI: a scrolling transcript with a live composer, built on
the reusable [`tui`](../../tui/README.md) controller package. It ships as a
library launched by the dedicated `openseek_tui` binary (a thin executable
package that builds this package's `cli_command`); the headless engine comes
from the separate `moonbitlang/openseek` module.

The UI runs no agent code itself. It spawns the `openseek` engine — by default
the `moonbitlang/openseek` release this module is compiled against, run through
`moonx` (`moonx moonbitlang/openseek@<version> serve …`; the first launch
downloads and caches its published linear-Wasm build); override it with
`--engine`. The engine is spawned **once per session** and driven over stdin
commands, and the UI renders the engine's
JSONL event stream: streamed thinking and answer text move live on the activity
line, each turn's reasoning is kept as a dim `✻` transcript aside above its
answer, and tool results land as `⏺` blocks. Pressing Enter while a task runs
steers it mid-turn; Ctrl-C cancels the turn (a second Ctrl-C kills the engine,
and the next prompt respawns it on the same session).

Killing the engine (a second Ctrl-C, or a quit that the engine does not drain
within two seconds) first asks it to stop — SIGTERM on Unix, CTRL_BREAK on
Windows — and force-kills it five seconds later if it is still running. On
Unix `moonx` `exec`s `moonrun`, so the spawned process *is* the engine. On
Windows `moonx` runs `moonrun` as a child instead, so the UI places each engine
in its own Job Object and terminates that job as soon as the spawned process
exits: a killed `moonx` takes `moonrun` and everything it started with it, and
none of them keeps the engine's pipes, session lock, or log open. Containment
is best effort; if the job cannot be created, only the spawned process is
killed. The mechanism lives in
[`internal/process_tree`](internal/process_tree/README.mbt.md).

A custom or recorded-stream engine (`--engine`) speaks the same protocol: it
is spawned as `<engine> serve --session=<id> --session-root=<root>
--dir=<cwd>`, reads JSONL commands on stdin and writes JSONL events on stdout.
It may exit after answering a prompt: once its turn's terminal event has
arrived, an engine exit is not an error, and the next prompt starts a fresh
one on the same session.

Because the UI takes over the terminal, launching it without a TTY (a pipe, CI
log, or cron) is refused with a pointer to `openseek run` / `openseek serve`.

From the source tree, `moon run cmd/openseek_tui` uses the same `moonx`
default, so it needs no engine build of its own; pass `--engine <path>` to try a
local openseek build instead. The preflight refuses to start the UI until the
engine is usable.

## Sessions

Every launch converses in a durable session — the engine only carries context
between prompts through the session store, so without one each prompt would be
an amnesiac one-shot. A generated id (`tui-YYYYMMDD-HHMMSS-mmm`, named in the
startup banner) stores the conversation under `--session-root` (default
`.openseek/`).

- `--continue` resumes the most recently active session.
- `--session <id>` resumes (or creates) a specific one; combining it with
  `--continue` is rejected.
- `openseek sessions list` lists what is resumable.

`/inspect` shows the session live in the browser. It starts (or reuses) the
session viewer for `--session-root`, `moonx moonbitlang/inspect@0.1.0 --ensure
--watch`, in the background, and adds its link to the transcript on a line of
its own. The page opens on this session and follows it as the conversation
grows. The viewer is its own process, shared with every other TUI and
`openseek run --inspect` in the project, outlives the TUI, and exits after an
hour without a request. If it cannot start, the transcript says why.

## Configuration

`--api-key` or a provider-specific key env is required: `DEEPSEEK` for DeepSeek
models, `KIMI` for Kimi models, and `GLM` for Z.AI GLM models. `--model`, `--api-url`,
`--max-steps`, and `--thinking` mirror the engine's flags and are forwarded to
it through the environment, alongside the session settings.

The full flag reference lives in the executable help — verified verbatim in
[`tests/cram/tui.md`](../../tests/cram/tui.md).
