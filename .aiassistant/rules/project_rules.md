---
apply: always
---

# Project Rules

## File creation and editing

When the user explicitly asks to create, write, update, or modify a file, the assistant should perform the change directly in the project whenever the environment supports file editing.

Examples of explicit permission:
- "create the file"
- "write the file"
- "update README.md"
- "add this doc"
- "modify that script"

In these cases:
- create the file if it does not exist
- update the file if it already exists
- prefer making the actual project change over only providing preview content
- after making the change, clearly summarize what was created or updated

If the environment does not support direct file modification:
- clearly say that the file could not be written
- explain that the limitation is due to missing write capability in the current session
- provide the exact file content as a fallback

## Preview behavior

Do not present generated file content as if it has already been saved unless the file was actually written to disk.

If the user asks to preview a file:
- show the content
- state whether it is only a preview or an actual saved file

## New markdown files

When the user asks for a review, summary, documentation, or notes in markdown:
- prefer creating a new `.md` file in the most relevant directory
- choose a clear filename such as `REVIEW.md`, `NOTES.md`, or `README.md`
- if the user did not specify a filename, state the intended filename before writing it

## Existing file changes

When editing an existing source file:
- make the smallest reasonable change that satisfies the request
- preserve surrounding style and conventions
- avoid unrelated refactoring unless the user asks for it

When editing an existing markdown file:
- preserve the structure and tone unless the user asks for a rewrite
- keep sections concise and scannable

## Confirmation policy

If the user explicitly instructs the assistant to create or modify a file, that counts as approval to make the change.

Do not ask for extra confirmation unless:
- the target file is ambiguous
- the change may overwrite substantial existing content
- the request could affect multiple files and the target set is unclear

## Response expectations after file edits

After writing or updating files:
- state the file path
- briefly summarize the change
- avoid pasting the entire file again unless the user asked for a preview

## Safety and scope

Only create or modify files inside the project workspace.

Do not invent successful file writes.
If a file was not actually created or updated, say so plainly.
