# Deployment guide

OTP form assistant is a library application. It runs inside the host's
BEAM release. It has no separate server, database, container, or listening port.
Deploy the host to deploy this capability.

## Runtime requirements

Use the Elixir and Erlang/OTP versions supported by the package.
Version 0.1.0 targets Elixir 1.20 and Erlang/OTP 29.
The host also needs Phoenix LiveView 1.2 and Armature 0.4.

Typed conversations need a host model adapter. Voice also needs an authenticated
transport, HTTPS, browser microphone permission, and the generated hook.
Model availability and provider access belong to the host's configuration.

## Configuration

| Setting | Default or requirement |
| --- | --- |
| `Config.form` | Required host form module. |
| `Config.scope` | Required opaque host authorization scope. |
| `Config.respond` | Required function for model requests. |
| `Config.record` | Required function for conversation events. |
| `Config.text_model` | Required model identifier. |
| `Config.voice` | Nil; text-only use. |
| `Voice.Options.transport` | Required when voice is enabled. |
| `Voice.Options.model` | Required voice model identifier. |
| `Voice.Options.voice` | Required voice identifier. |
| `Voice.Options.delegate_model` | Required model for voice tools. |
| `Voice.Options.supervisor` | `FormAssistant.Voice.Sessions`. |
| `Voice.Options.limit_ms` | 1,200,000 milliseconds (20 minutes). |
| Runtime supervisor `:name` | `FormAssistant.Supervisor`. |
| Runtime supervisor `:sessions` | `FormAssistant.Voice.Sessions`. |

The package defines no production environment variables or secret files.
The host supplies configuration per conversation. Keep credentials in the
platform secret store and expose them only to the host's network adapter.

## Build a host release

1. Publish the package version before updating a production consumer.
2. Declare a semantic version requirement in the host's `mix.exs`.
3. Run `mix deps.get` in the host.
4. Commit the host's updated `mix.lock`.
5. Run the host's complete checks.
6. Compile the host for production.
7. Build its assets after dependency compilation.
8. Assemble the host release with `MIX_ENV=prod mix release`.
9. Deploy the assembled release through the host's deployment procedure.

Use the host's normal asset task for step 7. For a standard Phoenix project,
this is often `MIX_ENV=prod mix assets.deploy`.
The target needs the release and its assets, not this repository or Mix.

Do not deploy a local path override. Do not include an embedded copy of the
same `FormAssistant` modules. Two implementations cannot share module names
inside one VM.

This extraction has not published version 0.1.0 to Hex or migrated the
original phone app. Its archive and local consumer check are ready for trials.

## Start and stop

Text-only use needs no child in the host's supervision tree.
For voice, add `FormAssistant.Supervisor` before the endpoint starts accepting
requests. Match its session supervisor name in `Voice.Options`.

Each voice conversation is a temporary child. A failure does not start a new
external conversation. The session monitors its owning page and normally ends
when that page exits. The host chooses when a person may start a session.

The package provides no built-in admission switch or drain command.
Before a planned restart, stop admitting new sessions in the host and wait
for active sessions to end.

`DynamicSupervisor.which_children/1` lists voice
children for the configured supervisor. `FormAssistant.Voice.Session.stop/1`
requests a normal close when an operator must end a session.

Normal session stop sends a provider close event. Forced process or VM shutdown
does not guarantee that close event or a final recorded notice. In-memory
drafts and typed response IDs are not durable across process termination.

## Upgrades and rollback

Replace the host release, or use a rolling deployment. The package has
no `.appup` or `relup` plan and no tested hot-upgrade contract. Replacing its
modules in a running node is not a supported deployment procedure.

A rolling deployment can preserve service availability while still dropping
individual LiveView connections. Drain sessions before removing an old node.
The package does not move active drafts or voice sessions between nodes.

To roll back, deploy the previous host release with its matching browser assets
and lockfile. Reconnect users and reload their saved form values.

The package cannot recover unsaved in-memory changes. Host-side schema
changes need their own compatible migration and rollback plan.

## Health and troubleshooting

The capability has no health endpoint. Use the host's checks for HTTP,
database access, provider connectivity, and static assets.

| Symptom | Checks |
| --- | --- |
| Panel does not render | Check compilation and component imports. |
| Voice button is absent | Confirm `Config.voice` contains voice options. |
| Voice process is missing | Check the configured supervisor and its child. |
| Unknown browser hook | Import the hooks and rebuild the JavaScript. |
| Microphone fails | Check HTTPS, permission, and the audio device. |
| Bad audio | Check PCM16, 24 kHz, base64, and protocol support. |
| Text fails | Check adapter access, timeouts, responses, and model. |
| Save is refused | Check scope, validation, and storage errors. |
| Draft disappears | Reload saved values. Drafts are not persistent. |

The voice process logs connection and send failures. Redact sensitive provider
errors in the host transport. Do not log credentials, raw audio, or unrelated
records. The host's event store is the source for conversation history.

## Publish documentation

The repository's Quality workflow runs on pushes to `main`, version tags,
and manual dispatch. It runs every gate in `.hone-gates.json`.
On `main`, it then builds clean ExDoc output in the development environment.
A dependent job deploys that output to GitHub Pages.

The published site contains these guides and the API reference. Source links
identify the revision used by Actions. Tag builds run checks but do not replace
the current documentation site.

Deployment uses the `github-pages` environment and GitHub's short-lived identity
token. It needs no publishing credential file.

1. Update the relevant guide when behavior or operation changes.
2. Run `MIX_ENV=test mix deps.get`.
3. Run `MIX_ENV=test mix quality`.
4. Run `MIX_ENV=dev mix docs --warnings-as-errors`.
5. Commit and push the change to `main`.
6. Check the Actions deployment result.
7. Open the published guides and confirm navigation works.

To retry an infrastructure failure, use the Quality workflow's manual dispatch
on `main`. To restore earlier documentation, revert the relevant source change
and push `main`. Do not edit generated HTML or maintain a separate docs branch.

## Publish the package

Run all gates before publishing a package version. `mix hex.build` includes
these guides and the stylesheet. The consumer gate compiles and tests that
archive in a separate temporary project.

Update the version and changelog for a release. Publish with `mix hex.publish`
using a credential supplied in memory. Tag the released version after its
checks pass. Documentation deployment does not publish a package to Hex.

The repository remains unregistered with Foundry, as Stacey requested.
GitHub Actions covers its own checks and documentation deployment.
