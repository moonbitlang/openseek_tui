///|
/// Decode one engine event and run it through `update`, appending any resulting
/// transcript items to `items`. Accumulating into a caller-owned array lets a
/// test replay a whole session and snapshot the rendered transcript at the end.
fn append_items(
  state : State,
  value : Json,
  items : Array[@ui.TranscriptItem],
) -> Unit {
  guard @event.decode_event(value) is Some(event) else { return }
  for cmd in update(state, AgentProgress(run_id=state.run_id, event)) {
    if cmd is AppendItem(item) {
      items.push(item)
    }
  }
}

///|
async test "a shell command runs locally and posts its output" {
  let messages = @async.Queue(kind=Unbounded)
  // `echo` is the same on POSIX `sh` and Windows `pwsh`, so the platform shell
  // `@shell.collect_shell_output` picks runs this on either.
  run_shell_command("echo hello", messages, run_id=1)
  // The only message is the local command result: a completed tool item titled
  // with the command, its stdout as a dimmed detail line. Nothing is sent to the
  // engine.
  let item = match messages.get() {
    CommandResult(command~, result, ..) => {
      assert_eq(command, "echo hello")
      command_item(command, result)
    }
    _ => fail("expected a CommandResult")
  }
  debug_inspect(
    item,
    content=(
      #|ToolCall(
      #|  {
      #|    title: {
      #|      spans: [
      #|        {
      #|          display: {
      #|            text: "$ echo hello",
      #|            units: [
      #|              {
      #|                text: <StringView: "$">,
      #|                width: 1,
      #|                textual_end: TextualPosition(1),
      #|                display_end: DisplayPosition(1),
      #|              },
      #|              {
      #|                text: <StringView: " ">,
      #|                width: 1,
      #|                textual_end: TextualPosition(2),
      #|                display_end: DisplayPosition(2),
      #|              },
      #|              {
      #|                text: <StringView: "e">,
      #|                width: 1,
      #|                textual_end: TextualPosition(3),
      #|                display_end: DisplayPosition(3),
      #|              },
      #|              {
      #|                text: <StringView: "c">,
      #|                width: 1,
      #|                textual_end: TextualPosition(4),
      #|                display_end: DisplayPosition(4),
      #|              },
      #|              {
      #|                text: <StringView: "h">,
      #|                width: 1,
      #|                textual_end: TextualPosition(5),
      #|                display_end: DisplayPosition(5),
      #|              },
      #|              {
      #|                text: <StringView: "o">,
      #|                width: 1,
      #|                textual_end: TextualPosition(6),
      #|                display_end: DisplayPosition(6),
      #|              },
      #|              {
      #|                text: <StringView: " ">,
      #|                width: 1,
      #|                textual_end: TextualPosition(7),
      #|                display_end: DisplayPosition(7),
      #|              },
      #|              {
      #|                text: <StringView: "h">,
      #|                width: 1,
      #|                textual_end: TextualPosition(8),
      #|                display_end: DisplayPosition(8),
      #|              },
      #|              {
      #|                text: <StringView: "e">,
      #|                width: 1,
      #|                textual_end: TextualPosition(9),
      #|                display_end: DisplayPosition(9),
      #|              },
      #|              {
      #|                text: <StringView: "l">,
      #|                width: 1,
      #|                textual_end: TextualPosition(10),
      #|                display_end: DisplayPosition(10),
      #|              },
      #|              {
      #|                text: <StringView: "l">,
      #|                width: 1,
      #|                textual_end: TextualPosition(11),
      #|                display_end: DisplayPosition(11),
      #|              },
      #|              {
      #|                text: <StringView: "o">,
      #|                width: 1,
      #|                textual_end: TextualPosition(12),
      #|                display_end: DisplayPosition(12),
      #|              },
      #|            ],
      #|            width: 12,
      #|            cjk: false,
      #|          },
      #|          style: { foreground: Default, background: Default, underline: false },
      #|        },
      #|      ],
      #|    },
      #|    status: Some(Completed),
      #|    details: [
      #|      {
      #|        spans: [
      #|          {
      #|            display: {
      #|              text: "hello",
      #|              units: [
      #|                {
      #|                  text: <StringView: "h">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(1),
      #|                  display_end: DisplayPosition(1),
      #|                },
      #|                {
      #|                  text: <StringView: "e">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(2),
      #|                  display_end: DisplayPosition(2),
      #|                },
      #|                {
      #|                  text: <StringView: "l">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(3),
      #|                  display_end: DisplayPosition(3),
      #|                },
      #|                {
      #|                  text: <StringView: "l">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(4),
      #|                  display_end: DisplayPosition(4),
      #|                },
      #|                {
      #|                  text: <StringView: "o">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(5),
      #|                  display_end: DisplayPosition(5),
      #|                },
      #|              ],
      #|              width: 5,
      #|              cjk: false,
      #|            },
      #|            style: {
      #|              foreground: Basic(BrightBlack),
      #|              background: Default,
      #|              underline: false,
      #|            },
      #|          },
      #|        ],
      #|      },
      #|    ],
      #|  },
      #|)
    ),
  )
}

