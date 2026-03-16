# GC Algorithm Selection Guide

Decision tree and detailed reasoning for choosing the right JVM garbage collector.

---

## Decision Tree

```
START
  |
  +-- Heap < 256MB?
  |     YES --> Serial GC (-XX:+UseSerialGC)
  |
  +-- Latency critical (< 10ms p99)?
  |     YES --> ZGC or Shenandoah
  |     |
  |     +-- Oracle JDK?
  |     |     YES --> ZGC (-XX:+UseZGC)
  |     |
  |     +-- OpenJDK / Corretto / Red Hat?
  |     |     --> ZGC or Shenandoah (both available)
  |     |
  |     +-- JDK 21+?
  |     |     YES --> ZGC with -XX:+ZGenerational (best option)
  |     |
  |     +-- JDK < 17?
  |           --> G1GC with aggressive pause target (ZGC not production-ready)
  |
  +-- Throughput critical (batch, offline, data pipeline)?
  |     YES --> Parallel GC (-XX:+UseParallelGC)
  |
  +-- General purpose web / API?
  |     YES --> G1GC (-XX:+UseG1GC, default since JDK 9)
  |     |
  |     +-- Heap > 8GB?
  |     |     --> Consider ZGC (G1 pause times grow with heap)
  |     |
  |     +-- Frequent humongous allocations in GC log?
  |           --> Increase -XX:G1HeapRegionSize
  |
  +-- Container with < 1GB RAM?
        --> Serial GC or G1GC (benchmark both)
        --> Serial: lower overhead, single-threaded
        --> G1GC: better pause behavior, more threads
```

---

## Detailed Reasoning by Collector

### Serial GC (-XX:+UseSerialGC)

**Best for:** Tiny heaps (< 256MB), single-CPU containers, client applications.

**Why:** Minimal overhead. No multi-threading coordination. For small heaps, a single-threaded stop-the-world collection completes in under a few milliseconds, making the overhead of parallel/concurrent collectors unnecessary.

**Avoid when:** Heap > 512MB or latency matters. Pause times scale linearly with heap size.

### Parallel GC (-XX:+UseParallelGC)

**Best for:** Throughput-oriented workloads -- batch processing, ETL pipelines, scientific computation, MapReduce-style jobs.

**Why:** Maximizes application throughput by using multiple threads for both young and old generation collection. Accepts longer individual pauses in exchange for less total time spent in GC.

**Avoid when:** Latency SLAs exist. Parallel GC pauses can reach hundreds of milliseconds to seconds on large heaps.

**Key flags:**
- `-XX:ParallelGCThreads=N` -- match to available CPUs
- `-XX:MaxGCPauseMillis=N` -- optional soft target (but throughput is still prioritized)

### G1GC (-XX:+UseG1GC)

**Best for:** General-purpose workloads -- web applications, REST APIs, microservices. Heaps from 2GB to ~16GB.

**Why:** Balances throughput and latency. Region-based design allows incremental collection. The pause time target (-XX:MaxGCPauseMillis) lets you tune the latency/throughput tradeoff. Default since JDK 9 and continuously improved through JDK 17+.

**Avoid when:**
- Sub-10ms p99 pauses required (use ZGC/Shenandoah)
- Pure throughput workload (use Parallel GC)

**Key flags:**
- `-XX:MaxGCPauseMillis=200` -- pause time target
- `-XX:G1HeapRegionSize=Nm` -- increase if humongous allocations appear in logs
- `-XX:InitiatingHeapOccupancyPercent=45` -- when to start concurrent marking

**Common mistake:** Setting MaxGCPauseMillis too low (e.g., 10ms). G1 cannot reliably achieve < 50ms. Setting it too low causes G1 to collect too frequently, reducing throughput without actually meeting the target.

### ZGC (-XX:+UseZGC)

**Best for:** Latency-critical applications with any heap size. Large heaps (8GB to multi-TB). Applications requiring consistent < 10ms pauses.

**Why:** Concurrent collector that performs almost all work while the application runs. Pause times are typically < 1ms and do not increase with heap size. Generational mode (JDK 21+) significantly improves throughput.

**Minimum JDK:** JDK 15 (experimental), JDK 17+ (production-ready).

**Avoid when:**
- JDK < 17 (not production-ready)
- Heap < 2GB (overhead may not be worth it)
- Maximum throughput is the sole goal (Parallel GC is better)

