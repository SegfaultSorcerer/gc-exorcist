<p align="center">
  <img src="assets/gc-exorcist.png" alt="gc-exorcist" width="100%">
</p>

<h1 align="center">gc-exorcist</h1>

<p align="center">
  <em>Banishing GC demons from your JVM.</em>
</p>

<p align="center">
  <a href="LICENSE-MIT"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <a href="LICENSE-APACHE"><img src="https://img.shields.io/badge/license-Apache_2.0-blue.svg" alt="Apache 2.0"></a>
  <img src="https://img.shields.io/badge/Java-8+-orange.svg" alt="Java 8+">
  <img src="https://img.shields.io/badge/Claude_Code-plugin-blueviolet.svg" alt="Claude Code Plugin">
</p>

<p align="center">
  A CLI-native, Claude Code-integrated tool that turns GC logs into structured tuning recommendations with concrete JVM flag suggestions — designed to run inside <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a>.
</p>

<p align="center">
  4 slash commands. 3 automation hooks. Zero config to get started.
</p>

<p align="center">
  Part of the <a href="https://github.com/SegfaultSorcerer">SegfaultSorcerer</a> Java Tooling Ecosystem.
</p>

---

## Why?

GC tuning is treated like black magic by most Java developers because:

- GC logs are voluminous, cryptic, and formats change across JVM versions
- Most developers never enable GC logging until there's a production incident
- Interpreting pause times, heap curves, and promotion rates requires deep GC algorithm knowledge
- Existing tools are SaaS (GCeasy.io), heavyweight GUI (GCViewer), or abandonware
- No tool connects GC behavior back to application code or Spring configuration

gc-exorcist turns GC logs into structured tuning recommendations with concrete JVM flag suggestions — right in your terminal.

---

## Skills

| Skill | Description |
|-------|-------------|
| `/gc-analyze <file>` | Full GC log analysis with tuning recommendations |
| `/gc-compare <before> <after>` | Compare two GC logs to evaluate tuning impact |
| `/gc-recommend [log]` | Generate recommended JVM GC flags (project-based or data-driven) |
| `/gc-enable` | Generate correct GC logging flags for your JDK version |

### /gc-analyze

Parses a GC log file (JDK 8 legacy or JDK 9+ unified format) and produces a structured report:

- Pause time percentiles (p50, p95, p99, max) per GC type
- Heap health assessment (occupancy, trends, memory leak detection)
- Full GC root cause analysis
- Severity-rated findings (CRITICAL / WARNING / INFO)
- Top 3 actionable tuning recommendations with concrete JVM flags
- Complete copy-pasteable JVM flags block

Works with G1, ZGC, Shenandoah, Parallel, Serial, and CMS collectors.

### /gc-compare

Compare two GC logs side-by-side to measure the impact of a tuning change:

- Delta analysis for all key metrics
- Regression detection (metrics that got worse)
- Overall improvement verdict
- Next-step recommendations

### /gc-recommend

Generate JVM GC flags, either from project analysis or data-driven from a GC log:

- **Without log**: Analyzes pom.xml/build.gradle, Dockerfiles, and run configs to recommend the right GC algorithm and flags
- **With log**: Identifies the primary issue and generates targeted flag adjustments

### /gc-enable

Generate the correct GC logging configuration for your JDK version:

- Auto-detects JDK version
- Three detail levels: basic (production), detailed (troubleshooting), trace (deep analysis)
- Integration snippets for shell, Dockerfile, Maven, Gradle

---

## Hooks

| Hook | Trigger | Behavior |
|------|---------|----------|
| GC Log Warning | JVM starts without GC logging | Suggests `/gc-enable` (opt-in) |
| Dockerfile Check | Writing Dockerfile with `java` | Warns about missing GC flags (always on) |

**Opt-in hooks**: Create `.gc-exorcist/warn-no-gc-log.enabled` to enable the startup warning.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `gc-parser.sh` / `.ps1` | Parse GC logs into structured metrics |
| `gc-capture.sh` / `.ps1` | Enable/disable GC logging on a running JVM via jcmd |
| `check-prerequisites.sh` | Verify required tools are installed |

### gc-capture

Control GC logging on running JVM processes (JDK 9+):

```bash
./scripts/gc-capture.sh enable <PID>      # Start GC logging
./scripts/gc-capture.sh disable <PID>     # Stop GC logging
./scripts/gc-capture.sh status <PID>      # Check current config
./scripts/gc-capture.sh snapshot <PID>    # Quick heap info snapshot
```

---

## Installation

### As a Claude Code Plugin

```bash
claude plugin add SegfaultSorcerer/gc-exorcist
```

### Manual

```bash
git clone https://github.com/SegfaultSorcerer/gc-exorcist.git
cd gc-exorcist
./scripts/check-prerequisites.sh
```

---

## Prerequisites

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| JDK | 8+ | 17+ | Unified logging requires JDK 9+ |
| Claude Code | latest | latest | Plugin support |
| OS | any | any | Bash + PowerShell variants |
| awk | any | gawk | For percentile computation |
| jcmd | JDK 7+ | JDK 17+ | For gc-capture (dynamic logging) |

### Supported GC Log Formats

- JDK 8 legacy format (`-XX:+PrintGCDetails`)
- JDK 9-21+ unified format (`-Xlog:gc*`)
- Rotated log files

---

## Synergies

gc-exorcist works alongside other SegfaultSorcerer tools:

| Tool | Integration |
|------|-------------|
| **thread-necromancer** | Correlate GC pauses with thread dumps — "all threads paused" often means GC |
| **heap-seance** | Heap analysis shows *what* objects consume memory; gc-exorcist shows *how* GC handles it |
| **spring-grimoire** | JPA audit finds lazy loading issues → gc-exorcist shows the allocation rate impact |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

Dual-licensed under [MIT](LICENSE-MIT) and [Apache 2.0](LICENSE-APACHE). Choose whichever suits your needs.
