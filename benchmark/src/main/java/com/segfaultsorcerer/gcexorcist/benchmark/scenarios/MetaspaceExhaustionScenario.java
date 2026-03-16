package com.segfaultsorcerer.gcexorcist.benchmark.scenarios;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.lang.reflect.Proxy;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Generates classes dynamically to exhaust Metaspace.
 *
 * Uses a custom ClassLoader to define unique classes from raw bytecode.
 * Each generated class is distinct, forcing the JVM to allocate new Metaspace
 * entries. References are retained to prevent class unloading.
 *
 * Additionally creates dynamic proxies with unique interface combinations
 * to further pressure Metaspace.
 *
 * Expected GC behavior:
 *   - Full GCs triggered by "Metadata GC Threshold"
 *   - Metaspace occupancy climbing toward MaxMetaspaceSize
 *   - Possible OutOfMemoryError: Metaspace
 *
 * Recommended JVM flags:
 *   -Xmx512m -XX:MetaspaceSize=32m -XX:MaxMetaspaceSize=64m -XX:+UseG1GC
 */
public class MetaspaceExhaustionScenario implements BenchmarkScenario {

    private static final Logger log = LoggerFactory.getLogger(MetaspaceExhaustionScenario.class);

    @Override
    public String description() {
        return "Generates dynamic classes to exhaust Metaspace (32m initial, 64m max), triggering Metadata GC Threshold Full GCs";
    }

    @Override
    public void run(Duration duration) {
        Instant deadline = Instant.now().plus(duration);
        List<Object> retainedReferences = new ArrayList<>();
        int classCount = 0;

        while (Instant.now().isBefore(deadline)) {
            try {
                // Strategy 1: Create dynamic proxies with unique invocation handlers
                // Each proxy class generated for a unique ClassLoader contributes to Metaspace
                for (int i = 0; i < 50; i++) {
                    ClassLoader loader = new DynamicClassLoader();
                    Class<?> generated = defineClass(loader, "Generated_" + classCount);
                    retainedReferences.add(generated.getDeclaredConstructor().newInstance());
                    classCount++;
                }

                // Strategy 2: Create proxies with fresh class loaders
                for (int i = 0; i < 50; i++) {
                    ClassLoader proxyLoader = new DynamicClassLoader();
                    Object proxy = Proxy.newProxyInstance(
                            proxyLoader,
                            new Class<?>[]{Runnable.class},
                            (p, method, args) -> null
                    );
                    retainedReferences.add(proxy);
                }

                if (classCount % 500 == 0) {
                    log.info("Generated {} classes, retained {} references", classCount, retainedReferences.size());
                }

            } catch (OutOfMemoryError e) {
                log.warn("Metaspace exhausted after {} classes (expected behavior)", classCount);
                // Clear some references and continue to keep generating GC events
                int clearCount = retainedReferences.size() / 4;
                retainedReferences.subList(0, clearCount).clear();
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    return;
                }
            } catch (Exception e) {
                log.debug("Class generation error (continuing): {}", e.getMessage());
            }

            try {
                Thread.sleep(10);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }

        log.info("Total classes generated: {}", classCount);
    }

    /**
     * Defines a simple class with the given name using raw bytecode.
     * The class extends Object and has a no-arg constructor.
     */
    private Class<?> defineClass(ClassLoader parent, String className) {
        DynamicClassLoader loader = (DynamicClassLoader) parent;
        // Generate minimal valid class bytecode
        byte[] bytecode = generateClassBytecode(className);
        return loader.defineClassFromBytes(className, bytecode);
    }

