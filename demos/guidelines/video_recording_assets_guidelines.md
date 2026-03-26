# Video Recording Assets Guide

Use this guide when creating recording-support assets for a demo video.

These assets are separate from the main video outline. The outline explains the story. The recording assets help the presenter record it cleanly.

## Purpose

The goal is to create small, practical files that reduce presenter error during recording.

These assets should help the presenter:

- keep the talk track tight
- stay aligned to the validated runtime story
- know exactly which commands to run
- know what output lines matter
- record in sections that are easy to edit later

## Standard Location

Store recording assets in a demo-local `video/` directory.

Examples:

- `demos/secrets_manager/summon_aws_auth/video/video_demo_outline.md`
- `demos/secrets_manager/summon_aws_auth/video/video_recording_run_of_show.md`
- `demos/secrets_manager/summon_aws_auth/video/video_teleprompter_script.md`

## Recommended Asset Set

Most recorded demos should have these files:

- `video_demo_outline.md`
  - the main story, timing, talk track, and on-screen flow
- `video_recording_run_of_show.md`
  - the operator sheet with exact commands, proof points, and section order
- `video_teleprompter_script.md`
  - the presenter-facing spoken script for teleprompter tools such as Textream

Do not create extra files unless they solve a real recording problem.

## Asset Roles

Keep the roles distinct.

`video_demo_outline.md` should contain:

- target length
- intended audience
- scope
- goal and pain framing
- security posture framing
- section-by-section talk track
- on-screen actions

`video_recording_run_of_show.md` should contain:

- recording order
- exact commands to run
- what output to pause on
- what each section proves
- recovery commands if a step fails during recording

`video_teleprompter_script.md` should contain:

- short spoken lines only
- silent cue markers such as `[SECTION]`, `[PAUSE]`, and `[RUN COMMAND]`
- no long command blocks
- no large chunks of explanatory text that sound unnatural when read aloud

## Teleprompter Guidance

Teleprompter scripts should be optimized for reading, not for documentation completeness.

Use:

- one or two short sentences at a time
- visible non-spoken markers such as `[SECTION] Opening`
- explicit pause markers
- explicit run-command markers

Avoid:

- long paragraphs
- raw command output
- headings that sound like spoken narration
- full documentation text copied into the teleprompter file

## Run Of Show Guidance

The run-of-show file should be optimized for the operator during recording.

For each section, include:

- what to show
- what command to run
- what lines to pause on
- what success proves

This file should let someone record the demo cleanly even if they are not reading the full outline live.

## Source Of Truth

Recording assets should stay aligned to:

- the local `demo_validation.md`
- the local `video_demo_outline.md`
- the shared `demos/guidelines/video_demo_guidelines.md`

Do not invent a recording story that contradicts the validation document.

If the validation flow changes, update the recording assets in the same turn when possible.

## Quality Bar

Before considering recording assets complete, check that:

- the file set lives under the demo's `video/` directory
- the video outline, run of show, and teleprompter script all tell the same story
- commands in the run of show match the validated demo flow
- the teleprompter script reads naturally out loud
- section markers are visually obvious and not meant to be spoken
- the assets help the presenter record in clean, editable sections

## Minimal Example

```md
# Demo Teleprompter Script

[SECTION] Opening

This demo shows how the workload authenticates to CyberArk at runtime.

[PAUSE]

The key point is that identity and authorization stay under centralized control.

[SECTION] Run The Demo

[RUN COMMAND]

This command proves the identity, policy, and delivery path together.
```
