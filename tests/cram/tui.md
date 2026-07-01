# Verified OpenSeek TUI CLI Documentation

These examples are executed by `moon cram test tests/cram`. The Moon wrapper
builds the native package at `cmd/openseek` and exposes the executable on `PATH`
as `openseek.exe`. The interactive terminal UI is the **default** mode of that
single binary; `openseek tui` is the explicit form. An initial prompt is passed
with `--prompt` (there is no free-form positional).

These commands are offline: they exercise only the argument parser and the
engine-usability preflight, which run before the terminal UI starts, so the
suite needs no API key, no TTY, and makes no network calls. The live,
API-backed examples live in [`tests/live/deepseek.md`](../live/deepseek.md).

## Help Banner

`openseek tui --help` prints the UI's options and exits successfully.

```mooncram
$ openseek.exe tui --help
Usage: openseek tui [options]

OpenSeek terminal UI.

Options:
  -h, --help                     Show help information.
  --api-key <api-key>            DeepSeek API key. [env: DEEPSEEK] [default: ]
  --model <model>                DeepSeek model: deepseek-v4-flash or deepseek-v4-pro. [env: DEEPSEEK_MODEL] [default: deepseek-v4-pro]
  --api-url <api-url>            DeepSeek-compatible chat completions endpoint. [env: OPENSEEK_API_URL] [default: ]
  --max-steps <max-steps>        Maximum number of agent loop steps before stopping. [env: OPENSEEK_MAX_STEPS] [default: 1000]
  --thinking <thinking>          DeepSeek thinking mode: no, high, or max. [env: OPENSEEK_THINKING] [default: max]
  --session <session>            Create or resume this durable session id. [env: OPENSEEK_SESSION]
  --session-root <session-root>  Directory containing durable OpenSeek sessions. [env: OPENSEEK_SESSION_ROOT] [default: .openseek]
  --continue                     Resume the most recently active session in --session-root.
  --engine <engine>              Agent engine to spawn (default: this openseek binary); reads its JSONL event stream from stdout. [env: OPENSEEK_ENGINE]
  --engine-mode <engine-mode>    Engine protocol: serve (one persistent, steerable process) or oneshot (spawn per prompt, for replay engines). [env: OPENSEEK_ENGINE_MODE] [default: serve]
  --prompt <prompt>              Initial prompt to send once the UI opens.
```

## A DeepSeek API Key Is Required

With no `--api-key` flag and no `DEEPSEEK` in the environment, the UI reports the
missing key on stderr and exits non-zero — before the terminal UI ever starts.
(The key is validated in the UI path rather than via argparse `required`, so the
root command can stay key-optional for offline engine subcommands like
`sessions list`.)

```mooncram
$ sh <<'EOF'
> stdout=$(mktemp)
> stderr=$(mktemp)
> if env -u DEEPSEEK openseek.exe tui > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' "$stderr"
> if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
> rm -f "$stdout" "$stderr"
> EOF
exit-non-zero
error: a DeepSeek API key is required: pass --api-key or set DEEPSEEK
stdout-empty
```

## Unknown Options Are Rejected

Option-looking tokens are validated by the parser before the UI starts.

```mooncram
$ sh <<'EOF'
> stdout=$(mktemp)
> stderr=$(mktemp)
> if env DEEPSEEK=test-key openseek.exe tui --xxy he > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' "$stderr"
> if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
> rm -f "$stdout" "$stderr"
> EOF
exit-non-zero
error: unexpected argument '--xxy' found
stdout-empty
```

## The Engine Is Probed Before The UI Starts

The UI spawns the `openseek` engine (by default this same binary, in `serve`
mode; override with `--engine`/`OPENSEEK_ENGINE`) and probes it with `--help`
first. A missing engine fails fast, before the UI takes over the terminal.

```mooncram
$ env DEEPSEEK=test-key openseek.exe tui --engine openseek-not-a-real-binary
error: engine 'openseek-not-a-real-binary' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path>, set OPENSEEK_ENGINE, or install the openseek binary.
[1]
```

## An Initial Prompt Comes From `--prompt`

`--prompt` supplies the first message. It parses and reaches the engine preflight
(shown here failing deterministically on a missing engine), which proves the
prompt path is wired — there is no free-form positional.

```mooncram
$ env DEEPSEEK=test-key openseek.exe tui --engine does-not-exist --prompt "inspect project"
error: engine 'does-not-exist' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path>, set OPENSEEK_ENGINE, or install the openseek binary.
[1]
```
