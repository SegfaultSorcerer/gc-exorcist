package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Allocates and holds a ~512MB working set inside a heap that is only 256MB.
 *
 * The working set is built from ArrayLists of byte arrays. Periodically, portions
 * of the working set are replaced to force promotion and mixed GC cycles.
 *
 * Expected GC behavior:
 *   - Frequent Young GCs due to constant allocation pressure
 *   - Occasional Full GCs triggered by Allocation Failure
 *   - High GC overhead as the collector struggles with insufficient heap
 *
 * Recommended JVM flags:
 *   -Xmx256m -Xms256m -XX:+UseG1GC
 */
public class UndersizedHeapScenario implements BenchmarkScenario {

    private static final Logger log = LoggerFactory.getLogger(UndersizedHeapScenario.class);

    // Each chunk is 64KB
    private static final int CHUNK_SIZE = 64 * 1024;

    // Try to hold ~200MB of live data (will pressure a 256MB heap heavily)
    private static final int TARGET_CHUNKS = 200 * 1024 / 64; // ~3200 chunks

    @Override
    public String description() {
        return "Allocates ~200MB working set in a 256MB heap, causing frequent Young GCs and Allocation Failures";
    }

    @Override
    public void run(Duration duration) {
        Instant deadline = Instant.now().plus(duration);
        List<byte[]> workingSet = new ArrayList<>(TARGET_CHUNKS);

        log.info("Building initial working set of {} chunks ({} bytes each)", TARGET_CHUNKS, CHUNK_SIZE);

        // Build the initial working set
        for (int i = 0; i < TARGET_CHUNKS && Instant.now().isBefore(deadline); i++) {
            workingSet.add(new byte[CHUNK_SIZE]);
            if (i % 500 == 0) {
                log.info("Allocated {} / {} chunks", i, TARGET_CHUNKS);
            }
        }

        log.info("Working set built. Starting churn cycle.");

        int iteration = 0;
        while (Instant.now().isBefore(deadline)) {
            // Replace ~10% of the working set each iteration to generate allocation pressure
            int replaceCount = workingSet.size() / 10;
            for (int i = 0; i < replaceCount && i < workingSet.size(); i++) {
                int index = (iteration * replaceCount + i) % workingSet.size();
                workingSet.set(index, new byte[CHUNK_SIZE]);
            }

            // Also allocate some temporary objects to pressure young gen
            for (int i = 0; i < 100; i++) {
                byte[] temp = new byte[CHUNK_SIZE];
                temp[0] = (byte) i; // prevent dead-code elimination
            }

            iteration++;
            if (iteration % 50 == 0) {
                log.info("Churn iteration {}, working set size: {} chunks", iteration, workingSet.size());
            }

            try {
                Thread.sleep(50);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
    }
}
