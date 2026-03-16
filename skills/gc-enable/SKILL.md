---
name: gc-enable
description: Generate the correct GC logging JVM flags for your JDK version
usage: /gc-enable [--jdk-version <version>] [--detail-level basic|detailed|trace]
arguments:
  - name: jdk-version
    description: "JDK version (8, 11, 17, 21). Auto-detected if not specified."
    required: false
  - name: detail-level
    description: "Logging detail: basic (low overhead), detailed (standard), trace (debug)"
    required: false
---

# GC Logging Configuration -- gc-exorcist

You are generating the correct GC logging JVM flags for the user's JDK version.

## Instructions

1. **Detect JDK version** (in order of preference):
   - From `$ARGUMENTS` if --jdk-version specified
   - From `java -version` output
   - From pom.xml `<java.version>` or `<maven.compiler.source>`
   - From build.gradle `sourceCompatibility`
   - Ask user if cannot detect

2. **Detect detail level**:
   - From `$ARGUMENTS` if --detail-level specified
   - Default to "detailed"

3. **Generate flags** based on JDK version:

   **JDK 8 (legacy flags):**
   ```
   -XX:+PrintGCDetails
   -XX:+PrintGCDateStamps
   -XX:+PrintTenuringDistribution
   -XX:+PrintGCApplicationStoppedTime
   -Xloggc:gc.log
   -XX:+UseGCLogFileRotation
   -XX:NumberOfGCLogFiles=5
   -XX:GCLogFileSize=20M
   ```

   **JDK 11+ basic:**
   ```
   -Xlog:gc*:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
   ```

   **JDK 11+ detailed:**
   ```
   -Xlog:gc*,gc+ref=debug,gc+phases=debug,gc+age=debug,safepoint:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20M
   ```

   **JDK 11+ trace:**
   ```
   -Xlog:gc*=debug,gc+ergo*=trace,gc+age*=trace,gc+alloc*=trace,safepoint*:file=gc.log:time,uptime,level,tags:filecount=10,filesize=50M
   ```

   **JDK 17+ (add async logging):**
   ```
   -Xlog:async
   ```

4. **Generate integration snippets** (all that are relevant):
   - `JAVA_OPTS` for shell scripts
   - Dockerfile `ENTRYPOINT` / `CMD`
   - `spring-boot-maven-plugin` `<jvmArguments>`
   - Gradle bootRun args
   - application.yml (Spring Boot 3.2+ if applicable)

5. **Explain** overhead expectations for each detail level

## Output Format

```markdown
## GC Logging Configuration

### Detected Environment
| Property      | Value     |
|---------------|-----------|
| JDK Version   |           |
| Detail Level  |           |

### GC Logging Flags
```
(the flags)
```

### Integration Snippets

#### Shell / JAVA_OPTS
```bash
export JAVA_OPTS="..."
```

#### Dockerfile
```dockerfile
ENTRYPOINT ["java", ..., "-jar", "app.jar"]
```

#### Maven (spring-boot-maven-plugin)
```xml
<configuration>
  <jvmArguments>...</jvmArguments>
</configuration>
```

### Overhead Expectations
(brief note on expected overhead for the chosen detail level)

### Legacy Flag Mapping
(if JDK 8, show the equivalent unified flags for future migration)
(if JDK 9+, show which legacy flags these replace)
```
