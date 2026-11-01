# OTP form assistant guidance

Read `CHARTER.md` before changing scope.

- Keep production modules under `FormAssistant`. The OTP app is
  `otp_form_assistant`.
- Hosts own authorization, persistence, credentials, and provider connections.
- Do not add product schemas or business-specific prompts.
- Keep voice optional. Text-only hosts start no capability processes.
- Preserve verified protocol shapes. Record evidence before changing them.
- Run every gate in `.hone-gates.json` before pushing. `MIX_ENV=test mix
  quality` runs the checks after dependency fetch.
- Commit scoped changes to `main`. No branches or pull requests.
- Use semantic versions. Publish libraries before updating consumer
  dependencies.
- Tests use synthetic forms and fake transports. Never require live provider
  access.
- Use Armature tokens in CSS. Preserve browser behavior during extraction.
- Keep package assets and hook imports documented in `README.md`.
- Keep full functional, integration, and deployment guides under `guides/`.
  Publish the guides and API reference to GitHub Pages through GitHub Actions.
  Changes to behavior, contracts, or operation must update the matching guide.
- Never write credentials to files. Read secrets from the platform secret store
  into memory.
- Foundry registration requires Stacey's decision. This repository is not
  registered by extraction.
