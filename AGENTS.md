# AGENTS.md — lidawake

Short orientation for Cursor agents.

This repo is a free MIT command-line tool. Do not add a menu-bar app, a paid license, or an App Store target.

## Defaults

- `make test` builds with warnings as errors and runs `scripts/test.sh`.
- The test toggles lid-sleep on this Mac and must restore it before exiting. Do not leave `lidawake on` running after a failed test. `lidawake off` clears a sticky override.
- No secrets. Do not commit a pid file or build output (`lidawake` binary is gitignored once produced; the source file is `main.swift`).

## Docs

README style: sentence-case headings, no emoji decoration, no home-directory paths or LAN addresses in committed docs.

## Close-out

1. `make test` before claiming a change works.
2. This repo's remote is GitHub `Gitilia/lidawake`.
