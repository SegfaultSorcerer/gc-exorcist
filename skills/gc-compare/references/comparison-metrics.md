# Metric Comparison Guide

## Primary Metrics (always compare)

- **P99 pause time** — most important for latency-sensitive apps
- **Max pause time** — worst case scenario
- **Full GC count** — zero is ideal for long-running apps
- **GC overhead** — percentage of time spent in GC

## Secondary Metrics (compare for deeper insight)

- **P50 pause time** — typical case
- **Allocation rate** — indicates application behavior changes
- **Promotion rate** — indicates object lifetime changes
- **After-GC heap occupancy** — indicates memory pressure

## Interpretation Rules

- **P99 improved but max worsened** — outlier problem, not a systematic fix
- **Full GC eliminated but Young GC p99 increased** — acceptable tradeoff in most cases
- **GC overhead decreased but allocation rate increased** — app is creating more garbage but GC handles it better
- **After-GC occupancy decreased** — more headroom, less risk of Full GC
- **Promotion rate decreased** — objects are being collected younger, good sign

## Normalization

- If log durations differ by > 20%, normalize all rate metrics to per-second
- If event counts differ significantly, focus on percentiles rather than totals
- Account for warmup: first 5 minutes of a log may not be representative

## Significance Thresholds

- **< 5% change** — not significant (➖)
- **5-20% improvement** — minor improvement (✅)
- **20-50% improvement** — significant improvement (✅✅)
- **> 50% improvement** — major improvement (✅✅✅)
- **5-20% regression** — minor regression (⚠️)
- **> 20% regression** — significant regression (🔴)
