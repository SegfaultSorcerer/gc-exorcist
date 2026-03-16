package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import java.time.Duration;

/**
 * Interface for benchmark scenarios that provoke specific GC behaviors.
 */
public interface BenchmarkScenario {

    /**
     * Runs the scenario for the given duration.
     */
    void run(Duration duration);

    /**
     * Returns a human-readable description of what GC behavior this scenario provokes.
     */
    String description();
}
