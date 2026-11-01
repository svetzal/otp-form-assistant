defmodule FormAssistant.Components do
  @moduledoc """
  The form assistant's page parts, built from Armature components: the
  assistant panel (open button, conversation, voice button and state, text
  box), the draft bar (changes not saved, undo, redo, save, discard) and the
  change notes a form section shows beside its fields.

  They take the `:form_assistant` assign (`FormAssistant.Live`) and send
  `fa_` events. Their own markup uses `fa-` classes; the application styles
  them with the packaged `priv/static/form_assistant.css` stylesheet. The open button sends
  `"fa_open"`, which the host page handles.
  """
  use Phoenix.Component

  import Armature.Components.Atoms, only: [button: 1, status: 1]
  import Armature.Components.Layouts, only: [cluster: 1, stack: 1]
  import Armature.Components.Molecules, only: [field: 1]
  import Armature.Components.Organisms, only: [panel: 1]

  alias FormAssistant.{Draft, Form}

  @doc "The assistant panel."
  attr(:id, :string, required: true)
  attr(:state, :any, required: true, doc: "the :form_assistant assign")
  attr(:turns, :any, required: true, doc: "the :form_assistant_turns stream")
  attr(:heading, :string, default: "Talk it through")
  slot(:intro, required: true, doc: "what the assistant does, shown while it is closed")

  def assistant(assigns) do
    assigns =
      assign(assigns,
        open?: assigns.state != nil and assigns.state.open?,
        busy?: assigns.state != nil and assigns.state.busy?,
        voice: assigns.state && assigns.state.voice,
        voice?: assigns.state != nil and assigns.state.config.voice != nil
      )

    ~H"""
    <.panel id={@id} heading={@heading}>
      <:actions>
        <.button :if={@state == nil} id={@id <> "-open"} variant="secondary" phx-click="fa_open">
          Open the assistant
        </.button>
        <.button
          :if={@state != nil and not @open?}
          id={@id <> "-reopen"}
          variant="secondary"
          phx-click="fa_reopen"
        >
          Open the assistant
        </.button>
        <.button :if={@open?} id={@id <> "-close"} variant="secondary" phx-click="fa_close">
          Close
        </.button>
      </:actions>
      <div :if={not @open?} class="fa-intro">{render_slot(@intro)}</div>
      <.stack :if={@open?}>
        <.cluster :if={@voice?}>
          <.button
            :if={@voice == nil}
            id={@id <> "-voice-start"}
            phx-click="fa_voice_start"
            disabled={@busy?}
          >
            Start talking
          </.button>
          <.button :if={@voice != nil} id={@id <> "-voice-stop"} phx-click="fa_voice_stop">
            Stop talking
          </.button>
          <.status
            :if={@voice != nil}
            id={@id <> "-voice-state"}
            label={voice_label(@voice.status)}
            tone={if @voice.status == :connecting, do: "warning", else: "success"}
          />
        </.cluster>
        <div
          id={@id <> "-voice"}
          phx-hook=".FormAssistantVoice"
          phx-update="ignore"
          class="fa-voice"
          hidden
        >
        </div>
        <div id={@id <> "-turns"} class="fa-turns" phx-update="stream" aria-live="polite">
          <p :for={{dom_id, turn} <- @turns} id={dom_id} class="fa-turn" data-speaker={turn.speaker}>
            <span class="fa-turn-who">{if turn.speaker == :owner, do: "You", else: "Assistant"}</span>
            <span>{turn.text}</span>
          </p>
        </div>
        <p :if={@busy?} id={@id <> "-busy"} class="fa-busy" role="status">
          The assistant is working on it.
        </p>
        <.form for={%{}} as={:say} id={@id <> "-say"} phx-submit="fa_say">
          <div class="fa-say">
            <.field
              id={@id <> "-message"}
              name="say[message]"
              value=""
              label={if @voice, do: "Or type to the assistant", else: "Type to the assistant"}
              autocomplete="off"
              disabled={@busy?}
            />
            <.button type="submit" id={@id <> "-send"} disabled={@busy?}>Send</.button>
          </div>
        </.form>
      </.stack>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FormAssistantVoice">
        // The microphone and the speaker for a voice session. The server says
        // when to start and stop, and sends the assistant's audio. Audio is
        // 16-bit PCM at the server's rate (24 kHz), base64, both ways.
        const toBase64 = (int16) => {
          const bytes = new Uint8Array(int16.buffer)
          let binary = ""
          for (let i = 0; i < bytes.length; i += 0x8000) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000))
          }
          return btoa(binary)
        }
        const fromBase64 = (b64) => {
          const binary = atob(b64)
          const bytes = new Uint8Array(binary.length)
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
          return new Int16Array(bytes.buffer)
        }
        export default {
          mounted() {
            this.handleEvent("fa:voice_start", ({rate}) => this.start(rate))
            this.handleEvent("fa:voice_stop", () => this.stop())
            this.handleEvent("fa:voice_audio", ({audio}) => this.play(audio))
          },
          destroyed() { this.stop() },
          async start(rate) {
            try {
              this.rate = rate
              this.context = new AudioContext({sampleRate: rate})
              this.stream = await navigator.mediaDevices.getUserMedia({
                audio: {echoCancellation: true, noiseSuppression: true, channelCount: 1}
              })
              const source = this.context.createMediaStreamSource(this.stream)
              this.processor = this.context.createScriptProcessor(2048, 1, 1)
              const mute = this.context.createGain()
              mute.gain.value = 0
              let pending = []
              let count = 0
              this.processor.onaudioprocess = (event) => {
                const input = event.inputBuffer.getChannelData(0)
                const chunk = new Int16Array(input.length)
                for (let i = 0; i < input.length; i++) {
                  const s = Math.max(-1, Math.min(1, input[i]))
                  chunk[i] = s < 0 ? s * 0x8000 : s * 0x7fff
                }
                pending.push(chunk)
                count += chunk.length
                if (count >= rate / 10) {
                  const joined = new Int16Array(count)
                  let at = 0
                  for (const part of pending) { joined.set(part, at); at += part.length }
                  pending = []
                  count = 0
                  this.pushEvent("fa_voice_audio", {audio: toBase64(joined)})
                }
              }
              source.connect(this.processor)
              this.processor.connect(mute)
              mute.connect(this.context.destination)
              this.playhead = this.context.currentTime
            } catch (error) {
              this.stop()
              this.pushEvent("fa_voice_error", {message: error.message || String(error)})
            }
          },
          play(audio) {
            if (!this.context) return
            const samples = fromBase64(audio)
            const buffer = this.context.createBuffer(1, samples.length, this.rate)
            const channel = buffer.getChannelData(0)
            for (let i = 0; i < samples.length; i++) channel[i] = samples[i] / 0x8000
            const node = this.context.createBufferSource()
            node.buffer = buffer
            node.connect(this.context.destination)
            this.playhead = Math.max(this.playhead, this.context.currentTime)
            node.start(this.playhead)
            this.playhead += buffer.duration
          },
          stop() {
            if (this.processor) { this.processor.disconnect(); this.processor.onaudioprocess = null }
            if (this.stream) this.stream.getTracks().forEach((track) => track.stop())
            if (this.context) this.context.close().catch(() => {})
            this.processor = null
            this.stream = null
            this.context = null
          }
        }
      </script>
    </.panel>
    """
  end

  @doc "The draft bar: the changes not saved, and Undo, Redo, Save and Discard."
  attr(:id, :string, required: true)
  attr(:state, :any, required: true, doc: "the :form_assistant assign")

  def draft_bar(%{state: nil} = assigns), do: ~H""

  def draft_bar(assigns) do
    assigns = assign(assigns, :changed, length(Draft.changed_fields(assigns.state.draft)))

    ~H"""
    <div id={@id} class="fa-draft-bar" role="region" aria-label="Changes not saved">
      <p id={@id <> "-count"} class="fa-draft-count">
        {case @changed do
          0 -> "No changes yet. Nothing is saved until you choose Save."
          1 -> "1 change not saved"
          n -> "#{n} changes not saved"
        end}
      </p>
      <.cluster>
        <.button
          id={@id <> "-undo"}
          variant="secondary"
          phx-click="fa_undo"
          disabled={@state.busy? or @state.draft.done == []}
        >
          Undo
        </.button>
        <.button
          id={@id <> "-redo"}
          variant="secondary"
          phx-click="fa_redo"
          disabled={@state.busy? or @state.draft.undone == []}
        >
          Redo
        </.button>
        <.button id={@id <> "-save"} phx-click="fa_save" disabled={@state.busy? or @changed == 0}>
          Save
        </.button>
        <.button
          id={@id <> "-discard"}
          variant="secondary"
          phx-click="fa_discard"
          disabled={@state.busy?}
          data-confirm={if @changed > 0, do: "Discard the changes not saved?"}
        >
          Discard
        </.button>
      </.cluster>
    </div>
    """
  end

  @doc """
  The changes not saved in one section of the form, each with who made it
  and the assistant's reason. Each note's id is `fa-changed-<field>`.
  """
  attr(:state, :any, required: true, doc: "the :form_assistant assign")
  attr(:section, :string, required: true)

  def change_notes(%{state: nil} = assigns), do: ~H""

  def change_notes(assigns) do
    draft = assigns.state.draft

    notes =
      for id <- Draft.changed_fields(draft),
          field = Form.field(draft.form, id),
          field.section == assigns.section,
          do: {field, note(Draft.last_change(draft, id))}

    assigns = assign(assigns, :notes, notes)

    ~H"""
    <ul :if={@notes != []} class="fa-changes" aria-label="Changes not saved">
      <li :for={{field, text} <- @notes} id={"fa-changed-#{field.id}"} class="fa-change">
        <strong>{field.label}</strong> {text}
      </li>
    </ul>
    """
  end

  defp note(%{by: :assistant, reason: reason}) when is_binary(reason) and reason != "",
    do: "changed by the assistant: #{reason}. Not saved."

  defp note(%{by: :assistant}), do: "changed by the assistant. Not saved."
  defp note(_change), do: "changed by you. Not saved."

  defp voice_label(:connecting), do: "Connecting"
  defp voice_label(:speaking), do: "Assistant speaking"
  defp voice_label(_status), do: "Listening"
end