    /**
     * Generates minimal valid Java class bytecode for a class that extends Object.
     * This produces a class file with a default constructor.
     */
    private byte[] generateClassBytecode(String className) {
        // Build a minimal class file:
        // magic, version, constant pool, access flags, this/super class,
        // interfaces, fields, methods (one <init>), attributes

        String internalName = className.replace('.', '/');
        String superName = "java/lang/Object";

        // Constant pool entries:
        // 1: CONSTANT_Methodref -> #3.#5 (Object.<init>)
        // 2: CONSTANT_Class -> #6 (this class)
        // 3: CONSTANT_Class -> #7 (java/lang/Object)
        // 4: CONSTANT_Utf8 "<init>"
        // 5: CONSTANT_NameAndType -> #4:#8
        // 6: CONSTANT_Utf8 <className>
        // 7: CONSTANT_Utf8 "java/lang/Object"
        // 8: CONSTANT_Utf8 "()V"
        // 9: CONSTANT_Utf8 "Code"

        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();

        // Magic number
        writeBytes(out, 0xCA, 0xFE, 0xBA, 0xBE);
        // Version: Java 17 = 61.0
        writeU2(out, 0); // minor
        writeU2(out, 61); // major

        // Constant pool count (9 entries + 1)
        writeU2(out, 10);

        // #1 CONSTANT_Methodref: class=#3, nameAndType=#5
        out.write(10); // tag
        writeU2(out, 3);
        writeU2(out, 5);

        // #2 CONSTANT_Class: name=#6
        out.write(7); // tag
        writeU2(out, 6);

        // #3 CONSTANT_Class: name=#7
        out.write(7); // tag
        writeU2(out, 7);

        // #4 CONSTANT_Utf8: "<init>"
        out.write(1); // tag
        writeUtf8(out, "<init>");

        // #5 CONSTANT_NameAndType: name=#4, descriptor=#8
        out.write(12); // tag
        writeU2(out, 4);
        writeU2(out, 8);

        // #6 CONSTANT_Utf8: className
        out.write(1);
        writeUtf8(out, internalName);

        // #7 CONSTANT_Utf8: "java/lang/Object"
        out.write(1);
        writeUtf8(out, superName);

        // #8 CONSTANT_Utf8: "()V"
        out.write(1);
        writeUtf8(out, "()V");

        // #9 CONSTANT_Utf8: "Code"
        out.write(1);
        writeUtf8(out, "Code");

        // Access flags: ACC_PUBLIC
        writeU2(out, 0x0021);

        // This class: #2
        writeU2(out, 2);

        // Super class: #3
        writeU2(out, 3);

        // Interfaces count
        writeU2(out, 0);

        // Fields count
        writeU2(out, 0);

        // Methods count: 1 (<init>)
        writeU2(out, 1);

        // Method: <init>
        writeU2(out, 0x0001); // ACC_PUBLIC
        writeU2(out, 4);     // name: #4 "<init>"
        writeU2(out, 8);     // descriptor: #8 "()V"
        writeU2(out, 1);     // attributes count: 1 (Code)

        // Code attribute
        writeU2(out, 9);     // attribute name: #9 "Code"
        writeU4(out, 17);    // attribute length
        writeU2(out, 1);     // max stack
        writeU2(out, 1);     // max locals
        writeU4(out, 5);     // code length

        // Bytecode: aload_0, invokespecial Object.<init>, return
        out.write(0x2A);     // aload_0
        out.write(0xB7);     // invokespecial
        writeU2(out, 1);     // -> #1 (Object.<init>)
        out.write(0xB1);     // return

        writeU2(out, 0);     // exception table length
        writeU2(out, 0);     // code attributes count

        // Class attributes count
        writeU2(out, 0);

        return out.toByteArray();
    }

    private void writeBytes(java.io.ByteArrayOutputStream out, int... bytes) {
        for (int b : bytes) {
            out.write(b);
        }
    }

    private void writeU2(java.io.ByteArrayOutputStream out, int value) {
        out.write((value >> 8) & 0xFF);
        out.write(value & 0xFF);
    }

    private void writeU4(java.io.ByteArrayOutputStream out, int value) {
        out.write((value >> 24) & 0xFF);
        out.write((value >> 16) & 0xFF);
        out.write((value >> 8) & 0xFF);
        out.write(value & 0xFF);
    }

    private void writeUtf8(java.io.ByteArrayOutputStream out, String s) {
        byte[] bytes = s.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        writeU2(out, bytes.length);
        out.write(bytes, 0, bytes.length);
    }

    /**
     * A simple ClassLoader that can define classes from raw bytecode.
     * Using a fresh ClassLoader per class ensures each class occupies
     * its own Metaspace entry and cannot be shared.
     */
    private static class DynamicClassLoader extends ClassLoader {
        DynamicClassLoader() {
            super(MetaspaceExhaustionScenario.class.getClassLoader());
        }

        public Class<?> defineClassFromBytes(String name, byte[] bytecode) {
            return defineClass(name, bytecode, 0, bytecode.length);
        }
    }
}
