# GC Algorithm Reference

## Algorithm Comparison

| Algorithm | Flag | Best For | Pause Goal | Throughput | Heap Range | JDK |
|-----------|------|----------|------------|------------|------------|-----|
| Serial | `-XX:+UseSerialGC` | Single-core, small heaps, client apps | N/A | Low | < 256M | All |
| Parallel (Throughput) | `-XX:+UseParallelGC` | Batch processing, throughput-oriented | Seconds ok | Highest | < 4GB | All |
| G1 | `-XX:+UseG1GC` | General purpose, balanced latency/throughput | 200ms default | Good | 2-32GB | 9+ default |
| ZGC | `-XX:+UseZGC` | Ultra-low latency, large heaps | < 10ms | Good | 8GB-16TB | 15+ (prod 17+) |
| Shenandoah | `-XX:+UseShenandoahGC` | Low latency, medium heaps | < 10ms | Good | 2-32GB | 12+ (not in Oracle JDK) |
| Epsilon | `-XX:+UseEpsilonGC` | Testing, short-lived processes | None (no GC) | Maximum | Any | 11+ |

---

## Serial GC

### How It Works
- Single-threaded, stop-the-world collector for both Young and Old generations.
- Young Gen: copying collector (Eden + 2 Survivor spaces).
- Old Gen: mark-sweep-compact.
- All application threads are stopped during the entire GC cycle.

### Key Tuning Flags
```
-XX:+UseSerialGC
-Xms<size> -Xmx<size>          # Heap sizing
-XX:NewRatio=<n>                # Old/Young ratio (default 2)
-XX:SurvivorRatio=<n>           # Eden/Survivor ratio (default 8)
-XX:MaxTenuringThreshold=<n>    # Promotion age (default 15)
```

### Common Pitfalls
- Used accidentally on multi-core servers (JDK may select it for small heaps or single-CPU containers).
- Pause times scale linearly with heap size — unusable above ~256M for latency-sensitive workloads.
- No parallelism means wasted CPU capacity on modern hardware.

### When to Switch Away
- Heap > 256M.
- Application runs on multi-core hardware.
- Pause times are noticeable to users.

---

## Parallel (Throughput) GC

### How It Works
- Multi-threaded stop-the-world collector for both generations.
- Young Gen: parallel copying collector across multiple GC threads.
- Old Gen: parallel mark-sweep-compact.
- Designed to maximize throughput (minimize total time in GC).
- Default GC in JDK 8.

### Phases
1. **Young GC (Parallel Scavenge):** STW, parallel copy from Eden+Survivor to Survivor/Old.
2. **Full GC (Parallel Old):** STW, parallel mark-compact of entire heap.

### Key Tuning Flags
```
-XX:+UseParallelGC
-XX:ParallelGCThreads=<n>             # GC thread count (default: CPU count for <= 8, else 5/8 * CPU + 3)
-XX:MaxGCPauseMillis=<ms>             # Soft pause time target
-XX:GCTimeRatio=<n>                   # Throughput target: 1/(1+n) GC time (default 99 = 1%)
-XX:+UseAdaptiveSizePolicy            # Auto-tune generation sizes (default on)
-XX:YoungGenerationSizeIncrement=<n>  # % to grow young gen (default 20)
-XX:AdaptiveSizePolicyWeight=<n>      # Weight of current vs historical data (default 10)
```

### Common Pitfalls
- Full GCs can be very long (seconds to tens of seconds on large heaps).
- `-XX:MaxGCPauseMillis` is a soft target — collector may not achieve it.
- Adaptive size policy can shrink young gen too aggressively under memory pressure.
- No concurrent work — all GC is stop-the-world.

### When to Switch Away
- Pause times unacceptable for interactive/API workloads.
- Heap > 4GB (Full GC pauses become very long).
- Application needs sub-second pause guarantees.

---

## G1 (Garbage-First) GC

### How It Works
- Region-based, generational, partially concurrent collector.
- Heap divided into equal-sized regions (1-32M each, auto-calculated).
- Regions are dynamically assigned as Eden, Survivor, Old, or Humongous.
- Prioritizes collecting regions with the most garbage first (hence the name).
- Default GC in JDK 9+.