///|
test "assistant_delta accumulates live text and commits only the final message" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(state, { "event": "assistant_delta", "content": "Hel" }, items)
  append_items(state, { "event": "assistant_delta", "content": "lo" }, items)
  assert_eq(items.length(), 0)
  assert_true(state.streaming_response is Some("Hello"))
  assert_true(state.step_response is None)
  append_items(
    state,
    { "event": "assistant_message", "content": "Hello" },
    items,
  )
  assert_true(state.streaming_response is None)
  assert_true(state.step_response is Some("Hello"))
  append_items(state, { "event": "agent_finished", "answer": "Hello" }, items)
  debug_inspect(items, content="[Response(\"Hello\")]")
}

///|
test "assistant_message clears live streaming text while tools continue" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "assistant_delta", "content": "Need tool" },
    items,
  )
  assert_true(state.streaming_response is Some("Need tool"))
  append_items(
    state,
    { "event": "assistant_message", "content": "Need tool" },
    items,
  )
  assert_true(state.run is Running(_))
  assert_true(state.streaming_response is None)
  assert_true(state.step_response is Some("Need tool"))
  assert_eq(items.length(), 1)
}

///|
test "assistant_delta live preview keeps the newest tail within the cap" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    {
      "event": "assistant_delta",
      "content": String::make(StreamingPreviewMaxColumns * 4, 'x'),
    },
    items,
  )
  guard state.streaming_response is Some(first) else {
    fail("expected streaming preview")
  }
  assert_true(
    @displaytext.DisplayText(first).width() <= StreamingPreviewMaxColumns,
  )
  assert_true(first.has_prefix("…"))
  // The preview is a tail window: new deltas keep showing up at its end
  // (instead of freezing once the cap is reached, as a head truncation would).
  append_items(state, { "event": "assistant_delta", "content": "more" }, items)
  guard state.streaming_response is Some(second) else {
    fail("expected streaming preview")
  }
  assert_true(second.has_suffix("more"))
  assert_true(
    @displaytext.DisplayText(second).width() <= StreamingPreviewMaxColumns,
  )
  assert_eq(items.length(), 0)
}

///|
test "streamed newlines collapse so the preview stays one line" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "assistant_delta", "content": "fn main {\n" },
    items,
  )
  append_items(
    state,
    { "event": "assistant_delta", "content": "  println(1)\n}" },
    items,
  )
  // The run of newline + indentation spanning the two deltas collapses to a
  // single space; the preview holds no control characters.
  assert_true(state.streaming_response is Some("fn main { println(1) }"))
}

///|
test "reasoning_message commits a thought item and clears the preview" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "reasoning_delta", "content": "Let me think" },
    items,
  )
  assert_true(state.streaming_reasoning is Some("Let me think"))
  // The full reasoning lands as one `✻` thought item, and the live preview
  // is finished with.
  append_items(
    state,
    {
      "event": "reasoning_message",
      "content": "Let me think about names.\nThe user said Hongbo.",
    },
    items,
  )
  assert_true(state.streaming_reasoning is None)
  guard items is [Thought(_)] else { fail("expected a single Thought item") }
  // Blank reasoning never appends an empty aside.
  append_items(state, { "event": "reasoning_message", "content": "  " }, items)
  assert_eq(items.length(), 1)
}

///|
test "reasoning_delta drives the thinking preview until content arrives" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "reasoning_delta", "content": "Let me think" },
    items,
  )
  assert_true(state.streaming_reasoning is Some("Let me think"))
  assert_true(state.streaming_response is None)
  assert_eq(items.length(), 0)
  // The first content delta ends the thinking phase: the content preview
  // replaces the reasoning one.
  append_items(
    state,
    { "event": "assistant_delta", "content": "Answer" },
    items,
  )
  assert_true(state.streaming_reasoning is None)
  assert_true(state.streaming_response is Some("Answer"))
  // The committed message clears both previews.
  append_items(
    state,
    { "event": "assistant_message", "content": "Answer" },
    items,
  )
  assert_true(state.streaming_response is None)
  assert_true(state.streaming_reasoning is None)
}

