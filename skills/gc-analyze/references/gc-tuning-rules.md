# GC Tuning Rules

Decision rules for GC log analysis. Each rule specifies a condition, severity level, and recommended action.

---

## Pause Time Rules

| Condition | Severity | Action |
|-----------|----------|--------|
| p99 pause > 500ms for web/API app | CRITICAL | Reduce `MaxGCPauseMillis`, consider G1 or ZGC, increase heap |
| p99 pause > 200ms for API/microservice | WARNING | Tune pause target, check young gen sizing |
| p99 pause > 10ms for trading/real-time | WARNING | Switch to ZGC or Shenandoah |
| Max pause > 5s | CRITICAL | Likely Full GC — investigate cause, may need larger heap or different collector |
| Max pause > 1s | WARNING | Check for Full GCs or oversized young gen |
| Average pause increasing over time | WARNING | Memory pressure building — possible leak or under-sized heap |
| Full GC occurring at all | WARNING | Investigate cause (see Full GC Rules below) |
| STW pauses during concurrent phase (G1 Remark > 100ms) | WARNING | Tune `-XX:G1RSetUpdatingPauseTimePercent`, check reference processing |

### Pause Time Targets by Workload

| Workload Type | p50 Target | p99 Target | Max Acceptable |
|---------------|------------|------------|----------------|
| Batch/Offline | < 1s | < 5s | 30s |
| Web Application | < 100ms | < 500ms | 2s |
| API/Microservice | < 50ms | < 200ms | 1s |
| Interactive/Game | < 20ms | < 50ms | 100ms |
| Trading/Real-time | < 1ms | < 10ms | 20ms |

---

## Heap Utilization Rules

| Condition | Severity | Action |
|-----------|----------|--------|
| After-GC occupancy > 70% of max heap consistently | WARNING | Heap too small — increase `-Xmx` or reduce live data set |
| After-GC occupancy > 85% of max heap | CRITICAL | Severe memory pressure — imminent Full GCs or OOM |
| After-GC occupancy trending upward over time | CRITICAL | Likely memory leak — profile with heap dump, check for growing caches/collections |
| After-GC occupancy < 30% of max heap consistently | INFO | Heap oversized — consider reducing `-Xmx` to save resources, especially in containers |
| Before-GC occupancy at 100% (heap fully consumed) | CRITICAL | Allocation rate exceeds GC throughput — increase heap or reduce allocation |
| Old gen > 80% after Full GC | CRITICAL | Live data set approaching heap limit — increase heap or find leak |
| Young gen too small (< 10% of heap) | WARNING | Frequent young GCs, premature promotion — increase `-XX:G1NewSizePercent` or `-XX:NewSize` |
| Young gen too large (> 70% of heap) | INFO | Old gen may not have enough space — reduce if Full GCs occur |

### Heap Sizing Guidelines

| Scenario | Recommendation |
|----------|---------------|
| After-GC occupancy is X | Set `-Xmx` to at least 2.5-3x of X |
| Container with N GB RAM | `-Xmx` = N * 0.75 (leave 25% for native memory, OS) |
| G1 GC | Need at least 30% free heap for region evacuation headroom |
| ZGC | Allow 10-20% extra for colored pointer overhead |

---

## GC Overhead Rules

| Condition | Severity | Action |
|-----------|----------|--------|
| GC overhead < 0.5% | HEALTHY | No action needed |
| GC overhead 0.5% - 2% | INFO | Acceptable for most workloads |
| GC overhead 2% - 5% | INFO | Acceptable but monitor trends |
| GC overhead 5% - 10% | WARNING | Increase heap, tune young gen, or switch collector |
| GC overhead 10% - 25% | CRITICAL | GC thrashing — major tuning needed, likely under-sized heap |
| GC overhead > 25% | CRITICAL | Near OOM territory — JVM spending more time in GC than application work |

GC overhead is calculated as: `total_gc_pause_time / total_wall_clock_time * 100`

The JVM's built-in `GCOverheadLimit` triggers at roughly 98% time in GC over 5 consecutive collections.

---

## Allocation Rate Rules

