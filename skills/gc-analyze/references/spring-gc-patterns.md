# Spring Boot GC Patterns

GC behavior patterns specific to Spring Boot applications, with diagnosis and fixes.

---

## Startup GC Pattern

### Normal Behavior
Spring Boot applications have a characteristic GC pattern during startup:

1. **High allocation rate** during bean initialization, component scanning, and auto-configuration.
2. **Frequent Young GCs** as the framework creates thousands of temporary objects (reflection metadata, annotation processing, proxy generation).
3. **Metaspace growth** as classes are loaded by Spring's classloader chain.
4. **Allocation rate drops sharply** after `ApplicationReadyEvent` fires (typically 10-60 seconds depending on app size).

### What to Look For
- **Healthy:** High Young GC frequency for 10-60 seconds at start, then drops to steady-state. No Full GCs during startup.
- **Unhealthy:** Full GC during startup (usually `Metadata GC Threshold` — fix by pre-sizing metaspace). Allocation rate never drops after startup (indicates a non-startup problem).

### Recommended Startup Tuning
```bash
# Pre-size metaspace to avoid Full GC during class loading
-XX:MetaspaceSize=256m
-XX:MaxMetaspaceSize=512m

# For large Spring apps with many auto-configurations
-XX:MetaspaceSize=512m
-XX:MaxMetaspaceSize=768m
```

---

## Common Pitfalls

### 1. Hibernate Second-Level Cache Flooding Old Gen

#### Signs in GC Log
- Old gen occupancy steadily grows over time (upward drift in after-GC occupancy).
- Mixed GCs (G1) or Full GCs become more frequent as the application runs.
- After-GC occupancy never returns to a stable baseline.
- High promotion rate despite normal allocation rate.

#### Root Cause
Hibernate's second-level cache (e.g., EhCache, Caffeine, Hazelcast) stores entity data in the Java heap. When configured with large max-size or no eviction, cached entities accumulate in Old Gen. This is especially problematic with:
- `@Cache(usage = CacheConcurrencyStrategy.READ_WRITE)` on entities with many instances.
- Default cache configuration that doesn't cap entry count.
- Entities with large object graphs (lazy collections loaded and cached).

#### Fix
```yaml
# application.yml - cap cache sizes
spring:
  jpa:
    properties:
      hibernate:
        cache:
          use_second_level_cache: true
          region.factory_class: org.hibernate.cache.jcache.JCacheRegionFactory
        javax:
          cache:
            provider: org.ehcache.jsr107.EhcacheCachingProvider

# ehcache.xml - set explicit limits
# <cache alias="com.example.MyEntity">
#   <heap unit="entries">10000</heap>
#   <expiry><ttl unit="minutes">30</ttl></expiry>
# </cache>
```

JVM tuning to accommodate:
```bash
# If cache is necessary and properly sized, increase Old Gen headroom
-Xmx4g                        # Ensure heap accommodates cache + working set
-XX:G1ReservePercent=15        # Extra headroom for G1 evacuation
```

If the cache is growing unbounded, no amount of JVM tuning will help — fix the cache configuration first.

---

### 2. Jackson Serialization Object Churn

#### Signs in GC Log
- Very high Young GC frequency correlating with API request volume.
- High allocation rate (often > 500 MB/s under load) but low promotion rate.
- Young GC pause times stable and short (objects die young).
- GC overhead climbs linearly with request throughput.

#### Root Cause
Jackson's `ObjectMapper` creates numerous intermediate objects during serialization/deserialization:
- `JsonParser` / `JsonGenerator` instances per request.
- `TokenBuffer` objects for complex structures.
- `byte[]` / `char[]` arrays for string handling.
- Reflection metadata cached per thread.

Each REST request serializing/deserializing a moderate-sized JSON payload can allocate 1-10 MB of short-lived objects.

#### Fix
```java
// Reuse ObjectMapper (thread-safe, should be singleton)
@Bean
public ObjectMapper objectMapper() {
    return new ObjectMapper()
        .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
        .configure(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS, false);
}

// For high-throughput: use Jackson Afterburner or Blackbird for less reflection
// implementation 'com.fasterxml.jackson.module:jackson-module-afterburner'
```

JVM tuning for high-churn serialization:
```bash
# Large young gen absorbs allocation spikes without frequent GC
-XX:G1NewSizePercent=30
-XX:G1MaxNewSizePercent=60

# Or with Parallel GC for throughput workloads
-XX:NewRatio=1                 # 50% young gen
```

---

### 3. Spring Boot DevTools Class Reloading (Metaspace Pressure)

