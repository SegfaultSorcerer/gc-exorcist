package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Creates conditions for G1 evacuation failure (to-space exhausted).
 *
 * This is achieved by:
 *   1. Filling old gen with objects of varying sizes to create fragmentation
 *   2. Keeping the heap near capacity with a low G1ReservePercent
 *   3. Continuously allocating objects that need to be evacuated but have no
 *      space to move to
 *
 * The mix of long-lived objects of different sizes in old gen creates
 * fragmentation, making it harder for G1 to find contiguous free regions
 * for evacuation targets.
 *
 * Expected GC behavior:
 *   - Evacuation Failure / To-space exhausted events
 *   - Full GCs triggered by evacuation failure
 *   - Possible "to-space overflow" in GC logs
 *
 * Recommended JVM flags:
 *   -Xmx512m -XX:+UseG1GC -XX:G1ReservePercent=5
 */
public class EvacuationFailureScenario implements BenchmarkScenario {

    private static final Logger log = LoggerFactory.getLogger(EvacuationFailureScenario.class);

    @Override
    public String description() {
        return "Creates heap fragmentation and near-capacity conditions to trigger G1 evacuation failures";
    }

    @Override
    public void run(Duration duration) {
        Instant deadline = Instant.now().plus(duration);
        ThreadLocalRandom rng = ThreadLocalRandom.current();

        // Long-lived objects of varying sizes to create fragmentation in old gen
        List<byte[]> longLived = new ArrayList<>(5000);

        // Phase 1: Fill heap with fragmented old-gen objects
        log.info("Phase 1: Building fragmented old-gen occupancy");
        try {
            for (int i = 0; i < 5000 && Instant.now().isBefore(deadline); i++) {
                // Vary sizes significantly to create fragmentation
                int size;
                int pick = rng.nextInt(100);
                if (pick < 40) {
                    size = rng.nextInt(512, 2048);         // small objects
                } else if (pick < 70) {
                    size = rng.nextInt(8192, 32768);       // medium objects
                } else if (pick < 90) {
                    size = rng.nextInt(32768, 131072);     // large objects
                } else {
                    size = rng.nextInt(131072, 524288);    // very large objects
                }

                byte[] obj = new byte[size];
                obj[0] = (byte) i;
                longLived.add(obj);

                if (i % 1000 == 0) {
                    log.info("  Allocated {} long-lived objects", i);
                }
            }
        } catch (OutOfMemoryError e) {
            log.info("  Heap filled during phase 1 (expected)");
        }

        // Phase 2: Create holes by removing some objects (fragmentation)
        log.info("Phase 2: Creating holes for fragmentation");
        int removed = 0;
        for (int i = longLived.size() - 1; i >= 0; i -= 3) {
            longLived.set(i, null);
            removed++;
        }
        log.info("  Removed {} objects to create holes", removed);

        // Phase 3: Continuous allocation to trigger evacuation failures
        log.info("Phase 3: Continuous allocation to trigger evacuation failures");
        List<byte[]> shortLived = new LinkedList<>();
        int iteration = 0;

        while (Instant.now().isBefore(deadline)) {
            try {
                // Allocate objects that will end up in young gen and need evacuation
                for (int i = 0; i < 50; i++) {
                    int size = rng.nextInt(4096, 65536);
                    byte[] obj = new byte[size];
                    obj[0] = (byte) iteration;
                    shortLived.add(obj);
                }

                // Occasionally keep some references to force promotion attempts
                if (iteration % 5 == 0 && !shortLived.isEmpty()) {
                    // Move some short-lived to long-lived to force promotion
                    int moveCount = Math.min(10, shortLived.size());
                    for (int i = 0; i < moveCount; i++) {
                        byte[] obj = shortLived.removeFirst();
                        // Fill a null slot in longLived
                        for (int j = 0; j < longLived.size(); j++) {
                            if (longLived.get(j) == null) {
                                longLived.set(j, obj);
                                break;
                            }
                        }
                    }
                }

                // Discard older short-lived objects to keep churn going
                if (shortLived.size() > 200) {
                    shortLived.subList(0, 100).clear();
                }

                iteration++;
                if (iteration % 100 == 0) {
                    log.info("Churn iteration {}, short-lived={}, long-lived={}",
                            iteration, shortLived.size(), longLived.size());
                }

                Thread.sleep(10);

            } catch (OutOfMemoryError e) {
                // Clear some objects and continue
                shortLived.clear();
                for (int i = 0; i < longLived.size(); i += 4) {
                    longLived.set(i, null);
                }
                log.info("OOM at iteration {} -- cleared some objects and continuing", iteration);
                try {
                    Thread.sleep(500);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    return;
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
    }
}
