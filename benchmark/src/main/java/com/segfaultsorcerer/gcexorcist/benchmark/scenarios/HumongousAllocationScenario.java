package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Allocates byte arrays of 4-16MB in a loop. With G1HeapRegionSize=4m,
 * any allocation exceeding 2MB (50% of region size) is treated as humongous.
 *
 * Some allocations are held briefly to force them into old gen as humongous objects,
 * while others are discarded immediately.
 *
 * Expected GC behavior:
 *   - Humongous allocation events visible in GC logs
 *   - Possible Full GCs caused by G1 Humongous Allocation
 *   - Fragmentation from humongous regions
 *
 * Recommended JVM flags:
 *   -Xmx1g -XX:+UseG1GC -XX:G1HeapRegionSize=4m
 */
public class HumongousAllocationScenario implements BenchmarkScenario {

    private static final Logger log = LoggerFactory.getLogger(HumongousAllocationScenario.class);

    private static final int MIN_ALLOC_MB = 4;
    private static final int MAX_ALLOC_MB = 16;
    private static final int RETAINED_OBJECTS = 20;

    @Override
    public String description() {
        return "Allocates 4-16MB byte arrays to trigger G1 humongous allocations with 4m region size";
    }

    @Override
    public void run(Duration duration) {
        Instant deadline = Instant.now().plus(duration);
        List<byte[]> retained = new ArrayList<>(RETAINED_OBJECTS);
        ThreadLocalRandom rng = ThreadLocalRandom.current();
        int iteration = 0;

        while (Instant.now().isBefore(deadline)) {
            int sizeMb = rng.nextInt(MIN_ALLOC_MB, MAX_ALLOC_MB + 1);
            byte[] humongous = new byte[sizeMb * 1024 * 1024];
            humongous[0] = (byte) iteration; // prevent elimination

            // Retain some objects to create pressure, cycle them out over time
            if (retained.size() < RETAINED_OBJECTS) {
                retained.add(humongous);
            } else {
                // Replace a random entry to keep old gen occupied
                retained.set(rng.nextInt(RETAINED_OBJECTS), humongous);
            }

            // Also create some throwaway humongous objects
            for (int i = 0; i < 3; i++) {
                byte[] throwaway = new byte[rng.nextInt(MIN_ALLOC_MB, MAX_ALLOC_MB + 1) * 1024 * 1024];
                throwaway[0] = (byte) i;
            }

            iteration++;
            if (iteration % 20 == 0) {
                log.info("Humongous allocation iteration {}, retained {} objects", iteration, retained.size());
            }

            try {
                Thread.sleep(200);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
    }
}