#### Signs in GC Log
- Metaspace usage grows after each code change / restart.
- `Pause Full (Metadata GC Threshold)` events recurring.
- Metaspace committed size ratchets upward over time.
- Classes loaded count keeps increasing without dropping.

#### Root Cause
Spring Boot DevTools uses a custom `RestartClassLoader` that creates a new classloader on each restart. Old classloaders and their loaded classes are not immediately garbage collected if:
- There are static references to classes from the old classloader.
- ThreadLocal variables hold references to old classloader's objects.
- Logging frameworks (Logback/Log4j2) retain references to old classes.

Each restart leaks a generation of classes into Metaspace.

#### Fix
```yaml
# application.yml - limit DevTools impact
spring:
  devtools:
    restart:
      # Narrow the scope of watched classes
      additional-paths: src/main/java
      exclude: "static/**,public/**,templates/**"
```

For development only:
```bash
# Increase metaspace for dev environments
-XX:MetaspaceSize=512m
-XX:MaxMetaspaceSize=1g

# Enable class unloading
-XX:+ClassUnloadingWithConcurrentMark    # G1, default on
```

Production should never have DevTools on the classpath. If `spring-boot-devtools` appears in a production deployment, it is a bug.

---

### 4. Actuator /heapdump Endpoint

#### Signs in GC Log
- Sudden `Pause Full (Heap Dump Initiated GC)` events.
- Very long Full GC pause (seconds to minutes depending on heap size).
- Often correlated with monitoring system polling intervals.

#### Root Cause
Spring Boot Actuator's `/actuator/heapdump` endpoint triggers a full heap dump, which forces a Full GC. If monitoring tools or scripts poll this endpoint periodically, it causes regular Full GC pauses.

A heap dump on a 4GB heap can take 10-30 seconds of STW pause.

#### Fix
```yaml
# application.yml - disable or secure the endpoint
management:
  endpoint:
    heapdump:
      enabled: false          # Disable entirely
  endpoints:
    web:
      exposure:
        exclude: heapdump     # Or exclude from web exposure
```

If you need heap dumps, use `jcmd <pid> GC.heap_dump <file>` on-demand instead of leaving the endpoint open.

---

### 5. Spring Batch Large Dataset Processing

#### Signs in GC Log
- Sustained high allocation rate during batch job execution.
- Promotion rate spikes (objects survive young gen because batch step holds references).
- Old gen fills up during job execution, triggers Full GCs.
- After job completes, Old gen drops back to baseline (rules out a leak).
- GC overhead > 10% during batch windows.

#### Root Cause
Spring Batch's `ItemReader` / `ItemProcessor` / `ItemWriter` pattern can cause GC pressure when:
- `JdbcPagingItemReader` with large page sizes loads many objects simultaneously.
- `ItemProcessor` chains create intermediate objects that survive across chunk boundaries.
- `chunk(1000)` size too large — 1000 items and their processed results all live simultaneously.
- `JobRepository` metadata (step execution context) grows with each chunk commit.

#### Fix
```java
@Bean
public Step processStep() {
    return stepBuilderFactory.get("processStep")
        .<Input, Output>chunk(100)     // Reduce chunk size from 1000 to 100
        .reader(reader())
        .processor(processor())
        .writer(writer())
        .build();
}

// Use streaming/cursor-based readers instead of paging
@Bean
public JdbcCursorItemReader<Input> reader() {
    return new JdbcCursorItemReaderBuilder<Input>()
        .dataSource(dataSource)
        .sql("SELECT * FROM large_table")
        .rowMapper(new InputRowMapper())
        .fetchSize(100)                // Database cursor fetch size
        .build();
}
```

JVM tuning for batch processing:
```bash
# Batch workloads tolerate longer pauses — optimize for throughput
-XX:+UseParallelGC                     # If pause times don't matter
-Xmx8g                                # Size heap for peak batch working set
-XX:NewRatio=2                         # Default, balanced

# Or with G1 for mixed workloads (batch + API on same JVM)
-XX:+UseG1GC
-XX:MaxGCPauseMillis=500               # Relaxed pause target for batch
-XX:G1NewSizePercent=20
-XX:G1MaxNewSizePercent=40
```

---

### 6. WebFlux Backpressure Failure

#### Signs in GC Log
- Sudden, extreme allocation rate spike (multiple GB/s).
- Rapid young gen exhaustion and promotion storm.
- Full GCs in quick succession, possibly leading to OOM.
- Pattern correlates with upstream traffic bursts.
- Old gen grows rapidly because objects in flight cannot be collected.

