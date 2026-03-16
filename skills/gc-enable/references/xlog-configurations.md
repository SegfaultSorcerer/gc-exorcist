# Unified Logging (-Xlog) Configuration Reference

Complete reference for JVM unified logging, focused on GC log configuration.

---

## -Xlog Syntax

```
-Xlog:[what][:[output][:[decorators][:output-options]]]
```

### Components

| Component | Description | Example |
|-----------|-------------|---------|
| what | Tag and level selections (what to log) | `gc*=info,gc+phases=debug` |
| output | Where to write logs | `file=gc.log` or `stdout` |
| decorators | Metadata added to each log line | `time,uptime,level,tags` |
| output-options | File rotation settings | `filecount=5,filesize=20M` |

---

## What: Tag and Level Selection

### Syntax

```
tag1[+tag2...][*][=level]
```

- `gc` -- exact match on the `gc` tag
- `gc*` -- matches `gc` and any tag combination starting with `gc` (e.g., gc+phases, gc+heap)
- `gc+phases` -- matches only log messages tagged with both `gc` and `phases`
- `gc*=debug` -- matches gc and subtags at debug level and above

### Log Levels (in order)

| Level | Description |
|-------|-------------|
| off | Disabled |
| error | Errors only |
| warning | Warnings and errors |
| info | Normal operational messages (default) |
| debug | Detailed diagnostic messages |
| trace | Very detailed, high-volume messages |

### GC-Relevant Tags

| Tag Combination | What It Logs |
|----------------|--------------|
| `gc` | Basic GC events (start, end, pause time) |
| `gc+start` | GC cycle start events |
| `gc+heap` | Heap state before/after GC |
| `gc+phases` | Individual GC phase timings (marking, evacuation, etc.) |
| `gc+age` | Object age distribution (tenuring) |
| `gc+alloc` | Allocation statistics and failures |
| `gc+ergo` | Ergonomic decisions (why GC made certain choices) |
| `gc+ref` | Reference processing (soft, weak, phantom, final) |
| `gc+task` | GC worker thread task details |
| `gc+region` | G1 region details |
| `gc+humongous` | G1 humongous object allocations |
| `gc+metaspace` | Metaspace allocation and GC |
| `gc+stringdedup` | String deduplication statistics |
| `gc+compaction` | Compaction details |
| `gc+nmethod` | Code cache / nmethod GC |
| `safepoint` | Safepoint (stop-the-world) events and timings |

---

## Output

| Value | Description |
|-------|-------------|
| `stdout` | Write to standard output (default) |
| `stderr` | Write to standard error |
| `file=<path>` | Write to a file |

### File Output Examples

```
file=gc.log                    # Write to gc.log in working directory
file=/var/log/app/gc.log       # Absolute path
file=gc_%p_%t.log              # %p = PID, %t = startup timestamp
```

---

## Decorators

Metadata prepended to each log line. Specified as a comma-separated list.

| Decorator | Description | Example Output |
|-----------|-------------|----------------|
| `time` | Current date and time (ISO 8601) | `[2024-01-15T10:30:45.123+0000]` |
| `utctime` | UTC date and time | `[2024-01-15T10:30:45.123+0000]` |
| `uptime` | Time since JVM start (seconds) | `[25.432s]` |
| `timemillis` | Milliseconds since epoch | `[1705312245123]` |
| `uptimemillis` | Milliseconds since JVM start | `[25432]` |
| `timenanos` | Nanoseconds since epoch | `[1705312245123456789]` |
| `uptimenanos` | Nanoseconds since JVM start | `[25432000000]` |
| `pid` | Process ID | `[12345]` |
| `tid` | Thread ID | `[0x00007f...]` |
| `level` | Log level | `[info]` |
| `tags` | Log tags | `[gc,phases]` |

### Recommended Decorator Set

For GC analysis, use: `time,uptime,level,tags`

- `time` -- correlate with application events
- `uptime` -- compute intervals between GC events
- `level` -- filter by severity
- `tags` -- identify message category

---

## Output Options

| Option | Description | Example |
|--------|-------------|---------|
| `filecount=N` | Number of rotated log files to keep | `filecount=5` |
| `filesize=NM` | Maximum size per log file before rotation | `filesize=20M` |

When `filecount` and `filesize` are both set, logs rotate automatically. The current log is always the named file; rotated files get `.0`, `.1`, etc. suffixes.

---

## Detail Level Configurations

### Basic (Low Overhead)

```
-Xlog:gc*:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
```

**What you get:** GC event type, pause times, heap before/after, cause.
**What you miss:** Phase breakdown, reference processing, allocation details.
**Overhead:** < 1% CPU, minimal I/O.
**Use when:** Production monitoring, always-on logging, first pass at GC analysis.

### Detailed (Standard)

```
-Xlog:gc*,gc+ref=debug,gc+phases=debug,gc+age=debug,safepoint:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
```

