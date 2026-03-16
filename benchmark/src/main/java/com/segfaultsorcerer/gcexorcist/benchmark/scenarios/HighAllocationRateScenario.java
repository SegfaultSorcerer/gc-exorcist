package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Creates and discards large temporary objects as fast as possible,
 * simulating a workload like JSON serialization of large payloads.
 *
 * The tight allocation loop generates extreme pressure on the young generation,
 * forcing very frequent Young GC pauses.
 *
 * Expected GC behavior:
 *   - Very high Young GC frequency (potentially hundreds per minute)
 *   - High allocation rate visible in GC log analysis
 *   - Short individual pause times but high cumulative GC overhead
 *
 * Recommended JVM flags:
 *   -Xmx1g -XX:+UseG1GC
 */
public class HighAllocationRateScenario implements BenchmarkScenario {

    private static final Logger log = LoggerFactory.getLogger(HighAllocationRateScenario.class);

    @Override
    public String description() {
        return "Tight allocation loop creating/discarding large temporary objects for extreme Young GC frequency";
    }

    @Override
    public void run(Duration duration) {
        Instant deadline = Instant.now().plus(duration);
        ThreadLocalRandom rng = ThreadLocalRandom.current();
        long totalAllocated = 0;
        long iteration = 0;
        Instant lastReport = Instant.now();

        while (Instant.now().isBefore(deadline)) {
            // Simulate processing a batch of "requests" with large temporary allocations
            for (int request = 0; request < 100; request++) {
                // Simulate building a large JSON response (64KB - 256KB)
                int responseSize = 64 * 1024 + rng.nextInt(192 * 1024);
                byte[] response = new byte[responseSize];
                response[0] = (byte) request;
                totalAllocated += responseSize;

                // Simulate intermediate processing buffers
                String payload = new String(new byte[rng.nextInt(4096, 16384)]);
                totalAllocated += payload.length();

                // Simulate serialization buffer
                byte[] serialized = new byte[rng.nextInt(8192, 32768)];
                serialized[0] = (byte) (request & 0xFF);
                totalAllocated += serialized.length;
            }

            iteration++;

            // Report every 5 seconds
            Instant now = Instant.now();
            if (java.time.Duration.between(lastReport, now).toSeconds() >= 5) {
                long allocatedMb = totalAllocated / (1024 * 1024);
                log.info("Iteration {}: total allocated ~{}MB", iteration, allocatedMb);
                lastReport = now;
            }

            // Minimal sleep to prevent the thread from being too CPU-hostile,
            // but short enough to maintain high allocation rate
            try {
                Thread.sleep(1);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }

        log.info("Final: {} iterations, ~{}MB total allocated",
                iteration, totalAllocated / (1024 * 1024));
    }
}
