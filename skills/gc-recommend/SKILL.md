---
name: gc-recommend
description: Analyze project and generate recommended JVM GC flags
usage: /gc-recommend [gc-log-file]
arguments:
  - name: gc-log-file
    description: "Optional GC log for data-driven recommendations. Without it, recommendations are based on project analysis."
    required: false
---

# GC Recommendations -- gc-exorcist

You are generating JVM GC flag recommendations, either from project analysis or data-driven from a GC log.

## Instructions

### If a GC log file is provided ($ARGUMENTS is not empty):

1. **Validate** the file exists
2. **Run the parser**:
   ```bash
   "$PLUGIN_DIR/scripts/gc-parser.sh" "$ARGUMENTS"
   ```
3. **Identify the primary issue** from the parsed data:
   - Latency (high pause times)?
   - Throughput (high GC overhead)?
   - Footprint (heap too large/small)?
   - Full GCs (heap pressure, metaspace, fragmentation)?
4. **Generate targeted flag adjustments** with before/after predictions
5. **Explain each flag** change and expected impact
6. Reference jvm-flag-catalog.md for valid flags and gc-selection-guide.md for algorithm choice

### If no GC log file is provided:

1. **Analyze the project**:
   - Check `pom.xml` or `build.gradle` for dependencies (Spring Boot, batch, reactive, etc.)
   - Check for existing JVM flags in run configs, Dockerfiles, shell scripts, application.yml
   - Detect JDK version from build config (java.version property, sourceCompatibility, etc.)
   - Check for Dockerfile (container deployment)

2. **Recommend GC algorithm** based on workload type:
   - Spring Boot web app -> G1GC with moderate pause target
   - Reactive/WebFlux -> ZGC or Shenandoah for ultra-low latency
   - Batch processing -> Parallel GC for throughput
   - Large heap (> 8GB) -> ZGC or G1GC
   - Container/memory-constrained -> G1GC with container awareness flags

3. **Generate complete flag block** using the jvm-flag-catalog reference

## Output Format

```markdown
## GC Recommendations

### Analysis Summary
(What was detected about the project/workload and current GC configuration)

### Recommended GC Algorithm
| Property | Current | Recommended | Reason |
|----------|---------|-------------|--------|

### Recommended JVM Flags
(Each flag with explanation)

| Flag | Value | Purpose |
|------|-------|---------|

### Complete JVM Flags Block
(Ready to copy-paste)
```bash
java \
  -Xms... -Xmx... \
  -XX:+Use...GC \
  ...
  -jar app.jar
```

### Integration Snippets
(Provide for whichever are relevant: JAVA_OPTS, Dockerfile, Maven plugin, application.yml)

### Explanation
(Brief explanation of why these flags were chosen and what improvement to expect)
```

## Important Notes
- Never recommend deprecated flags for the detected JDK version
- Never generate contradictory flags (e.g., two GC algorithms)
- Always include -XX:+HeapDumpOnOutOfMemoryError for production
- For containers: always use -XX:MaxRAMPercentage instead of absolute -Xmx
- Set -Xms equal to -Xmx for production (avoids resize pauses)
- Include GC logging flags (reference gc-enable skill approach)
