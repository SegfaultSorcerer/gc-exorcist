# Contributing to gc-exorcist

Thanks for your interest in improving gc-exorcist! This guide will help you get started.

---

## Reporting Bugs

Open a [GitHub issue](https://github.com/SegfaultSorcerer/gc-exorcist/issues/new) and include:

- **What you expected** vs. **what happened**
- The GC log format you were working with (JDK version, collector)
- The command or skill you ran
- Any error output from the terminal
- Your OS and JDK version (`java -version`)

If possible, attach a sanitized snippet of the GC log that triggers the issue.

## Suggesting Features

Feature requests are welcome. Open an issue with the `enhancement` label and describe:

- The problem you're trying to solve
- How you envision the solution working
- Whether it fits as a skill, hook, or script

---

## Development Setup

```bash
git clone https://github.com/SegfaultSorcerer/gc-exorcist.git
cd gc-exorcist
./scripts/check-prerequisites.sh
```

The prerequisite checker will tell you if anything is missing (JDK, awk, jcmd, etc.).

### Project Layout

```
skills/          # Claude Code slash command definitions
hooks/           # Automation hooks (Dockerfile check, GC log warning)
scripts/         # Shell scripts (gc-parser, gc-capture, check-prerequisites)
docs/            # Internal documentation and reference material
```

---

## Testing

Run skills against the sample GC logs in `docs/` or generate your own:

1. **Produce a GC log** from any Java application with `-Xlog:gc*:file=gc.log` (JDK 9+) or `-XX:+PrintGCDetails -Xloggc:gc.log` (JDK 8).
2. **Run the skill** you changed — e.g., `/gc-analyze gc.log` — and verify the output is correct.
3. **Compare before/after** if you modified parsing logic: run `/gc-compare` with two logs to confirm delta calculations.
4. **Cross-version check**: if your change touches log parsing, test with at least one JDK 8 log and one JDK 17+ log.

For shell scripts, run [ShellCheck](https://www.shellcheck.net/) before submitting:

```bash
shellcheck scripts/*.sh
```

---

## Code Style

### Bash scripts

- Must pass `shellcheck` with zero warnings.
- Use POSIX-compatible `awk` unless `gawk` is explicitly required (document it if so).
- Quote all variables: `"$var"`, not `$var`.
- Use `set -euo pipefail` at the top of every script.
- Prefer functions over inline logic for anything non-trivial.

### Skill and hook definitions

- Follow the existing YAML/Markdown structure in `skills/` and `hooks/`.
- Keep prompts clear and deterministic — avoid vague instructions.
- Include example output in skill descriptions where it helps.

### General

- Follow the [SegfaultSorcerer coding conventions](https://github.com/SegfaultSorcerer/.github/blob/main/CODING_CONVENTIONS.md) for shared standards across the ecosystem.

---

## Pull Request Process

1. **Fork** the repo and create a feature branch from `main`.
2. **Make your changes** — keep commits focused and well-described.
3. **Test** as described above.
4. **Open a PR** against `main` with:
   - A clear title summarizing the change
   - A description of *what* and *why*
   - Any relevant issue numbers (`Closes #123`)
5. A maintainer will review. Expect feedback — it's collaborative, not adversarial.

Small, focused PRs are reviewed faster than large ones.

---

## License

By contributing, you agree that your contributions will be dual-licensed under [MIT](LICENSE-MIT) and [Apache 2.0](LICENSE-APACHE), consistent with the project's licensing.
