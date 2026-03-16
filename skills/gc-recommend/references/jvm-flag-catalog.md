# JVM GC Flag Catalog

Comprehensive reference of GC-related JVM flags for gc-exorcist recommendations.

---

## Heap Sizing

### -Xms / -Xmx (Initial and Maximum Heap Size)

| Property | Value |
|----------|-------|
| Default | Platform-dependent (typically 1/64 and 1/4 of physical memory) |
| What it does | Sets the initial (-Xms) and maximum (-Xmx) heap size |
| When to change | Always set explicitly for production workloads |
| Recommended | Set -Xms equal to -Xmx in production to avoid resize pauses |

Example:
```
-Xms4g -Xmx4g
```

### -XX:MaxRAMPercentage

| Property | Value |
|----------|-------|
| Default | 25.0 |
| What it does | Sets maximum heap as a percentage of available RAM (used when -Xmx is not set) |
| When to change | Container deployments where absolute memory is not known at build time |
| Recommended | 75.0 for dedicated containers (leaves 25% for off-heap, metaspace, threads) |

Example:
```
-XX:MaxRAMPercentage=75.0
```

### -XX:MinRAMPercentage

| Property | Value |
|----------|-------|
| Default | 50.0 |
| What it does | Sets maximum heap percentage for JVMs with small total memory (< ~200MB). Despite the name, this is a maximum, not a minimum |
| When to change | Small container deployments with less than 200MB total memory |
| Recommended | 50.0 (default is usually fine) |

### -XX:NewRatio

| Property | Value |
|----------|-------|
| Default | 2 (young gen = 1/3 of heap) |
| What it does | Ratio of old generation to young generation size. NewRatio=2 means old is 2x young |
| When to change | When GC logs show excessive young GC frequency or promotion failures |
| Recommended | 2-3 for web apps; 1 for apps that create many short-lived objects |

### -XX:MetaspaceSize

| Property | Value |
|----------|-------|
| Default | ~21MB (platform-dependent) |
| What it does | Sets the initial metaspace size threshold that triggers GC. Metaspace will grow beyond this but GC is triggered at this point |
| When to change | Spring Boot and large framework apps that load many classes at startup |
| Recommended | 256m for Spring Boot apps to avoid early unnecessary GCs |

Example:
```
-XX:MetaspaceSize=256m
```

### -XX:MaxMetaspaceSize

| Property | Value |
|----------|-------|
| Default | Unlimited (bounded only by native memory) |
| What it does | Hard cap on metaspace size. Prevents runaway class loading from exhausting native memory |
| When to change | Always set in production to prevent unbounded growth |
| Recommended | 512m for typical Spring Boot apps; increase if ClassLoader leaks are not the concern |

Example:
```
-XX:MaxMetaspaceSize=512m
```

---

## G1GC Tuning

### -XX:+UseG1GC

| Property | Value |
|----------|-------|
| Default | Enabled by default since JDK 9 |
| What it does | Selects the G1 (Garbage-First) garbage collector |
| When to change | Explicitly set when you need to ensure G1 is used regardless of JDK defaults |
| Recommended | General-purpose web/API workloads, heaps from 2GB to 16GB |

### -XX:MaxGCPauseMillis

| Property | Value |
|----------|-------|
| Default | 200 |
| What it does | Target maximum GC pause time in milliseconds. G1 adapts its behavior to try to meet this goal |
| When to change | Lower for latency-sensitive apps; raise for throughput-oriented apps |
| Recommended | 200 for general web apps; 50-100 for latency-sensitive; 500+ for batch |

Example:
```
-XX:MaxGCPauseMillis=100
```

### -XX:G1HeapRegionSize

| Property | Value |
|----------|-------|
| Default | Ergonomically determined (1MB to 32MB, targeting ~2048 regions) |
| What it does | Size of G1 heap regions. Objects larger than 50% of region size are humongous objects |
| When to change | When GC logs show frequent humongous allocations. Increase region size so objects fit in a single region |
| Recommended | Power of 2 between 1m and 32m. Set to 2x your largest common allocation if humongous allocations are a problem |

