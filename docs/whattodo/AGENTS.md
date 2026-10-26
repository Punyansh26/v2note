# Documentation-Only Guidelines

These rules apply to work in `docs/` and take precedence over general project guidance when working there.

## Scope and safety

- Treat documentation tasks as research and writing tasks only. Do not execute code, shell commands, scripts, tests, builds, migrations, database queries, or other operational actions while working in `docs/`.
- Do not create or modify application code, scripts, configuration, infrastructure, or other non-Markdown files. Do not write code or executable examples unless the user explicitly asks for them.
- Create or edit Markdown documentation only, and only to the extent requested. Do not make implementation changes as a side effect of documenting an issue.
- Reading files and using read-only research tools, including the internet, is allowed. Never submit project code, credentials, or other sensitive material to external services.

## Research and writing

- Explore the relevant project documentation and sources before making claims. For current or externally verifiable information, research the internet and prioritize authoritative, primary sources.
- Link sources close to the claims they support. Include publication or access dates when useful, and distinguish verified facts from assumptions, recommendations, and unresolved questions.
- Cross-check important claims, note conflicts or uncertainty, and avoid presenting unsupported details as fact.
- Preserve the existing documentation's organization and conventions. Keep content focused, accurate, and useful to its intended reader.
- Ask the user for clarification when the requested scope, audience, or a consequential decision is unclear; otherwise proceed with a reasonable, explicit assumption.

## Code explanations

- When the user explicitly asks for a code explanation, assume they are new to programming and this is their first project. Explain thoroughly in plain language: what the code does, how the important parts work together, and unfamiliar terms or concepts. Use a small example when it helps, and do not assume prior knowledge.
- Explaining code does not authorize changing or executing it. Continue to follow the documentation-only rules unless the user explicitly asks for code changes.