**What you get:** Everything in basic, plus:
- Individual phase timings (marking, evacuation, cleanup)
- Reference processing times (soft, weak, phantom)
- Object age distribution (promotion patterns)
- Safepoint times (time-to-safepoint latency)

**Overhead:** 1-3% CPU, moderate I/O.
**Use when:** Active GC tuning, investigating specific GC issues.

### Trace (Debug)

```
-Xlog:gc*=debug,gc+ergo*=trace,gc+age*=trace,gc+alloc*=trace,safepoint*:file=gc.log:time,uptime,level,tags:filecount=10,filesize=50M
```

**What you get:** Everything in detailed, plus:
- Ergonomic decisions (why G1 chose certain region counts, IHOP adjustments)
- Detailed allocation statistics and allocation failures
- Full age table at every young GC
- All safepoint details

**Overhead:** 3-5% CPU, significant I/O (logs can grow to hundreds of MB/hour).
**Use when:** Deep debugging of specific GC problems. Do not run in production long-term.

---

## JDK 17+ Async Logging

```
-Xlog:async
```

When enabled, log messages are written asynchronously from a dedicated thread, reducing the impact of GC logging on application pause times. Without async logging, the GC thread itself writes the log entry, which can add microseconds to pause times.

**Recommendation:** Always enable on JDK 17+. No reason not to -- it reduces logging overhead with no downside.

**Combined example (JDK 17+ detailed):**
```
-Xlog:async -Xlog:gc*,gc+ref=debug,gc+phases=debug,gc+age=debug,safepoint:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
```

---

## Legacy Flag to Unified Logging Mapping

This table maps JDK 8 (and earlier) GC logging flags to their JDK 9+ unified logging equivalents.

| Legacy Flag (JDK 8) | Unified Equivalent (JDK 9+) | Notes |
|----------------------|------------------------------|-------|
| `-XX:+PrintGC` | `-Xlog:gc` | Basic GC events |
| `-XX:+PrintGCDetails` | `-Xlog:gc*` | Detailed GC events with subtags |
| `-XX:+PrintGCDateStamps` | Decorator: `time` | ISO 8601 timestamp |
| `-XX:+PrintGCTimeStamps` | Decorator: `uptime` | Seconds since JVM start |
| `-XX:+PrintGCApplicationStoppedTime` | `-Xlog:safepoint` | Safepoint / STW times |
| `-XX:+PrintGCApplicationConcurrentTime` | `-Xlog:safepoint` | Time between safepoints |
| `-XX:+PrintTenuringDistribution` | `-Xlog:gc+age=debug` | Object age table |
| `-XX:+PrintAdaptiveSizePolicy` | `-Xlog:gc+ergo=debug` | Ergonomic decisions |
| `-XX:+PrintReferenceGC` | `-Xlog:gc+ref=debug` | Reference processing |
| `-XX:+PrintHeapAtGC` | `-Xlog:gc+heap=debug` | Heap layout before/after |
| `-XX:+PrintGCCause` | Always included in JDK 9+ | GC trigger cause |
| `-XX:+PrintFlagsFinal` | `-XX:+PrintFlagsFinal` (unchanged) | Not part of -Xlog |
| `-Xloggc:<file>` | `-Xlog:...:file=<file>` | Output to file |
| `-XX:+UseGCLogFileRotation` | Output option: `filecount=N` | Automatic with output-options |
| `-XX:NumberOfGCLogFiles=N` | Output option: `filecount=N` | Number of rotated files |
| `-XX:GCLogFileSize=NM` | Output option: `filesize=NM` | Max size per file |
| `-XX:+PrintStringDeduplicationStatistics` | `-Xlog:gc+stringdedup=debug` | String dedup stats |
| `-XX:+PrintPromotionFailure` | `-Xlog:gc+alloc=debug` | Promotion/allocation failure |
| `-XX:+PrintClassHistogramBeforeFullGC` | No direct equivalent | Use `jcmd` instead |
| `-XX:+PrintClassHistogramAfterFullGC` | No direct equivalent | Use `jcmd` instead |

---

## Multiple -Xlog Arguments

You can specify multiple `-Xlog` arguments. Later ones override earlier ones for the same tags. This is useful for sending different detail levels to different outputs:

```
# Basic to stdout, detailed to file
-Xlog:gc:stdout:time,tags -Xlog:gc*,gc+phases=debug:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
```

---

## Quick Copy-Paste Reference

### JDK 8 -- Standard Logging
```
-XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintTenuringDistribution -XX:+PrintGCApplicationStoppedTime -Xloggc:gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=5 -XX:GCLogFileSize=20M
```

### JDK 11 -- Detailed
```
-Xlog:gc*,gc+ref=debug,gc+phases=debug,gc+age=debug,safepoint:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
```

### JDK 17 -- Detailed with Async
```
-Xlog:async -Xlog:gc*,gc+ref=debug,gc+phases=debug,gc+age=debug,safepoint:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
```

### JDK 21 -- Detailed with Async
```
-Xlog:async -Xlog:gc*,gc+ref=debug,gc+phases=debug,gc+age=debug,safepoint:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
```
