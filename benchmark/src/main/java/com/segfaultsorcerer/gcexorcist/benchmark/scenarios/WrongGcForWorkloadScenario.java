package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.LongSummaryStatistics;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Simulates a latency-sensitive web-like workload but runs with the Parallel GC,
 * which is optimized for throughput, not latency.
 *
 * The workload simulates concurrent request processing with timing measurements.
 * When Parallel GC triggers its stop-the-world collections, the pause times will
 * be significantly longer than what G1 or ZGC would produce.
 *
 * Expected GC behavior:
 *   - Long STW pause times from Parallel GC (tens to hundreds of ms)
 *   - Pauses that would be unacceptable for latency-sensitive applications
 *   - Request latency spikes correlating with GC pauses
 *
 * Recommended JVM flags:
 *   -Xmx1g -XX:+UseParallelGC
 */
public class WrongGcForWorkloadScenario implements BenchmarkScenario {

    private static final Logger log = LoggerFactory.getLogger(WrongGcForWorkloadScenario.class);

    @Override
    public String description() {
        return "Latency-sensitive web workload running with Parallel GC, producing unacceptably long STW pauses";
    }

    @Override
    public void run(Duration duration) {
        Instant deadline = Instant.now().plus(duration);
        ThreadLocalRandom rng = ThreadLocalRandom.current();
        LongSummaryStatistics requestStats = new LongSummaryStatistics();
        List<Long> pauseViolations = new ArrayList<>();

        // Maintain some long-lived data (simulating application caches)
        List<byte[]> applicationCache = new ArrayList<>(1000);
        for (int i = 0; i < 1000; i++) {
            applicationCache.add(new byte[rng.nextInt(16384, 65536)]);
        }

        long requestCount = 0;
        long slaViolations = 0;
        // SLA: requests should complete within 10ms
        long slaThresholdMs = 10;

        Instant lastReport = Instant.now();

        while (Instant.now().isBefore(deadline)) {
            // Simulate a batch of concurrent requests
            for (int req = 0; req < 10; req++) {
                long startNanos = System.nanoTime();

                // Simulate request processing:
                // 1. Read from cache
                byte[] cached = applicationCache.get(rng.nextInt(applicationCache.size()));

                // 2. Deserialize request body (temporary allocation)
                byte[] requestBody = new byte[rng.nextInt(4096, 32768)];
                requestBody[0] = cached[0];

                // 3. Process (create intermediate objects)
                List<String> results = new ArrayList<>();
                for (int i = 0; i < 20; i++) {
                    results.add("result-" + i + "-" + new String(new byte[rng.nextInt(256, 1024)]));
                }

                // 4. Serialize response (temporary allocation)
                byte[] response = new byte[rng.nextInt(8192, 65536)];
                response[0] = (byte) results.size();

                // 5. Periodically update cache (promotes objects to old gen)
                if (requestCount % 50 == 0) {
                    int idx = rng.nextInt(applicationCache.size());
                    applicationCache.set(idx, new byte[rng.nextInt(16384, 65536)]);
                }

                long elapsedNanos = System.nanoTime() - startNanos;
                long elapsedMs = elapsedNanos / 1_000_000;
                requestStats.accept(elapsedMs);

                if (elapsedMs > slaThresholdMs) {
                    slaViolations++;
                    pauseViolations.add(elapsedMs);
                }

                requestCount++;
            }

            // Report every 10 seconds
            Instant now = Instant.now();
            if (java.time.Duration.between(lastReport, now).toSeconds() >= 10) {
                double violationPct = requestCount > 0 ? (double) slaViolations / requestCount * 100 : 0;
                log.info("Requests: {}, SLA violations (>{}ms): {} ({}%), avg latency: {}ms, max: {}ms",
                        requestCount, slaThresholdMs, slaViolations,
                        String.format("%.1f", violationPct),
                        String.format("%.1f", requestStats.getAverage()), requestStats.getMax());

                if (!pauseViolations.isEmpty()) {
                    log.info("  Recent violations (ms): {}",
                            pauseViolations.subList(
                                    Math.max(0, pauseViolations.size() - 10),
                                    pauseViolations.size()));
                }
                lastReport = now;
            }

            try {
                // Simulate request arrival interval
                Thread.sleep(5);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }

        log.info("Final: {} requests, {} SLA violations ({}%), max latency: {}ms",
                requestCount, slaViolations,
                requestCount > 0 ? (slaViolations * 100 / requestCount) : 0,
                requestStats.getMax());
    }
}
