package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;

/**
 * Explicitly calls System.gc() at regular intervals while maintaining
 * a modest workload.
 *
 * This simulates code that inappropriately calls System.gc() -- a common
 * anti-pattern found in production applications, often in cleanup routines,
 * RMI internals, or misguided "optimization" attempts.
 *
 * Expected GC behavior:
 *   - Full GCs with cause "System.gc()"
 *   - Unnecessary stop-the-world pauses
 *   - Full GCs even when the heap is not under pressure
 *
 * Recommended JVM flags:
 *   -Xmx512m -XX:+UseG1GC
 *   (Note: do NOT use -XX:+DisableExplicitGC, we want to see the bad behavior)
 */
public class SystemGcAbuseScenario implements BenchmarkScenario {

    private static final Logger log = LoggerFactory.getLogger(SystemGcAbuseScenario.class);

    // Call System.gc() every 3 seconds
    private static final long GC_INTERVAL_MS = 3_000;

    @Override
    public String description() {
        return "Calls System.gc() every 3 seconds to generate unnecessary Full GCs with cause 'System.gc()'";
    }

    @Override
    @SuppressWarnings("all")
    public void run(Duration duration) {
        Instant deadline = Instant.now().plus(duration);
        long lastGcCall = 0;
        int gcCallCount = 0;
        long iteration = 0;

        while (Instant.now().isBefore(deadline)) {
            // Do some modest work to keep the application "busy"
            for (int i = 0; i < 20; i++) {
                byte[] work = new byte[4096];
                work[0] = (byte) i;
                // Simulate some processing
                String s = new String(work);
                s.hashCode();
            }

            // Call System.gc() at regular intervals
            long now = System.currentTimeMillis();
            if (now - lastGcCall >= GC_INTERVAL_MS) {
                log.info("Calling System.gc() (call #{})", gcCallCount + 1);
                System.gc();
                gcCallCount++;
                lastGcCall = now;
            }

            iteration++;
            if (iteration % 500 == 0) {
                log.info("Iteration {}, System.gc() called {} times", iteration, gcCallCount);
            }

            try {
                Thread.sleep(50);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }

        log.info("Total System.gc() calls: {}", gcCallCount);
    }
}
