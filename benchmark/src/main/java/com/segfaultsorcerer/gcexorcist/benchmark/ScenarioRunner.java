package com.segfaultsorcerer.gcexorcist.benchmark;

import com.segfaultsorcerer.gcexorcist.benchmark.scenarios.*;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Map;
import java.util.function.Supplier;

/**
 * Accepts a scenario name via --scenario and runs it for the configured duration.
 * If no scenario is specified, the application starts normally without running any scenario.
 */
@Component
public class ScenarioRunner {

    private static final Logger log = LoggerFactory.getLogger(ScenarioRunner.class);

    private static final Duration DEFAULT_DURATION = Duration.ofMinutes(15);

    private static final Map<String, Supplier<BenchmarkScenario>> SCENARIOS = Map.of(
            "undersized-heap", UndersizedHeapScenario::new,
            "humongous-allocation", HumongousAllocationScenario::new,
            "metaspace-exhaustion", MetaspaceExhaustionScenario::new,
            "memory-leak", MemoryLeakScenario::new,
            "high-allocation-rate", HighAllocationRateScenario::new,
            "evacuation-failure", EvacuationFailureScenario::new,
            "system-gc-abuse", SystemGcAbuseScenario::new,
            "wrong-gc-for-workload", WrongGcForWorkloadScenario::new
    );

    @Value("${scenario:#{null}}")
    private String scenarioName;

    @Value("${duration:0}")
    private long durationSeconds;

    @PostConstruct
    public void run() {
        if (scenarioName == null || scenarioName.isBlank()) {
            log.info("No scenario specified. Use --scenario=<name> to run a benchmark scenario.");
            log.info("Available scenarios: {}", String.join(", ", SCENARIOS.keySet()));
            return;
        }

        Supplier<BenchmarkScenario> factory = SCENARIOS.get(scenarioName);
        if (factory == null) {
            log.error("Unknown scenario: '{}'. Available scenarios: {}", scenarioName,
                    String.join(", ", SCENARIOS.keySet()));
            return;
        }

        Duration duration = durationSeconds > 0
                ? Duration.ofSeconds(durationSeconds)
                : DEFAULT_DURATION;

        BenchmarkScenario scenario = factory.get();

        log.info("Starting scenario '{}' for {}", scenarioName, duration);
        log.info("Description: {}", scenario.description());

        Thread scenarioThread = new Thread(() -> {
            try {
                scenario.run(duration);
                log.info("Scenario '{}' completed successfully", scenarioName);
            } catch (OutOfMemoryError e) {
                log.error("Scenario '{}' triggered OutOfMemoryError (this may be expected)", scenarioName);
            } catch (Exception e) {
                log.error("Scenario '{}' failed with exception", scenarioName, e);
            }
        }, "scenario-" + scenarioName);

        scenarioThread.setDaemon(true);
        scenarioThread.start();
    }
}
