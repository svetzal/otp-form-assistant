# Functional guide

OTP form assistant helps a person complete a structured form through text
or voice. It edits a draft beside the host's form. The person and assistant
share one history of changes.

## Responsibilities

The package owns field descriptions, drafts, review, assistant tools, and
LiveView interactions. Optional voice sessions run under a supervisor.

The host owns identity, authorization, storage, model access, and provider
connections. The package has no database, HTTP endpoint, or credentials.
It starts no process when its OTP application starts.

## A conversation

1. The host checks access and loads the saved values.
2. The person opens the assistant.
3. The assistant reads the form through generated tools.
4. The person types or starts a voice session.
5. Changes appear in the draft and on the page.
6. The person saves or discards the draft.

The host supplies the initial values to `FormAssistant.Live.open/4`.
The opening turn asks the model to read and review the form before asking
one open question. The model's exact words can vary.

Text-only use has no microphone control. Voice use also permits typed words
through the active voice session.

## Fields and dependencies

A `FormAssistant.Field` describes one string-keyed field. Its label,
section, help, limits, and choices explain that field to the person and model.
The host's validator parses values and enforces domain rules.

The `affects` list describes relationships between fields. The assistant
reads each relationship in both directions. This is a navigation and review
aid. It does not calculate or change dependent values automatically.

A field marked `worth_filling` appears in review when empty. A list field
with one item appears as thin. The host can add review findings for conflicts.
Review does not replace validation or authorization.

## Draft lifecycle

`FormAssistant.Draft` keeps saved values, current values, applied changes,
and undone changes. Each change records its field, previous value, next
value, author, and optional reason.

- A valid change enters the shared history.
- An invalid change leaves that field unchanged and returns an error.
- An unchanged value creates no history entry.
- A new change clears redo history.
- Undo and redo affect the latest history entry, regardless of author.
- A manual section edit creates separate entries for changed fields.

A section edit skips refused fields and can apply valid fields from the
same submission. It is not an atomic transaction across the section.

Saving updates the saved baseline but retains history. Undo after saving
therefore creates an unsaved difference from the saved baseline.

Closing the assistant panel keeps its draft. Reopening restores the panel.
Discard drops the draft and stops voice.

Page termination loses the in-memory draft. The package does not persist
drafts or resume them after reconnects. The host may add that capability
separately.

## Assistant tools

| Tool | Result |
| --- | --- |
| `describe_form` | Field descriptions, choices, and relationships. |
| `read_form` | Draft values, saved values, and changed field IDs. |
| `set_field` | A validated change to one draft field. |
| `clear_field` | A validated change to nil. |
| `undo` | Reverses the latest applied change. |
| `redo` | Restores the latest undone change. |
| `review` | General and host-specific review findings. |
| `save` | Requests a save through the host callback. |

Tool outputs include errors for unknown tools, invalid arguments, and refused
changes. `FormAssistant.run_tool/3` records the call and its result through
the host's recording function.

The prompt instructs the assistant to save only when asked. The save tool
requires nonempty `owner_words`, supplied by the model. Those words are not
independent proof of consent.

Hosts that need explicit approval must enforce it in their save path.
Authorization always belongs in `c:FormAssistant.Form.save/3`.

## Typed turns

Each typed turn sends instructions and tools to the host's Responses API
adapter. Requests set `store: true`. Later requests use the previous response
ID when available. The adapter must support these shapes.

The package allows eight tool rounds per turn. If the model keeps calling
tools, it returns a fallback reply. An empty response also produces a fallback.
A provider error returns to the LiveView. The person can try another message.

Recording is synchronous through the supplied callback. The host must keep
that callback reliable and choose a policy for storage failures. Its return
value is not a durable-delivery acknowledgement protocol.

## Voice sessions

One temporary GenServer owns each voice connection. It monitors the page
that started it.

A session ends when stopped, when the page exits, when the
provider closes it, or when its time limit expires. The default limit is
20 minutes.

The browser sends and receives base64 PCM16 audio at 24 kHz. The session
passes tool calls to the LiveView, which edits the same draft used by text
and manual changes. The host supplies the authenticated transport.

A failed connection shows an error and leaves typed use available. A crashed
session is not restarted as a new conversation. The existing implementation
has no automatic reconnect, resumed session, or durable audio queue.

The voice protocol comes from the original probes. Its documentation
distinguishes verified message shapes from assumptions about PCM input and
typed words. The fake-transport suite does not prove live provider behavior.

## Privacy and access

The model receives the form context, values returned by tools, and the
conversation. Field help and context are model input too. Exclude unrelated
or confidential records that the assistant does not need.

The package treats scope as opaque. It cannot decide whether a person may
edit a record. The host must check access before opening the page and again
when loading or saving data. Recheck authorization after access changes.

The host chooses retention, erasure, and access rules for recorded events.
Provider-side records are separate from host-side event storage.

## Limits

The package does not supply model networking, business rules, persistence,
telephony, user accounts, or conflict resolution between concurrent editors.
It has no deployment service of its own.

The integration guide describes host adapters. The deployment guide describes
operation inside a host release.
