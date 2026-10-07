# AGENTS.md — lidawake

Short orientation for Cursor agents.

This repo is a free MIT command-line tool. Do not add a menu-bar app, a paid license, or an App Store target.

## Defaults

- On macOS, `make test` builds with warnings as errors, runs `scripts/test.sh`, then runs `scripts/test-linux.sh`.
- On Linux, `make test` runs `scripts/test-linux.sh` only. `scripts/lidawake` is the command. It does not compile.
- The macOS test toggles lid sleep on this Mac and must restore it before exiting. `lidawake off` clears a sticky macOS override. The Linux lock ends when the process ends.
- No secrets. Do not commit a pid file or the macOS build output (the `lidawake` binary at the repo root is gitignored; the source is `main.swift`).

## Docs

README style: sentence-case headings, no emoji decoration, no home-directory paths or LAN addresses in committed docs.

## Close-out

1. `make test` before claiming a change works.
2. This repo's remote is GitHub `Gitilia/lidawake`.