| Condition | Severity | Action |
|-----------|----------|--------|
| Sustained allocation rate > 1 GB/s | WARNING | Profile allocation hotspots, consider object pooling or stack allocation |
| Sustained allocation rate > 2 GB/s | CRITICAL | Excessive allocation — TLAB contention likely, profile immediately |
| Bursty spikes > 3x average allocation rate | WARNING | Investigate periodic batch operations, request bursts |
| Promotion rate > 100 MB/s sustained | WARNING | Objects surviving young gen too often — increase young gen or tenuring threshold |
| Promotion rate > 500 MB/s | CRITICAL | Severe premature promotion — young gen far too small |
| Allocation rate near zero | INFO | Application may be idle — check if log covers active period |

### Allocation Analysis Tips
- High allocation + low promotion = healthy (short-lived objects collected in young gen)
- High allocation + high promotion = bad (objects living too long for young gen to collect)
- Low allocation + high GC overhead = live data set problem (old gen too full)

---

## Full GC Rules

Full GCs are always notable. Root cause determines severity and action.

| Cause | Log Pattern | Severity | Action |
|-------|-------------|----------|--------|
| Metadata GC Threshold | `Pause Full (Metadata GC Threshold)` | WARNING | Increase `-XX:MetaspaceSize` and `-XX:MaxMetaspaceSize` to avoid threshold trigger |
| Allocation Failure | `Pause Full (Allocation Failure)` | CRITICAL | Heap exhausted — increase `-Xmx`, reduce allocation rate, check for leak |
| System.gc() | `Pause Full (System.gc())` | WARNING | Add `-XX:+DisableExplicitGC` or fix calling code. If using RMI, tune `-Dsun.rmi.dgc.client.gcInterval` |
| Ergonomics | `Pause Full (Ergonomics)` | WARNING | JVM adaptive sizing triggered Full GC — often under-sized heap |
| G1 Humongous Allocation | `Pause Full (G1 Humongous Allocation)` | CRITICAL | Increase `-XX:G1HeapRegionSize` so objects < 50% of region, or reduce allocation size |
| G1 Evacuation Failure | `To-space exhausted` / `Evacuation Failure` | CRITICAL | Increase heap, increase `-XX:G1ReservePercent`, reduce IHOP |
| G1 Compaction Pause | `Pause Full (G1 Compaction Pause)` | CRITICAL | Fragmentation or heap exhaustion — increase heap |
| Heap Dump | `Pause Full (Heap Dump Initiated GC)` | INFO | Triggered by jmap/jcmd — not an application issue unless frequent |
| JNI | `Pause Full (GCLocker Initiated GC)` | WARNING | JNI critical region preventing GC — check native code, consider `-XX:GCLockerRetryAllocationCount` |
| Concurrent Mode Failure (CMS legacy) | `concurrent mode failure` | CRITICAL | Old gen filled during concurrent collection — increase heap or switch to G1 |

### Full GC Frequency Thresholds

| Frequency | Severity | Action |
|-----------|----------|--------|
| 0 Full GCs | HEALTHY | Ideal state |
| < 1 per hour | INFO | Monitor but likely acceptable |
| 1-5 per hour | WARNING | Tune based on cause |
| > 5 per hour | CRITICAL | Urgent tuning needed |
| Multiple per minute | CRITICAL | Application is effectively unusable |

---

## G1-Specific Rules

| Condition | Severity | Action |
|-----------|----------|--------|
| Humongous allocations detected | WARNING | Objects > 50% of region size bypass young gen. Increase `-XX:G1HeapRegionSize` (power of 2, max 32M) |
| Humongous allocations > 10% of all allocations | CRITICAL | Major fragmentation risk. Profile allocation to find large objects. Consider `-XX:G1HeapRegionSize=32m` |
| Mixed GCs not occurring after marking | WARNING | IHOP may be too high or `G1HeapWastePercent` too high. Lower IHOP or waste percent |
| Mixed GC count < `G1MixedGCCountTarget` | INFO | Regions were reclaimed quickly — usually fine |
| Evacuation failure / to-space exhaustion | CRITICAL | Increase `-XX:G1ReservePercent` (default 10, try 15-20), increase heap |
| Concurrent marking not completing before old gen fills | CRITICAL | Lower `-XX:InitiatingHeapOccupancyPercent`, increase `-XX:ConcGCThreads` |
| Region size < 4M with heap > 8GB | WARNING | Regions too small — increases management overhead. Set `-XX:G1HeapRegionSize=8m` or higher |
| Region size > 16M with heap < 4GB | WARNING | Regions too large — poor granularity. Let JVM auto-calculate or reduce |
| Marking cycle frequency increasing | WARNING | Old gen filling faster — possibly increasing live data set or allocation rate |
| Remark pause > 100ms | WARNING | Large remembered set or many reference objects. Tune `-XX:G1RSetUpdatingPauseTimePercent` |

