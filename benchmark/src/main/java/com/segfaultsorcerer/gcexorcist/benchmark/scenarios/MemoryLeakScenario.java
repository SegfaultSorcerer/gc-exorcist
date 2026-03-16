package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Simulates a classic memory leak by continuously adding objects to collections
 * that are never cleared.
 *
 * Multiple leak patterns are used:
 *   - A growing ArrayList of "session" objects (byte arrays)
 *   - A HashMap with monotonically increasing keys (simulating a cache without eviction)
 *
 * Expected GC behavior:
 *   - After-GC heap occupancy trending steadily upward
 *   - Increasing Full GC frequency as the heap fills
 *   - Eventually OutOfMemoryError: Java heap space
 *
 * Recommended JVM flags:
 *   -Xmx512m -XX:+UseG1GC
 */
public class MemoryLeakScenario implements BenchmarkScenario {

    private static final Logger log = LoggerFactory.getLogger(MemoryLeakScenario.class);

    // Each "session" is 8KB
    private static final int SESSION_SIZE = 8 * 1024;

    // Each "cache entry" value is 4KB
    private static final int CACHE_VALUE_SIZE = 4 * 1024;

    @Override
    public String description() {
        return "Simulates a memory leak with ever-growing collections, causing upward-trending post-GC occupancy";
    }

    @Override
    public void run(Duration duration) {
        Instant deadline = Instant.now().plus(duration);

        // These collections are never cleared -- the leak
        List<byte[]> leakedSessions = new ArrayList<>();
        Map<Long, byte[]> leakedCache = new HashMap<>();

        long iteration = 0;

        while (Instant.now().isBefore(deadline)) {
            try {
                // Leak pattern 1: growing list of "sessions"
                for (int i = 0; i < 10; i++) {
                    byte[] session = new byte[SESSION_SIZE];
                    session[0] = (byte) (iteration & 0xFF);
                    leakedSessions.add(session);
                }

                // Leak pattern 2: cache that never evicts
                for (int i = 0; i < 5; i++) {
                    long key = iteration * 5 + i;
                    byte[] value = new byte[CACHE_VALUE_SIZE];
                    value[0] = (byte) (key & 0xFF);
                    leakedCache.put(key, value);
                }

                // Generate some short-lived garbage too, to trigger Young GCs
                // so we can observe the post-GC trend
                for (int i = 0; i < 50; i++) {
                    byte[] temp = new byte[1024];
                    temp[0] = (byte) i;
                }

                iteration++;
                if (iteration % 200 == 0) {
                    long leakedMb = ((long) leakedSessions.size() * SESSION_SIZE
                            + (long) leakedCache.size() * CACHE_VALUE_SIZE) / (1024 * 1024);
                    log.info("Iteration {}: leaked sessions={}, cache entries={}, estimated leak ~{}MB",
                            iteration, leakedSessions.size(), leakedCache.size(), leakedMb);
                }

                Thread.sleep(20);

            } catch (OutOfMemoryError e) {
                log.warn("OutOfMemoryError at iteration {} (expected behavior)", iteration);
                // Free some space and continue to keep generating GC activity
                int clearCount = leakedSessions.size() / 3;
                if (clearCount > 0) {
                    leakedSessions.subList(0, clearCount).clear();
                }
                int cacheRemoveCount = leakedCache.size() / 3;
                List<Long> keysToRemove = leakedCache.keySet().stream()
                        .limit(cacheRemoveCount)
                        .toList();
                keysToRemove.forEach(leakedCache::remove);

                try {
                    Thread.sleep(2000);
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