### Phases
1. **Young GC (STW):** Evacuate live objects from Eden and Survivor regions to new Survivor/Old regions.
2. **Concurrent Marking Cycle:**
   - Initial Mark (STW, piggybacked on Young GC)
   - Root Region Scanning (concurrent)
   - Concurrent Mark (concurrent)
   - Remark (STW)
   - Cleanup (STW + concurrent)
3. **Mixed GC (STW):** Evacuate live objects from both Young and selected Old regions. Triggered after concurrent marking identifies high-garbage old regions.
4. **Full GC (STW, single-threaded in JDK 9, parallel in JDK 10+):** Last resort, compacts entire heap.

### Key Tuning Flags
```
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200               # Pause time target (default 200ms)
-XX:G1HeapRegionSize=<n>m              # Region size (1-32M, power of 2)
-XX:G1NewSizePercent=5                 # Min young gen % (default 5)
-XX:G1MaxNewSizePercent=60             # Max young gen % (default 60)
-XX:InitiatingHeapOccupancyPercent=45  # IHOP: start marking when old gen reaches this % (default 45)
-XX:G1MixedGCLiveThresholdPercent=85   # Skip regions with > this % live data
-XX:G1MixedGCCountTarget=8            # Target mixed GC count after marking
-XX:G1ReservePercent=10                # Reserve heap % for evacuation (default 10)
-XX:G1HeapWastePercent=5               # Stop mixed GC when reclaimable < this %
-XX:+G1UseAdaptiveIHOP                 # Auto-tune IHOP (default on, JDK 9+)
-XX:ParallelGCThreads=<n>             # STW GC threads
-XX:ConcGCThreads=<n>                 # Concurrent marking threads (default ParallelGCThreads/4)
```

### Common Pitfalls
- **Humongous allocations:** Objects > 50% of region size are allocated as humongous, skip young gen, can cause fragmentation and early Full GCs. Fix: increase region size or reduce allocation size.
- **Evacuation failure / to-space exhaustion:** Not enough free regions to copy live objects. Triggers a Full GC. Fix: increase heap, increase `-XX:G1ReservePercent`, reduce allocation rate.
- **Concurrent marking not finishing in time:** Old gen fills before marking completes. Fix: lower IHOP, increase concurrent threads, increase heap.
- **Too-tight pause target:** Setting `MaxGCPauseMillis` too low causes tiny young generations, frequent GCs, higher overhead. Rarely set below 50ms.
- **Under-sized heap:** G1 needs headroom (~30% free) to work efficiently. Heaps at 90%+ occupancy cause frequent Full GCs.

### When to Switch Away
- Need sub-10ms pauses consistently: use ZGC or Shenandoah.
- Very small heaps (< 1GB): Parallel GC may give better throughput.
- Pure batch throughput with no pause requirements: Parallel GC.

---

## ZGC

### How It Works
- Concurrent, region-based collector designed for ultra-low latency.
- Almost all work done concurrently with application threads.
- Uses colored pointers (pointer metadata bits) and load barriers.
- Generational ZGC (default in JDK 21+) adds young/old separation for better efficiency.
- STW pauses are O(1) — independent of heap size, live object count, or root set size.

### Phases
1. **Pause Mark Start (STW, ~microseconds):** Mark roots.
2. **Concurrent Mark/Remap:** Trace all live objects concurrently.
3. **Pause Mark End (STW, ~microseconds):** Synchronize marking.
4. **Concurrent Prepare for Relocate:** Select relocation set.
5. **Pause Relocate Start (STW, ~microseconds):** Relocate root references.
6. **Concurrent Relocate:** Move objects and update references concurrently.