### G1 Tuning Decision Tree

1. **Full GCs occurring?**
   - Yes, Evacuation Failure → increase heap, increase `G1ReservePercent`
   - Yes, Humongous → increase `G1HeapRegionSize`
   - Yes, Allocation Failure → increase heap
2. **Pause target not met?**
   - Young GC too long → reduce young gen max (`G1MaxNewSizePercent`)
   - Mixed GC too long → increase `G1MixedGCCountTarget` (spread work)
   - Remark too long → check reference processing
3. **Too many GCs?**
   - Young GCs very frequent → increase young gen min (`G1NewSizePercent`)
   - Mixed GCs very frequent → increase `G1HeapWastePercent`
4. **Throughput too low?**
   - Consider switching to Parallel GC if pauses are acceptable

---

## Container and Cloud Rules

| Condition | Severity | Action |
|-----------|----------|--------|
| `-Xmx` set to container memory limit | CRITICAL | OOM kill inevitable. Use `-XX:MaxRAMPercentage=75.0` or set `-Xmx` to 75% of container memory |
| `-XX:-UseContainerSupport` set | WARNING | JVM won't detect container memory/CPU limits. Remove this flag unless you have a specific reason |
| `UseContainerSupport` not detected (JDK < 10) | WARNING | JVM sees host memory, not container. Must set `-Xmx` explicitly |
| CPU limit < 2 cores | INFO | GC threads may be too many. Set `-XX:ParallelGCThreads=2 -XX:ConcGCThreads=1` |
| `-XX:ActiveProcessorCount` not set with fractional CPU | WARNING | JVM may miscalculate GC threads. Set explicitly: `-XX:ActiveProcessorCount=<n>` |
| Swap enabled in container | WARNING | GC pauses become unpredictable with swap. Disable swap or set memory limits carefully |
| No `-XX:+ExitOnOutOfMemoryError` or `-XX:+CrashOnOutOfMemoryError` | INFO | Container orchestrator can't restart on OOM. Add one of these flags |

### Container Memory Budgeting

```
Container Memory (e.g., 2GB)
├── JVM Heap (-Xmx):           ~75% = 1536M
├── Metaspace:                  ~128-256M
├── Thread stacks (200 threads): ~200M (1M default per thread)
├── Direct buffers / NIO:       ~64-128M
├── JIT code cache:             ~64-128M
├── Native / OS overhead:       ~128M
└── Buffer for safety:          remaining
```

### Recommended Container Flags
```
-XX:+UseContainerSupport
-XX:MaxRAMPercentage=75.0
-XX:InitialRAMPercentage=75.0
-XX:+ExitOnOutOfMemoryError
-XX:ActiveProcessorCount=<actual cores>
```

---

## Metaspace Rules

| Condition | Severity | Action |
|-----------|----------|--------|
| Metaspace GC Threshold triggers Full GC | WARNING | Set `-XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m` (adjust to workload) |
| Metaspace growing continuously | CRITICAL | Classloader leak — profile with `-verbose:class`, check for hot-deploy issues |
| Metaspace > 512M | WARNING | Unusual unless very large app (many frameworks/libs). Profile class loading |
| `MetaspaceSize` not set | INFO | Default is ~21M which triggers early Full GCs on most apps. Set to 128-256M |
| `MaxMetaspaceSize` not set | INFO | Unbounded metaspace can consume excessive native memory. Set a cap |

---

## Safepoint Rules

| Condition | Severity | Action |
|-----------|----------|--------|
| Time-to-safepoint > 200ms | CRITICAL | Counted loops without safepoint polls, large array operations. Add `-XX:+UseCountedLoopSafepoints` (JDK 14+: `-XX:LoopStripMiningIter=1000`) |
| Time-to-safepoint > 50ms | WARNING | Investigate with `-Xlog:safepoint` for slow threads |
| Safepoint frequency > 100/s | WARNING | Excessive safepoints — check for biased locking revocation (disable with `-XX:-UseBiasedLocking` in JDK < 15) |
| Safepoint cleanup > 10ms | INFO | Internal VM operations taking time at safepoint |