**Key flags:**
- `-XX:+UseZGC`
- `-XX:+ZGenerational` (JDK 21+, default in JDK 23+)
- `-XX:SoftMaxHeapSize=Ng` -- soft cap to encourage more frequent collection

**Common mistake:** Using non-generational ZGC on JDK 21+. Always enable -XX:+ZGenerational on JDK 21-22 for significantly better throughput.

### Shenandoah (-XX:+UseShenandoahGC)

**Best for:** Same use cases as ZGC, on non-Oracle JDK distributions.

**Why:** Similar to ZGC -- concurrent collector with sub-10ms pauses. Available in OpenJDK, Amazon Corretto, Red Hat, Azul, and other distributions.

**Not available on:** Oracle JDK (use ZGC instead).

**Key flags:**
- `-XX:+UseShenandoahGC`
- `-XX:ShenandoahGCHeuristics=adaptive` (default, rarely needs changing)

**Common mistake:** Trying to use Shenandoah on Oracle JDK and getting an unrecognized VM option error.

---

## Workload-to-Collector Mapping

| Workload Type | Recommended | Runner-up | Avoid |
|---------------|-------------|-----------|-------|
| Spring Boot REST API | G1GC | ZGC (if p99 < 10ms needed) | Parallel |
| Spring WebFlux / Reactive | ZGC or Shenandoah | G1GC (MaxGCPauseMillis=50) | Parallel |
| Batch / ETL / Data Pipeline | Parallel GC | G1GC | ZGC (wasted concurrent overhead) |
| Microservice (< 1GB heap) | G1GC | Serial GC | ZGC (overhead too high for small heap) |
| Large heap (> 16GB) | ZGC | G1GC (higher pause risk) | Parallel (unacceptable pauses) |
| Real-time / Trading | ZGC | Shenandoah | Any STW collector |
| CLI / Short-lived tool | Serial GC | (whatever is default) | ZGC/Shenandoah (startup overhead) |
| Container, < 512MB | Serial GC | G1GC | ZGC (too much overhead) |
| Container, 1-4GB | G1GC | ZGC (JDK 17+) | Parallel |
| Container, > 4GB | G1GC or ZGC | Shenandoah | Parallel |

---

## Common Mistakes

### 1. Using the JDK default without verifying
The default collector changed from Parallel (JDK 8) to G1 (JDK 9+). If you upgraded from JDK 8 but your workload is throughput-oriented, you may have silently switched to the wrong collector.

### 2. Mixing GC algorithm flags
Never specify more than one `-XX:+Use*GC` flag. The JVM will either error or silently use only one.

### 3. Copying flags from StackOverflow without context
Flags tuned for a specific workload (e.g., Cassandra, Elasticsearch) are often wrong for your application. Always start from defaults and tune based on your own GC logs.

### 4. Over-tuning G1GC
G1 is designed to be self-tuning. Setting too many parameters (NewSize, MaxNewSize, SurvivorRatio) removes G1's ability to adapt. Start with only MaxGCPauseMillis and add flags only if GC logs show a specific problem.

### 5. Ignoring container CPU limits
In containers, set -XX:ParallelGCThreads and -XX:ConcGCThreads explicitly if the JVM misdetects CPU limits. Too many GC threads on a 2-CPU container cause excessive context switching.

### 6. Not enabling generational ZGC on JDK 21+
Non-generational ZGC has significantly lower throughput. Always add -XX:+ZGenerational on JDK 21-22.

---

## Migration Paths

### Parallel GC -> G1GC
- Remove: -XX:+UseParallelGC, -XX:ParallelGCThreads (unless in container)
- Add: -XX:+UseG1GC, -XX:MaxGCPauseMillis=200
- Expect: Lower pause times, slightly lower throughput

### G1GC -> ZGC
- Remove: All G1-specific flags (G1HeapRegionSize, InitiatingHeapOccupancyPercent, etc.)
- Add: -XX:+UseZGC, -XX:+ZGenerational (JDK 21+)
- Expect: Sub-millisecond pauses, slightly higher CPU and memory overhead
- Increase heap by 10-20% to accommodate ZGC overhead

### CMS -> G1GC (JDK 8 to 11+ migration)
- Remove: -XX:+UseConcMarkSweepGC and all CMS flags (CMSInitiatingOccupancyFraction, etc.)
- Add: -XX:+UseG1GC, -XX:MaxGCPauseMillis=200
- CMS was removed in JDK 14. G1 is the natural successor.