Example:
```
-XX:G1HeapRegionSize=16m
```

### -XX:G1ReservePercent

| Property | Value |
|----------|-------|
| Default | 10 |
| What it does | Percentage of heap kept as free reserve to reduce promotion failure risk |
| When to change | Increase if you see evacuation failures or to-space exhaustion in GC logs |
| Recommended | 10-20 |

### -XX:G1MixedGCLiveThresholdPercent

| Property | Value |
|----------|-------|
| Default | 85 |
| What it does | Old regions with live data above this percentage are excluded from mixed GC (not worth collecting) |
| When to change | Lower to collect more aggressively; raise if mixed GCs are too long |
| Recommended | 85 (default is usually optimal) |

### -XX:InitiatingHeapOccupancyPercent (IHOP)

| Property | Value |
|----------|-------|
| Default | 45 |
| What it does | Heap occupancy threshold that triggers the start of a concurrent marking cycle |
| When to change | Lower if you see Full GCs caused by late marking; raise if concurrent cycles start too early |
| Recommended | 45 for most workloads. With adaptive IHOP (default since JDK 9), the JVM auto-tunes this |

Note: Since JDK 9, adaptive IHOP (-XX:+G1UseAdaptiveIHOP, on by default) means the JVM adjusts this dynamically. Only set manually if adaptive IHOP is not performing well.

### -XX:G1NewSizePercent

| Property | Value |
|----------|-------|
| Default | 5 |
| What it does | Minimum percentage of heap used for young generation |
| When to change | Increase if young gen is too small, causing very frequent young GCs |
| Recommended | 5-20 |

### -XX:G1MaxNewSizePercent

| Property | Value |
|----------|-------|
| Default | 60 |
| What it does | Maximum percentage of heap used for young generation |
| When to change | Decrease if old gen needs more room; increase for allocation-heavy workloads |
| Recommended | 40-60 |

---

## ZGC Tuning (JDK 15+, production-ready JDK 17+)

### -XX:+UseZGC

| Property | Value |
|----------|-------|
| Default | Disabled |
| What it does | Selects the Z Garbage Collector. Sub-millisecond pause times regardless of heap size |
| When to change | Latency-critical applications where p99 pause time < 10ms is required |
| Recommended | JDK 17+ for production. Heap sizes from 8GB to multi-TB |

### -XX:+ZGenerational (JDK 21+)

| Property | Value |
|----------|-------|
| Default | Enabled by default in JDK 23+; available from JDK 21 |
| What it does | Enables generational mode for ZGC, improving throughput by collecting young objects more frequently |
| When to change | Always enable on JDK 21-22. On JDK 23+ it is the default |
| Recommended | Always use generational ZGC when available |

Example:
```
-XX:+UseZGC -XX:+ZGenerational
```

### -XX:SoftMaxHeapSize

| Property | Value |
|----------|-------|
| Default | Same as -Xmx |
| What it does | Soft limit on heap size. ZGC tries to stay below this but can exceed it if needed |
| When to change | When you want ZGC to be more aggressive about collecting to keep heap usage low, while allowing bursts |
| Recommended | Set to 50-80% of -Xmx |

---

## Shenandoah Tuning

### -XX:+UseShenandoahGC

| Property | Value |
|----------|-------|
| Default | Disabled |
| What it does | Selects the Shenandoah garbage collector. Low-pause-time collector similar to ZGC |
| When to change | Latency-critical applications on OpenJDK, Amazon Corretto, or Red Hat builds |
| Recommended | Not available on Oracle JDK. Use ZGC on Oracle JDK instead |

### -XX:ShenandoahGCHeuristics

| Property | Value |
|----------|-------|
| Default | adaptive |
| What it does | Controls when Shenandoah triggers GC cycles. Options: adaptive, static, compact, aggressive |
| When to change | Rarely needs changing. `adaptive` handles most workloads well |
| Recommended | adaptive (default) |

---

## Parallel GC Tuning

### -XX:+UseParallelGC

