# Verified OpenSeek TUI CLI Documentation

These examples are executed by `moon cram test tests/cram`. The Moon wrapper
builds the native package at `cmd/tui` first, then exposes the executable on
`PATH` as `tui.exe`.

Both commands are offline: they exercise only the argument parser, which runs
before the terminal UI starts, so the suite needs no API key, no TTY, and makes
no network calls. The live, API-backed examples live in
[`tests/live/deepseek.md`](../live/deepseek.md).

## Help Banner

`--help` prints the usage, the available options, and the environment variables
and defaults behind each one, then exits successfully.

```mooncram
$ tui.exe --help
Usage: openseek-tui --api-key <api-key> [options] [task...]

OpenSeek terminal UI.

Arguments:
  task...  Optional initial task description.

Options:
  -h, --help                     Show help information.
  --continue                     Resume the most recently active session in --session-root.
  --api-key <api-key>            DeepSeek API key. [env: DEEPSEEK]
  --model <model>                DeepSeek model: deepseek-v4-flash or deepseek-v4-pro. [env: DEEPSEEK_MODEL] [default: deepseek-v4-pro]
  --api-url <api-url>            DeepSeek-compatible chat completions endpoint. [env: OPENSEEK_API_URL] [default: ]
  --max-steps <max-steps>        Maximum number of agent loop steps before stopping. [env: OPENSEEK_MAX_STEPS] [default: 1000]
  --thinking <thinking>          DeepSeek thinking mode: no, high, or max. [env: OPENSEEK_THINKING] [default: max]
  --engine <engine>              Agent engine binary to spawn; reads its JSONL event stream from stdout. [env: OPENSEEK_ENGINE] [default: openseek]
  --engine-mode <engine-mode>    Engine protocol: serve (one persistent, steerable process) or oneshot (spawn per prompt, for replay engines). [env: OPENSEEK_ENGINE_MODE] [default: serve]
  --session <session>            Create or resume this durable session id. [env: OPENSEEK_SESSION]
  --session-root <session-root>  Directory containing durable OpenSeek sessions. [env: OPENSEEK_SESSION_ROOT] [default: .openseek]
```

## A DeepSeek API Key Is Required

With no `--api-key` flag and no `DEEPSEEK` in the environment, the CLI reports
the missing required argument, prints the usage, and exits non-zero — before the
terminal UI ever starts.

```mooncram
$ env -u DEEPSEEK tui.exe "summarize this project"
error: the following required argument was not provided: 'api-key'

Usage: openseek-tui --api-key <api-key> [options] [task...]

OpenSeek terminal UI.

Arguments:
  task...  Optional initial task description.

Options:
  -h, --help                     Show help information.
  --continue                     Resume the most recently active session in --session-root.
  --api-key <api-key>            DeepSeek API key. [env: DEEPSEEK]
  --model <model>                DeepSeek model: deepseek-v4-flash or deepseek-v4-pro. [env: DEEPSEEK_MODEL] [default: deepseek-v4-pro]
  --api-url <api-url>            DeepSeek-compatible chat completions endpoint. [env: OPENSEEK_API_URL] [default: ]
  --max-steps <max-steps>        Maximum number of agent loop steps before stopping. [env: OPENSEEK_MAX_STEPS] [default: 1000]
  --thinking <thinking>          DeepSeek thinking mode: no, high, or max. [env: OPENSEEK_THINKING] [default: max]
  --engine <engine>              Agent engine binary to spawn; reads its JSONL event stream from stdout. [env: OPENSEEK_ENGINE] [default: openseek]
  --engine-mode <engine-mode>    Engine protocol: serve (one persistent, steerable process) or oneshot (spawn per prompt, for replay engines). [env: OPENSEEK_ENGINE_MODE] [default: serve]
  --session <session>            Create or resume this durable session id. [env: OPENSEEK_SESSION]
  --session-root <session-root>  Directory containing durable OpenSeek sessions. [env: OPENSEEK_SESSION_ROOT] [default: .openseek]

[1]
```

## Unknown Options Are Rejected Before Initial Task Text

Like the one-shot CLI, the TUI treats option-looking tokens as options until
the normal `--` delimiter stops option parsing.

```mooncram
$ sh <<'EOF'
> stdout=$(mktemp)
> stderr=$(mktemp)
> if env DEEPSEEK=test-key tui.exe --xxy he > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' "$stdout"
> if test -s "$stderr"; then echo stderr-not-empty; else echo stderr-empty; fi
> rm -f "$stdout" "$stderr"
> EOF
exit-non-zero
error: unexpected argument '--xxy' found
stderr-empty
```

When the initial task itself must start with `-`, use `--`. This gets past
argument parsing; the fake engine then fails the preflight check before the TUI
takes over the terminal.

```mooncram
$ env DEEPSEEK=test-key tui.exe --engine openseek-not-a-real-binary -- '--xxy he'
error: engine 'openseek-not-a-real-binary' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path>, set OPENSEEK_ENGINE, or install the openseek binary.
[1]
```