#### Root Cause
Spring WebFlux (Project Reactor) relies on backpressure to control data flow. When backpressure signals are not properly propagated:
- `Flux.flatMap()` without `concurrency` limit spawns unbounded concurrent processing.
- `onBackpressureBuffer()` with unbounded or very large buffer accumulates items in memory.
- Blocking calls inside reactive pipelines (e.g., JDBC in a Reactor chain) stall consumption, causing upstream buffers to grow.
- SSE (Server-Sent Events) or WebSocket endpoints without client-side backpressure accumulate outbound messages.

#### Fix
```java
// Always limit concurrency in flatMap
flux.flatMap(item -> processAsync(item), 16)    // max 16 concurrent

// Use bounded backpressure buffers
flux.onBackpressureBuffer(1000, BufferOverflowStrategy.DROP_LATEST)

// For blocking operations, offload to bounded scheduler
flux.publishOn(Schedulers.boundedElastic())
    .map(item -> blockingDbCall(item))           // Now on bounded thread pool

// Limit SSE/WebSocket outbound
@GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<Event> stream() {
    return eventFlux
        .onBackpressureLatest()                  // Drop if client can't keep up
        .limitRate(100);                          // Prefetch limit
}
```

JVM tuning won't fix a backpressure problem — the application code must be corrected. However, for resilience:
```bash
-XX:+ExitOnOutOfMemoryError             # Fast restart instead of lingering in broken state
-Xmx2g                                 # Cap heap so OOM triggers faster, preventing swap thrashing
```

---

## Container-Specific Spring Boot GC Recommendations

### Dockerfile Example

```dockerfile
FROM eclipse-temurin:21-jre-alpine

# Copy the Spring Boot fat JAR
COPY target/myapp.jar /app/myapp.jar

# Set JVM flags via JAVA_TOOL_OPTIONS (respected by all JDK tools)
ENV JAVA_TOOL_OPTIONS="\
  -XX:+UseG1GC \
  -XX:MaxRAMPercentage=75.0 \
  -XX:InitialRAMPercentage=75.0 \
  -XX:+UseContainerSupport \
  -XX:MetaspaceSize=256m \
  -XX:MaxMetaspaceSize=512m \
  -XX:+ExitOnOutOfMemoryError \
  -Xlog:gc*:file=/tmp/gc.log:time,uptime,level,tags:filecount=3,filesize=50m"

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/myapp.jar"]
```

### Kubernetes Resource Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: myapp
          image: myapp:latest
          resources:
            requests:
              memory: "1Gi"       # Guaranteed memory
              cpu: "500m"
            limits:
              memory: "2Gi"       # Max memory (OOM killed above this)
              cpu: "2"
          env:
            - name: JAVA_TOOL_OPTIONS
              value: >-
                -XX:+UseG1GC
                -XX:MaxRAMPercentage=75.0
                -XX:InitialRAMPercentage=75.0
                -XX:ActiveProcessorCount=2
                -XX:MetaspaceSize=256m
                -XX:MaxMetaspaceSize=512m
                -XX:+ExitOnOutOfMemoryError
                -Xlog:gc*:file=/tmp/gc.log:time,uptime,level,tags:filecount=3,filesize=50m
```

### Container Memory Sizing for Spring Boot

| App Size | Container Memory | -Xmx (75%) | Notes |
|----------|-----------------|-------------|-------|
| Minimal microservice | 512M | 384M | Tight — monitor closely |
| Typical REST API | 1G | 768M | Good starting point |
| API + Hibernate + caching | 2G | 1536M | Standard enterprise app |
| Large monolith | 4G | 3G | Consider splitting |
| Batch processing | 4-8G | 3-6G | Size for peak working set |

### Common Container Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| `-Xmx` equals container limit | OOM killed by kernel (native memory not accounted for) | Use `-XX:MaxRAMPercentage=75.0` |
| No `-XX:ActiveProcessorCount` with fractional CPU | JVM sees host CPUs, creates too many GC threads | Set `-XX:ActiveProcessorCount=<n>` |
| Using JDK 8 without `-Xmx` in container | JVM sees host memory (128GB), allocates accordingly | Always set `-Xmx` on JDK 8, or upgrade |
| `-XX:+UseSerialGC` in container with 2+ cores | Wasting available CPU for GC | Use G1 or Parallel GC |
| No GC logging in container | Can't diagnose issues post-mortem | Always enable GC logging to a file |
| Liveness probe too aggressive | GC pause triggers restart loop | Set probe timeout > max expected GC pause |