///|
test "replaying a recorded engine session renders the transcript" {
  let state = drain_test_state()
  // Submit a task so the agent is running before progress arrives.
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  assert_true(state.run is Running(_))

  // A realistic one-step session: think, report usage, run a tool, finish.
  let items : Array[@ui.TranscriptItem] = []
  append_items(state, { "event": "agent_step", "step": 1 }, items)
  append_items(
    state,
    { "event": "assistant_message", "content": "Let me check the project." },
    items,
  )
  append_items(
    state,
    {
      "event": "usage",
      "usage": {
        "prompt_tokens": 100,
        "completion_tokens": 20,
        "total_tokens": 120,
        "prompt_cache_hit_tokens": 0,
        "prompt_cache_miss_tokens": 100,
      },
    },
    items,
  )
  append_items(
    state,
    {
      "event": "tool_result",
      "tool_call_id": "c1",
      "tool_name": "bash",
      "is_error": false,
      "content": "ok",
    },
    items,
  )
  append_items(
    state,
    { "event": "agent_finished", "answer": "all done" },
    items,
  )

  // The rendered transcript: the assistant message, the tool result, and the
  // final answer. `agent_step` and `usage` update state without emitting items.
  debug_inspect(
    items,
    content=(
      #|[
      #|  Response("Let me check the project."),
      #|  ToolCall(
      #|    {
      #|      title: {
      #|        spans: [
      #|          {
      #|            display: {
      #|              text: "Tool bash",
      #|              units: [
      #|                {
      #|                  text: <StringView: "T">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(1),
      #|                  display_end: DisplayPosition(1),
      #|                },
      #|                {
      #|                  text: <StringView: "o">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(2),
      #|                  display_end: DisplayPosition(2),
      #|                },
      #|                {
      #|                  text: <StringView: "o">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(3),
      #|                  display_end: DisplayPosition(3),
      #|                },
      #|                {
      #|                  text: <StringView: "l">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(4),
      #|                  display_end: DisplayPosition(4),
      #|                },
      #|                {
      #|                  text: <StringView: " ">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(5),
      #|                  display_end: DisplayPosition(5),
      #|                },
      #|                {
      #|                  text: <StringView: "b">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(6),
      #|                  display_end: DisplayPosition(6),
      #|                },
      #|                {
      #|                  text: <StringView: "a">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(7),
      #|                  display_end: DisplayPosition(7),
      #|                },
      #|                {
      #|                  text: <StringView: "s">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(8),
      #|                  display_end: DisplayPosition(8),
      #|                },
      #|                {
      #|                  text: <StringView: "h">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(9),
      #|                  display_end: DisplayPosition(9),
      #|                },
      #|              ],
      #|              width: 9,
      #|              cjk: false,
      #|            },
      #|            style: { foreground: Default, background: Default, underline: false },
      #|          },
      #|        ],
      #|      },
      #|      status: Some(Completed),
      #|      details: [
      #|        {
      #|          spans: [
      #|            {
      #|              display: {
      #|                text: "ok",
      #|                units: [
      #|                  {
      #|                    text: <StringView: "o">,
      #|                    width: 1,
      #|                    textual_end: TextualPosition(1),
      #|                    display_end: DisplayPosition(1),
      #|                  },
      #|                  {
      #|                    text: <StringView: "k">,
      #|                    width: 1,
      #|                    textual_end: TextualPosition(2),
      #|                    display_end: DisplayPosition(2),
      #|                  },
      #|                ],
      #|                width: 2,
      #|                cjk: false,
      #|              },
      #|              style: {
      #|                foreground: Basic(BrightBlack),
      #|                background: Default,
      #|                underline: false,
      #|              },
      #|            },
      #|          ],
      #|        },
      #|      ],
      #|    },
      #|  ),
      #|  Response("all done"),
      #|]
    ),
  )
  match state.usage {
    Some(usage) => assert_eq(usage.total_tokens, 120)
    None => fail("usage not recorded")
  }
  // The terminal event left the agent idle.
  assert_true(state.run is Idle)
}
