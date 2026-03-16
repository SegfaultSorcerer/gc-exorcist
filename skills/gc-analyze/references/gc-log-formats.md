# GC Log Format Reference

## Unified Logging (JDK 9+)

### Enabling Unified GC Logging

```bash
# Recommended comprehensive logging flags
-Xlog:gc*=info:file=gc.log:time,uptime,level,tags:filecount=5,filesize=100m

# Breakdown:
# -Xlog:<selectors>=<level>:<output>:<decorators>:<output-options>
```

### Log Line Structure

```
[<decorators>][<level>][<tags>] <message>
```

#### Decorators
| Decorator | Flag | Example | Description |
|-----------|------|---------|-------------|
| Uptime | `uptime` | `[0.532s]` | Seconds since JVM start |
| UTC time | `time` | `[2024-01-15T10:30:45.123+0000]` | Wall clock time |
| Elapsed time | `utctime` | Same as time but UTC | UTC wall clock |
| Level | `level` | `[info]` | Log level |
| Tags | `tags` | `[gc,start]` | Category tags |
| PID | `pid` | `[12345]` | Process ID |
| TID | `tid` | `[0x00007f...]` | Thread ID |

### Key Tag Combinations

| Tags | What It Captures | Example |
|------|-----------------|---------|
| `gc` | GC event summary lines | `GC(42) Pause Young (Normal) (G1 Evacuation Pause) 256M->128M(512M) 12.345ms` |
| `gc,start` | GC event start marker | `GC(42) Pause Young (Normal) (G1 Evacuation Pause)` |
| `gc,phases` | GC phase timing breakdown | `GC(42) Phase 1: Mark live objects 3.456ms` |
| `gc,heap` | Heap state before/after GC | `GC(42) Eden regions: 25->0(25)` |
| `gc,metaspace` | Metaspace usage | `GC(42) Metaspace: 45678K(46080K)->45678K(46080K)` |
| `gc,age` | Tenuring distribution | `GC(42) Desired survivor size 1048576 bytes, new threshold 7 (max 15)` |
| `gc,alloc` | Allocation statistics | Allocation rate and TLAB info |
| `gc,ergo` | Ergonomic decisions | `GC(42) Initiate concurrent cycle (occupancy higher than threshold)` |
| `gc,humongous` | Humongous object info | `GC(42) Humongous object allocation request: 2097152 bytes` |
| `gc,ref` | Reference processing | `GC(42) SoftReference: 0, WeakReference: 42, FinalReference: 7, PhantomReference: 3` |
| `gc,task` | GC thread task details | Worker thread statistics |
| `gc,cpu` | CPU time breakdown | `GC(42) User=0.05s Sys=0.00s Real=0.01s` |
| `safepoint` | Safepoint information | `Safepoint "G1CollectFull", Time since last: 1234567 ns...` |

### GC Event Patterns to Match

#### Young GC Patterns
```
# G1 Young GC
GC(<id>) Pause Young (Normal) (G1 Evacuation Pause) <before>M-><after>M(<heap>M) <time>ms
GC(<id>) Pause Young (Concurrent Start) (G1 Evacuation Pause) ...
GC(<id>) Pause Young (Mixed) (G1 Evacuation Pause) ...
GC(<id>) Pause Young (Prepare Mixed) (G1 Evacuation Pause) ...

# Parallel GC Young
GC(<id>) Pause Young (Allocation Failure) <before>M-><after>M(<heap>M) <time>ms

# Serial GC Young
GC(<id>) Pause Young (Allocation Failure) <before>K-><after>K(<heap>K) <time>ms

# ZGC (JDK 17+)
GC(<id>) Minor Collection (Allocation Rate) <before>M-><after>M(<heap>M) <time>ms
GC(<id>) Minor Collection (Proactive) ...

# Shenandoah
GC(<id>) Pause Init Mark <time>ms
GC(<id>) Concurrent marking ...
GC(<id>) Pause Final Mark <time>ms
```

#### Full GC Patterns
```
# G1 Full GC
GC(<id>) Pause Full (System.gc()) <before>M-><after>M(<heap>M) <time>ms
GC(<id>) Pause Full (Allocation Failure) ...
GC(<id>) Pause Full (Metadata GC Threshold) ...
GC(<id>) Pause Full (G1 Humongous Allocation) ...
GC(<id>) Pause Full (G1 Compaction Pause) ...
GC(<id>) Pause Full (Ergonomics) ...
GC(<id>) Pause Full (Heap Dump Initiated GC) ...
GC(<id>) Pause Full (GCLocker Initiated GC) ...

# Parallel Full GC
GC(<id>) Pause Full (Ergonomics) <before>M-><after>M(<heap>M) <time>ms
GC(<id>) Pause Full (Allocation Failure) ...

# ZGC Full (rare)
GC(<id>) Major Collection (Allocation Rate) ...
GC(<id>) Major Collection (Proactive) ...

# Shenandoah degenerated/full
GC(<id>) Pause Degenerated GC (Mark) ...
GC(<id>) Pause Full GC (Allocation Failure) ...
```