| Property | Value |
|----------|-------|
| Default | Was default before JDK 9 |
| What it does | Selects the Parallel (throughput) garbage collector |
| When to change | Batch processing, offline computation, or throughput-critical workloads where pause time is acceptable |
| Recommended | Batch jobs, data processing pipelines |

### -XX:ParallelGCThreads

| Property | Value |
|----------|-------|
| Default | Number of available processors (up to 8), then 5/8 of additional processors |
| What it does | Number of threads used during parallel GC phases |
| When to change | In containers where CPU is limited; when GC threads compete with application threads |
| Recommended | Set to number of available CPUs in containers |

---

## Diagnostic and Safety Flags

### -XX:+HeapDumpOnOutOfMemoryError

| Property | Value |
|----------|-------|
| Default | Disabled |
| What it does | Generates a heap dump (HPROF file) when an OutOfMemoryError is thrown |
| When to change | Always enable in production |
| Recommended | Always enabled |

### -XX:HeapDumpPath

| Property | Value |
|----------|-------|
| Default | Current working directory |
| What it does | Directory or file path for heap dump output |
| When to change | Set to a known writable directory with sufficient disk space |
| Recommended | /tmp/heapdump or a mounted volume in containers |

Example:
```
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp/heapdump
```

### -XX:+DisableExplicitGC

| Property | Value |
|----------|-------|
| Default | Disabled (System.gc() is allowed) |
| What it does | Ignores calls to System.gc(). Prevents application or library code from triggering Full GC |
| When to change | Enable unless NIO direct buffers or RMI depend on explicit GC |
| Recommended | Enable in most production deployments. Note: some NIO-heavy applications need explicit GC for direct buffer reclamation |

### -XX:+ExitOnOutOfMemoryError

| Property | Value |
|----------|-------|
| Default | Disabled |
| What it does | JVM exits immediately on OutOfMemoryError. Useful in container environments where orchestrators restart failed containers |
| When to change | Container/Kubernetes deployments where a restart is preferable to a limping JVM |
| Recommended | Enable in Kubernetes/container environments |

### -XX:NativeMemoryTracking

| Property | Value |
|----------|-------|
| Default | off |
| What it does | Tracks JVM native memory usage. Options: off, summary, detail |
| When to change | Diagnosing native memory leaks or understanding total JVM memory footprint |
| Recommended | summary for production monitoring (1-2% overhead); detail for diagnostics only |

Example:
```
-XX:NativeMemoryTracking=summary
```

Then query with: `jcmd <pid> VM.native_memory summary`

---

## Container Awareness Flags

### -XX:+UseContainerSupport

| Property | Value |
|----------|-------|
| Default | Enabled since JDK 10 |
| What it does | JVM detects container CPU and memory limits from cgroups |
| When to change | Should not need to change; verify it is not disabled |
| Recommended | Leave enabled (default) |

### -XX:ActiveProcessorCount

| Property | Value |
|----------|-------|
| Default | Auto-detected from container CPU limits |
| What it does | Overrides the number of CPUs the JVM sees. Affects GC thread count and ForkJoinPool sizing |
| When to change | When container CPU limits are fractional and JVM misdetects (e.g., sees 1 CPU with 2.5 CPU limit) |
| Recommended | Set explicitly if GC thread count is wrong in container logs |

---

## String and Compiler Flags (GC-Adjacent)

### -XX:+UseStringDeduplication

| Property | Value |
|----------|-------|
| Default | Disabled |
| What it does | G1GC/ZGC deduplicate String objects that have identical char arrays, reducing heap usage |
| When to change | Applications with many duplicate strings (e.g., parsing CSV, JSON with repeated field names) |
| Recommended | Enable if heap analysis shows significant string duplication. Adds minor GC overhead |

### -XX:+AlwaysPreTouch

| Property | Value |
|----------|-------|
| Default | Disabled |
| What it does | Touches all heap pages at JVM startup, forcing the OS to allocate physical memory immediately |
| When to change | Production deployments where consistent performance from first request matters |
| Recommended | Enable for production. Increases startup time but avoids page faults during runtime |