### Key Tuning Flags
```
-XX:+UseZGC
-XX:+ZGenerational                     # Generational mode (default in JDK 21+)
-XX:SoftMaxHeapSize=<size>             # Soft limit, GC tries to stay under
-XX:ZAllocationSpikeTolerance=<n>      # Allocation spike tolerance (default 2.0)
-XX:ZCollectionInterval=<seconds>      # Force GC interval (0 = disabled)
-XX:ZFragmentationLimit=<percent>      # Max fragmentation before compaction (default 25)
-XX:ConcGCThreads=<n>                  # Concurrent GC threads
```

### Common Pitfalls
- Higher memory overhead (~3-5% for pointer coloring, more for multi-mapping).
- Throughput typically 5-15% lower than Parallel GC for batch workloads.
- Requires JDK 15+ (production-ready in 17+). Generational mode best in JDK 21+.
- Not available in all JDK distributions.
- Very large heaps (> 1TB) need sufficient concurrent GC threads.

### When to Switch Away
- Pure throughput workloads where pauses don't matter: Parallel GC gives more throughput.
- Constrained memory environments where 3-5% overhead matters.
- JDK < 15.

---

## Shenandoah GC

### How It Works
- Concurrent, region-based collector with low pause times.
- Uses Brooks forwarding pointers (extra word per object) and read/write barriers.
- Performs concurrent compaction — moves objects while application runs.
- All phases are concurrent except brief STW pauses for root scanning.
- Available in OpenJDK and derivatives, NOT in Oracle JDK.

### Phases
1. **Init Mark (STW, ~microseconds):** Scan root set.
2. **Concurrent Mark:** Trace reachable objects.
3. **Final Mark (STW, ~microseconds):** Drain remaining SATB buffers, select collection set.
4. **Concurrent Cleanup:** Reclaim fully empty regions.
5. **Concurrent Evacuation:** Copy live objects from collection set regions concurrently.
6. **Init Update Refs (STW, ~microseconds):** Prepare for reference update.
7. **Concurrent Update References:** Update all heap references to point to new locations.
8. **Final Update Refs (STW, ~microseconds):** Update root references.
9. **Concurrent Cleanup:** Reclaim evacuated regions.

### Key Tuning Flags
```
-XX:+UseShenandoahGC
-XX:ShenandoahGCHeuristics=adaptive    # Heuristic mode (adaptive, compact, static, aggressive)
-XX:ShenandoahMinFreeThreshold=10      # Start GC when free heap drops below %
-XX:ShenandoahInitFreeThreshold=70     # Initial free threshold %
-XX:ShenandoahAllocSpikeFactor=5       # Allocation spike tolerance
-XX:ShenandoahGuaranteedGCInterval=<ms> # Max interval between GCs (default 5 min)
-XX:ConcGCThreads=<n>                  # Concurrent threads
-XX:ParallelGCThreads=<n>              # STW phase threads
```

### Common Pitfalls
- Brooks forwarding pointer adds 8 bytes per object (memory overhead).
- Write barrier overhead slightly higher than ZGC's load barrier on some workloads.
- Not available in Oracle JDK — must use OpenJDK, AdoptOpenJDK/Temurin, Red Hat builds.
- "Degenerated GC" or "Full GC" in logs means Shenandoah couldn't keep up — treat as CRITICAL.

### When to Switch Away
- Using Oracle JDK (not available).
- Need maximum throughput: use Parallel GC.
- Heap > 32GB with pause-time focus: ZGC may be a better fit.
- JDK < 12.

---

## Epsilon GC

### How It Works
- No-op garbage collector. Allocates memory but never reclaims it.
- Application runs until heap is exhausted, then JVM terminates with OutOfMemoryError.
- Zero GC overhead, zero pauses.

### Key Tuning Flags
```
-XX:+UseEpsilonGC
-XX:+UnlockExperimentalVMOptions       # Required in some JDK versions
-Xmx<size>                             # Set heap large enough for workload lifetime
```

### Common Pitfalls
- Application will crash with OOM when heap fills.
- Only suitable for short-lived processes, performance testing, or GC-free workloads.

### When to Switch Away
- Almost always: Epsilon is not for production workloads that run indefinitely.
- Use only for: benchmarks measuring raw allocation speed, ultra-short-lived containers, testing GC impact.
