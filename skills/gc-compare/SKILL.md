---
name: gc-compare
description: Compare two GC logs to evaluate the impact of a tuning change
usage: /gc-compare <before-log> <after-log>
arguments:
  - name: before-log
    description: "Path to GC log before tuning change"
    required: true
  - name: after-log
    description: "Path to GC log after tuning change"
    required: true
---

# GC Comparison — gc-exorcist

You are comparing two GC logs to evaluate the impact of a configuration or code change.

## Instructions

1. **Parse arguments**: Extract the two file paths from `$ARGUMENTS` (space-separated).

2. **Validate** both files exist. If either is missing, tell the user and stop.

3. **Run the parser** on both logs:
   ```bash
   "$PLUGIN_DIR/scripts/gc-parser.sh" "<before-log>"
   "$PLUGIN_DIR/scripts/gc-parser.sh" "<after-log>"
   ```

4. **Compare** key metrics side-by-side using the comparison metrics reference:

   - Pause time percentiles (p50, p95, p99, max) for each GC type
   - Full GC frequency and total duration
   - GC overhead percentage
   - Heap utilization patterns (avg/max occupancy after GC)
   - Allocation and promotion rates
   - Humongous allocation counts (if G1)
   - Anomaly count changes

5. **Assess each metric**:
   - Improved: ✅ with percentage/absolute improvement
   - Regressed: 🔴 with percentage/absolute regression
   - Unchanged: ➖ (within ±5% tolerance)

6. **Overall verdict**: Did the tuning change improve things overall?

7. **Output** a structured comparison report:

```markdown
## GC Comparison Report

### Configuration Changes Detected
| Property        | Before          | After           |
|-----------------|-----------------|-----------------|
| GC Algorithm    |                 |                 |
| Heap Size       |                 |                 |
| (other changes) |                 |                 |

### Pause Time Comparison
| Metric              | Before    | After     | Delta     | Assessment |
|---------------------|-----------|-----------|-----------|------------|
| Young GC P50        |           |           |           |            |
| Young GC P95        |           |           |           |            |
| Young GC P99        |           |           |           |            |
| Young GC Max        |           |           |           |            |
| Mixed GC P95        |           |           |           |            |
| Full GC Count       |           |           |           |            |
| Full GC Max         |           |           |           |            |
| Max STW Pause       |           |           |           |            |

### Heap & Throughput Comparison
| Metric                  | Before    | After     | Delta     | Assessment |
|-------------------------|-----------|-----------|-----------|------------|
| GC Overhead             |           |           |           |            |
| Avg After-GC Occupancy  |           |           |           |            |
| Max After-GC Occupancy  |           |           |           |            |
| Allocation Rate         |           |           |           |            |
| Promotion Rate          |           |           |           |            |
| Humongous Allocs        |           |           |           |            |

### Regressions
(List any metrics that got worse — these need attention)

### Overall Verdict
(Summary: net improvement/regression, confidence level, key wins and concerns)

### Next Steps
(Based on remaining issues in the "after" log, suggest the next tuning action)
```

## Important Notes
- Calculate percentage changes: ((after - before) / before) * 100
- For pause times and overhead: lower is better (negative delta = improvement)
- For throughput: higher is better
- If GC algorithm changed between logs, note that comparisons may not be apples-to-apples
- If log durations differ significantly, normalize rates to per-second or per-minute
- Always suggest a concrete next step even if the change was an improvement
