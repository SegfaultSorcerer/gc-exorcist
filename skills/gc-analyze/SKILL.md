---
name: gc-analyze
description: Analyze a GC log file and provide tuning recommendations
usage: /gc-analyze <file-path>
arguments:
  - name: file-path
    description: "Path to GC log file (.log, .txt)"
    required: true
---

# GC Analysis — gc-exorcist

You are performing a comprehensive GC log analysis using the gc-exorcist plugin.

## Instructions

1. **Validate** that the file at `$ARGUMENTS` exists. If not, tell the user and stop.

2. **Run the parser** to extract structured metrics:
   ```bash
   "$PLUGIN_DIR/scripts/gc-parser.sh" "$ARGUMENTS"
   ```
   Read the output carefully.

3. **Analyze** the parsed output against the tuning rules in your reference files:

   ### Checklist
   - Is the GC algorithm appropriate for this workload? (See gc-algorithms.md, gc-selection-guide rules)
   - Are pause times acceptable? (< 200ms for latency-sensitive, < 1s for throughput)
   - Is there memory pressure? (frequent Full GCs, high occupancy after GC, upward drift)
   - Are there allocation rate spikes? (bursty patterns)
   - Are there humongous allocation issues? (G1 specific)
   - Is GC overhead acceptable? (< 5% for most, < 1% ideal)
   - Are there evacuation failures or to-space exhaustion?
   - Is metaspace sized correctly?
   - Safepoint analysis (if data available)

4. **Cross-reference with application context**:
   - Check if this is a Spring Boot project (look for pom.xml/build.gradle with spring-boot dependencies)
   - If Spring Boot: check heap size vs typical Spring app needs, check for Hibernate/JPA, batch processing patterns
   - Reference spring-gc-patterns.md for Spring-specific findings

5. **Output** a structured report in this exact format:

```markdown
## GC Analysis Report

### Overview
| Field            | Value                                      |
|------------------|--------------------------------------------|
| GC Algorithm     | <detected>                                 |
| JDK Version      | <if detectable>                            |
| Log Duration     | <duration>                                 |
| Total GC Events  | <count>                                    |
| Full GCs         | <count> (<status emoji + note>)            |
| GC Overhead      | <percentage> (<status emoji + note>)       |

### Pause Time Analysis
| Metric         | Young GC  | Mixed GC  | Full GC   | Assessment          |
|----------------|-----------|-----------|-----------|---------------------|
| Count          |           |           |           |                     |
| P50            |           |           |           |                     |
| P95            |           |           |           | <if concerning>     |
| P99            |           |           |           | <if concerning>     |
| Max            |           |           |           | <if concerning>     |

### Heap Health
| Metric                    | Value       | Assessment              |
|---------------------------|-------------|-------------------------|
| Avg occupancy after GC    |             |                         |
| Max occupancy after GC    |             |                         |
| Occupancy trend           |             |                         |
| Allocation rate (avg)     |             |                         |
| Promotion rate (avg)      |             |                         |
| Humongous allocations     |             | <if applicable>         |

### Full GC Root Causes
(table of all Full GC events with timestamp, cause, duration, severity)

### Findings
| Severity | Category         | Finding                                    | Impact                     |
|----------|------------------|--------------------------------------------|----------------------------|
(sorted by severity: CRITICAL > WARNING > INFO)

### Top 3 Actions
(numbered list with severity, description, explanation, and concrete JVM flag code blocks)

### Recommended Complete JVM Flags
(complete java command with all recommended flags, ready to copy-paste)
```

## Important Notes
- Use 🔴 for CRITICAL, ⚠️ for WARNING, ✅ for healthy/INFO
- Always provide concrete JVM flags, never vague advice
- If data is missing from the parser output (e.g., no heap config), note it as "not available in log"
- If no Full GCs occurred, celebrate that fact but still check other metrics
- Reference the tuning rules for severity thresholds