#### Concurrent Phase Patterns
```
# G1 Concurrent Marking
GC(<id>) Concurrent Mark Cycle
GC(<id>) Concurrent Mark Cycle <time>ms
GC(<id>) Pause Remark <before>M-><after>M(<heap>M) <time>ms
GC(<id>) Pause Cleanup <before>M-><after>M(<heap>M) <time>ms

# ZGC Concurrent Phases
GC(<id>) Concurrent Mark <time>ms
GC(<id>) Concurrent Process Non-Strong References <time>ms
GC(<id>) Concurrent Relocate <time>ms

# Shenandoah Concurrent Phases
GC(<id>) Concurrent marking <time>ms
GC(<id>) Concurrent evacuation <time>ms
GC(<id>) Concurrent update references <time>ms
```

#### Special Event Patterns
```
# Evacuation failure (G1)
GC(<id>) To-space exhausted

# Humongous allocation
[gc,humongous] GC(<id>) Humongous object allocation ...

# Metaspace
GC(<id>) Metaspace: <used>K(<committed>K)-><used>K(<committed>K) ...

# CPU time
GC(<id>) User=<time>s Sys=<time>s Real=<time>s
```

### Heap Transition Pattern

The standard heap transition format in unified logging:

```
<before_gc>M-><after_gc>M(<max_heap>M)
```

Example: `256M->128M(512M)` means:
- Before GC: 256M used
- After GC: 128M used (128M reclaimed)
- Max heap: 512M configured

For G1 region-based output:
```
Eden regions: 25->0(25)       # 25 regions used -> 0 after GC (25 max)
Survivor regions: 3->3(4)     # 3 -> 3 (some objects survived)
Old regions: 42->38           # 42 -> 38 (4 reclaimed via mixed GC)
Humongous regions: 2->1       # 2 -> 1 humongous region
```

---

## Legacy GC Logging (JDK 8 and earlier)

### Enabling Legacy GC Logging

```bash
-verbose:gc
-XX:+PrintGCDetails
-XX:+PrintGCDateStamps
-XX:+PrintGCTimeStamps
-XX:+PrintGCApplicationStoppedTime
-XX:+PrintGCApplicationConcurrentTime
-XX:+PrintTenuringDistribution
-XX:+PrintAdaptiveSizePolicy
-Xloggc:gc.log
-XX:+UseGCLogFileRotation
-XX:NumberOfGCLogFiles=5
-XX:GCLogFileSize=100M
```

### Legacy Log Line Patterns

#### Young GC
```
2024-01-15T10:30:45.123+0000: 1.234: [GC (Allocation Failure) [PSYoungGen: 65536K->10752K(76288K)] 65536K->12345K(251392K), 0.0123456 secs] [Times: user=0.04 sys=0.00, real=0.01 secs]
```

Structure: `<timestamp>: <uptime>: [GC (<cause>) [<collector>: <young_before>-><young_after>(<young_total>)] <heap_before>-><heap_after>(<heap_total>), <duration> secs]`

#### Full GC
```
2024-01-15T10:30:45.123+0000: 1.234: [Full GC (System.gc()) [PSYoungGen: 1024K->0K(76288K)] [ParOldGen: 12345K->11234K(175104K)] 13369K->11234K(251392K), [Metaspace: 45678K->45678K(1091584K)], 0.1234567 secs] [Times: user=0.20 sys=0.01, real=0.12 secs]
```

#### CMS Phases (Legacy)
```
[GC (CMS Initial Mark) ...]
[CMS-concurrent-mark: 0.123/0.456 secs]
[GC (CMS Final Remark) ...]
[CMS-concurrent-sweep: 0.234/0.567 secs]
[CMS-concurrent-reset: 0.012/0.034 secs]
```

#### G1 Legacy Format
```
1.234: [GC pause (G1 Evacuation Pause) (young), 0.0123456 secs]
   [Parallel Time: 10.0 ms, GC Workers: 8]
      [GC Worker Start (ms): ...]
      [Ext Root Scanning (ms): ...]
      [Update RS (ms): ...]
      [Scan RS (ms): ...]
      [Code Root Scanning (ms): ...]
      [Object Copy (ms): ...]
      [Termination (ms): ...]
      [GC Worker Other (ms): ...]
      [GC Worker Total (ms): ...]
      [GC Worker End (ms): ...]
   [Code Root Fixup: 0.0 ms]
   [Code Root Purge: 0.0 ms]
   [Clear CT: 0.1 ms]
   [Other: 1.2 ms]
      [Choose CSet: 0.0 ms]
      [Ref Proc: 0.5 ms]
      [Ref Enq: 0.0 ms]
      [Redirty Cards: 0.1 ms]
      [Humongous Register: 0.0 ms]
      [Humongous Reclaim: 0.0 ms]
      [Free CSet: 0.1 ms]
   [Eden: 24.0M(24.0M)->0.0B(24.0M) Survivors: 4096.0K->4096.0K Heap: 45.0M(256.0M)->22.0M(256.0M)]
```

