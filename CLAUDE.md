# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

See [AGENTS.md](AGENTS.md) — same guidance, kept in one file so it doesn't drift between
agents.

**Skills are in `.agents/skills/<name>/SKILL.md`**, not under `.claude/`, so that one set serves
every agent and gets committed — `.claude/` is gitignored. Read the relevant one before creating
a module, writing an ADR, or reconciling the documentation. `make skills` symlinks them into
`.claude/skills/` where Claude Code discovers them; the symlinks are local and the content is
tracked.
