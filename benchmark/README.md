# gc-exorcist Benchmark Fixture

A Spring Boot application that generates GC logs with intentionally problematic configurations for testing the gc-exorcist analysis skills.

## Prerequisites

- Java 17+
- Maven 3.8+

## Quick Start

Run all scenarios (5 minutes each by default):

```bash
./run-scenarios.sh
```

Run a single scenario:

```bash
./run-scenarios.sh undersized-heap
```

Override the duration (in seconds):

```bash
DURATION=60 ./run-scenarios.sh
```

## Scenarios

| Scenario | JVM Flags | What It Tests |
|---|---|---|
| `undersized-heap` | `-Xmx256m -Xms256m -XX:+UseG1GC` | Frequent Young GCs and Allocation Failure Full GCs from a working set that exceeds heap capacity |
| `humongous-allocation` | `-Xmx1g -XX:+UseG1GC -XX:G1HeapRegionSize=4m` | G1 humongous allocation events from byte arrays exceeding 50% of region size |
| `metaspace-exhaustion` | `-Xmx512m -XX:MetaspaceSize=32m -XX:MaxMetaspaceSize=64m -XX:+UseG1GC` | Full GCs triggered by Metadata GC Threshold from dynamically generated classes |
| `memory-leak` | `-Xmx512m -XX:+UseG1GC` | Steadily increasing post-GC heap occupancy from collections that are never cleared |
| `high-allocation-rate` | `-Xmx1g -XX:+UseG1GC` | Very high Young GC frequency from rapid creation and discard of large temporary objects |
| `evacuation-failure` | `-Xmx512m -XX:+UseG1GC -XX:G1ReservePercent=5` | G1 evacuation failure / to-space exhausted from fragmented old gen near capacity |
| `system-gc-abuse` | `-Xmx512m -XX:+UseG1GC` | Unnecessary Full GCs with cause "System.gc()" from explicit System.gc() calls |
| `wrong-gc-for-workload` | `-Xmx1g -XX:+UseParallelGC` | Long STW pauses from Parallel GC on a latency-sensitive workload |

## Output

GC logs are written to `logs/<scenario-name>.log` using unified GC logging with debug-level phase, heap, humongous, and safepoint information.

## Using Generated Logs with gc-exorcist

The generated GC logs are designed to exercise specific gc-exorcist analysis skills:

1. **Parse the log** to extract GC events, pause times, and heap occupancy data
2. **Detect anomalies** such as memory leaks (rising post-GC occupancy), excessive Full GC frequency, or humongous allocations
3. **Generate recommendations** for JVM tuning based on the observed GC behavior
4. **Validate fixes** by re-running a scenario with corrected JVM flags and comparing the logs

Example workflow:

```bash
# Generate a log with a known problem
./run-scenarios.sh memory-leak

# Feed it to gc-exorcist for analysis
# (use the appropriate gc-exorcist skill/command for your setup)
```