---

## Legacy to Unified Logging Mapping

| Legacy Flag | Unified Equivalent |
|-------------|-------------------|
| `-verbose:gc` | `-Xlog:gc` |
| `-XX:+PrintGCDetails` | `-Xlog:gc*` |
| `-XX:+PrintGCDateStamps` | `-Xlog:gc*::time` (decorator) |
| `-XX:+PrintGCTimeStamps` | `-Xlog:gc*::uptime` (decorator) |
| `-XX:+PrintGCApplicationStoppedTime` | `-Xlog:safepoint` |
| `-XX:+PrintGCApplicationConcurrentTime` | `-Xlog:safepoint` |
| `-XX:+PrintTenuringDistribution` | `-Xlog:gc+age*=trace` |
| `-XX:+PrintAdaptiveSizePolicy` | `-Xlog:gc+ergo*=trace` |
| `-XX:+PrintReferenceGC` | `-Xlog:gc+ref*=debug` |
| `-XX:+PrintGCCause` | Always included in unified logging |
| `-Xloggc:<file>` | `-Xlog:gc*:file=<file>` |
| `-XX:+UseGCLogFileRotation` | `-Xlog:gc*:file=<file>::filecount=N,filesize=M` |
| `-XX:+PrintHeapAtGC` | `-Xlog:gc+heap=trace` |
| `-XX:+PrintStringDeduplicationStatistics` | `-Xlog:gc+stringdedup*=debug` |
| `-XX:+PrintClassHistogramBeforeFullGC` | No direct equivalent — use `jcmd` |
| `-XX:+PrintFLSStatistics` | `-Xlog:gc+freelist=trace` |

### Unified Logging Quick Reference

```bash
# Minimal GC logging
-Xlog:gc:file=gc.log

# Standard GC logging (recommended minimum)
-Xlog:gc*:file=gc.log:time,uptime,level,tags:filecount=5,filesize=100m

# Detailed GC logging (for troubleshooting)
-Xlog:gc*=debug:file=gc.log:time,uptime,level,tags:filecount=10,filesize=100m

# Maximum detail (generates large logs)
-Xlog:gc*=trace:file=gc.log:time,uptime,level,tags:filecount=10,filesize=200m

# Include safepoint info
-Xlog:gc*,safepoint:file=gc.log:time,uptime,level,tags:filecount=5,filesize=100m

# Multiple outputs (console + file)
-Xlog:gc:stdout -Xlog:gc*:file=gc.log:time,uptime,level,tags
```

---

## Regex Patterns for Parsing

### Unified Format Core Patterns

```regex
# GC event summary line (captures: id, type, cause, before, after, heap, duration)
GC\((\d+)\)\s+(Pause \w+(?:\s+\([^)]+\))*)\s+(\d+[MKG])->(\d+[MKG])\((\d+[MKG])\)\s+([\d.]+)ms

# Heap transition (captures: before, after, max)
(\d+[MKG])->(\d+[MKG])\((\d+[MKG])\)

# Duration in ms (captures: duration)
([\d.]+)ms$

# GC ID (captures: id)
GC\((\d+)\)

# Timestamp decorator (captures: datetime)
\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d{4})\]

# Uptime decorator (captures: uptime_seconds)
\[([\d.]+)s\]

# CPU times (captures: user, sys, real)
User=([\d.]+)s\s+Sys=([\d.]+)s\s+Real=([\d.]+)s

# Metaspace line (captures: used_before, committed_before, used_after, committed_after)
Metaspace:\s+(\d+)K\((\d+)K\)->(\d+)K\((\d+)K\)
```

### Legacy Format Core Patterns

```regex
# Young GC (captures: cause, young_before, young_after, young_total, heap_before, heap_after, heap_total, duration)
\[GC\s+\(([^)]+)\)\s+\[\w+:\s+(\d+)K->(\d+)K\((\d+)K\)\]\s+(\d+)K->(\d+)K\((\d+)K\),\s+([\d.]+)\s+secs\]

# Full GC (captures: cause, ... , duration)
\[Full GC\s+\(([^)]+)\)\s+.*,\s+([\d.]+)\s+secs\]

# Times line (captures: user, sys, real)
\[Times:\s+user=([\d.]+)\s+sys=([\d.]+),\s+real=([\d.]+)\s+secs\]
```

### Size Unit Conversion

| Suffix | Multiplier | Example |
|--------|-----------|---------|
| K | 1024 bytes | `65536K` = 64 MB |
| M | 1,048,576 bytes | `256M` = 256 MB |
| G | 1,073,741,824 bytes | `2G` = 2048 MB |
| B | 1 byte | `4096.0B` = 4 KB |
