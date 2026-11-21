import java.io.BufferedReader;
import java.io.IOException;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.LockSupport;
import weka.associations.AbstractAssociator;
import weka.associations.Apriori;
import weka.associations.AssociationRule;
import weka.associations.AssociationRules;
import weka.associations.AssociationRulesProducer;
import weka.associations.FPGrowth;
import weka.associations.Item;
import weka.core.Instances;
import weka.core.OptionHandler;
import weka.core.Utils;
import weka.core.Version;

/** Measurement harness only. Mining is performed entirely by the installed WEKA jar. */
public final class WekaBenchmark {
    private static final long HANDSHAKE_TIMEOUT_NS = TimeUnit.SECONDS.toNanos(180);

    public static void main(String[] args) throws Exception {
        if (args.length == 2 && "--probe".equals(args[0])) {
            Map<String, Object> probe = new LinkedHashMap<String, Object>();
            probe.put("weka_version", Version.VERSION);
            probe.put("java_version", System.getProperty("java.version"));
            probe.put("java_runtime_version", System.getProperty("java.runtime.version"));
            probe.put("java_vendor", System.getProperty("java.vendor"));
            probe.put("java_vm_name", System.getProperty("java.vm.name"));
            probe.put("java_home", System.getProperty("java.home"));
            probe.put("os_name", System.getProperty("os.name"));
            probe.put("os_version", System.getProperty("os.version"));
            probe.put("os_arch", System.getProperty("os.arch"));
            probe.put("available_processors", Runtime.getRuntime().availableProcessors());
            probe.put("max_heap_bytes", Runtime.getRuntime().maxMemory());
            List<String> collectors = new ArrayList<String>();
            for (GarbageCollectorMXBean gc : ManagementFactory.getGarbageCollectorMXBeans()) {
                collectors.add(gc.getName());
            }
            probe.put("garbage_collectors", collectors.toString());
            writeJson(Paths.get(args[1]), probe);
            return;
        }
        if (args.length != 8) {
            throw new IllegalArgumentException("Expected: dataset algorithm support phase repeat sample_ms result.json expected_rules");
        }
        Path dataset = Paths.get(args[0]);
        String algorithmName = args[1];
        double support = Double.parseDouble(args[2]);
        String phase = args[3];
        int repeat = Integer.parseInt(args[4]);
        int sampleMs = Integer.parseInt(args[5]);
        Path resultPath = Paths.get(args[6]);
        int expected = Integer.parseInt(args[7]);
        if (!"3.8.7".equals(Version.VERSION)) {
            throw new IllegalStateException("WEKA 3.8.7 required; actual=" + Version.VERSION);
        }
        if (!"runtime".equals(phase) && !"memory".equals(phase)) {
            throw new IllegalArgumentException("Unknown measurement phase: " + phase);
        }
        if (sampleMs < 1) throw new IllegalArgumentException("sample_ms must be >= 1");

        // Initialize WEKA's package infrastructure before measuring the algorithm call.
        // The runner supplies an isolated, empty WEKA_HOME; no user packages are loaded.
        Class.forName("weka.core.WekaPackageManager");
        Class.forName("weka.core.WekaPackageClassLoaderManager");

        // Read the existing ARFF directly. No filter, CSV access, or data transformation.
        Instances data;
        try (BufferedReader reader = Files.newBufferedReader(dataset, StandardCharsets.UTF_8)) {
            data = new Instances(reader);
        }
        validateDataset(data);
        AbstractAssociator algorithm = createAlgorithm(algorithmName, support);
        String options = Utils.joinOptions(((OptionHandler) algorithm).getOptions());

        MemoryMXBean heap = ManagementFactory.getMemoryMXBean();
        List<GarbageCollectorMXBean> collectors = ManagementFactory.getGarbageCollectorMXBeans();
        HeapSampler sampler = "memory".equals(phase) ? new HeapSampler(heap, sampleMs) : null;
        if (sampler != null) sampler.prepare();
        // Same preconditioning in both phases; no warm-up build in this JVM.
        System.gc();
        Thread.sleep(100);
        if (sampler != null) {
            Files.write(sibling(resultPath, ".ready"), new byte[0], StandardOpenOption.CREATE_NEW);
            awaitFile(sibling(resultPath, ".go"));
        }
        long baseline = heap.getHeapMemoryUsage().getUsed();
        long gcCountBefore = gcCount(collectors);
        long gcTimeBefore = gcTime(collectors);
        if (sampler != null) sampler.begin(baseline);

        // Keep these three lines adjacent: no loading, console, I/O or reporting here.
        long start = System.nanoTime();
        algorithm.buildAssociations(data);
        long elapsed = System.nanoTime() - start;

        if (sampler != null) sampler.finish();
        long gcCountAfter = gcCount(collectors);
        long gcTimeAfter = gcTime(collectors);

        // Rule conversion, validation, fingerprints and exports are outside both measurements.
        AssociationRules associationRules = ((AssociationRulesProducer) algorithm).getAssociationRules();
        List<String> rules = canonicalRules(associationRules);
        int count = associationRules.getNumRules();
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("phase", phase);
        result.put("algorithm", algorithmName);
        result.put("min_support", support);
        result.put("repetition", repeat);
        result.put("pid", ManagementFactory.getRuntimeMXBean().getName().split("@")[0]);
        result.put("weka_version", Version.VERSION);
        result.put("instances", data.numInstances());
        result.put("attributes", data.numAttributes());
        result.put("expected_rules", expected);
        result.put("actual_rules", count);
        result.put("status", count == expected ? "OK" : "RULE_COUNT_MISMATCH");
        result.put("rule_set_sha256", sha256(String.join("\n", rules)));
        result.put("runtime_ns", sampler == null ? elapsed : null);
        result.put("runtime_ms", sampler == null ? elapsed / 1e6 : null);
        result.put("instrumented_runtime_ns", sampler == null ? null : elapsed);
        result.put("instrumented_runtime_ms", sampler == null ? null : elapsed / 1e6);
        result.put("heap_baseline_bytes", baseline);
        result.put("heap_peak_sampled_bytes", sampler == null ? null : sampler.peak);
        result.put("heap_peak_minus_baseline_bytes", sampler == null ? null : sampler.peak - baseline);
        result.put("heap_samples", sampler == null ? null : sampler.samples);
        result.put("heap_requested_interval_ms", sampler == null ? null : sampleMs);
        result.put("heap_actual_mean_interval_ms", sampler == null ? null : sampler.meanIntervalMs());
        result.put("heap_actual_max_interval_ms", sampler == null ? null : sampler.maxGap / 1e6);
        result.put("gc_count_during_build", gcCountAfter - gcCountBefore);
        result.put("gc_time_during_build_ms", gcTimeAfter - gcTimeBefore);
        result.put("options", options);
        if (sampler != null && sampler.failure != null) {
            throw new IllegalStateException("Heap sampler failed", sampler.failure);
        }
        if (repeat == 1 && "runtime".equals(phase)) {
            Files.write(sibling(resultPath, ".rules.tsv"), rules, StandardCharsets.UTF_8,
                    StandardOpenOption.CREATE_NEW);
        }
        writeJson(resultPath, result);
        if (sampler != null) {
            // Keep the process alive until PowerShell has read the OS high-water mark.
            Files.write(sibling(resultPath, ".complete"), new byte[0], StandardOpenOption.CREATE_NEW);
            awaitFile(sibling(resultPath, ".release"));
        }
        if (count != expected) {
            throw new IllegalStateException("Explorer rule count mismatch: " + algorithmName
                    + ", support=" + support + ", expected=" + expected + ", actual=" + count);
        }
    }

    private static AbstractAssociator createAlgorithm(String name, double support) throws Exception {
        if ("Apriori".equals(name)) {
            Apriori a = new Apriori();
            a.setOptions(Utils.splitOptions("-N 1000 -T 0 -C 0.05 -D " + (1.0 - support)
                    + " -U 1.0 -M " + support + " -S -1.0 -Z -c -1"));
            a.setTreatZeroAsMissing(true);
            a.setOutputItemSets(false);
            a.setVerbose(false);
            return a;
        }
        if ("FPGrowth".equals(name)) {
            FPGrowth f = new FPGrowth();
            // -N 10 and -D 0.05 match Explorer; -S disables rule-count stopping/support stepping.
            f.setOptions(Utils.splitOptions("-P 2 -I -1 -N 10 -T 0 -C 0.05 -D 0.05 -U 1.0 -M "
                    + support + " -S"));
            f.setPositiveIndex(2);
            f.setFindAllRulesForSupportLevel(true);
            f.setMaxNumberOfItems(-1);
            return f;
        }
        throw new IllegalArgumentException("Unsupported algorithm: " + name);
    }

    private static void validateDataset(Instances data) {
        if (data.numInstances() != 14963 || data.numAttributes() != 167 || data.classIndex() != -1) {
            throw new IllegalStateException("Expected 14963 baskets, 167 attributes and no class; actual="
                    + data.numInstances() + "," + data.numAttributes() + ",class=" + data.classIndex());
        }
        for (int j = 0; j < data.numAttributes(); j++) {
            if (!data.attribute(j).isNominal() || data.attribute(j).numValues() != 2
                    || !"f".equals(data.attribute(j).value(0)) || !"t".equals(data.attribute(j).value(1))) {
                throw new IllegalStateException("Attribute must have ordered values {f,t}: " + data.attribute(j).name());
            }
        }
        for (int i = 0; i < data.numInstances(); i++) {
            if (data.instance(i).weight() != 1.0) throw new IllegalStateException("Non-unit instance weight");
            for (int j = 0; j < data.numAttributes(); j++) {
                if (data.instance(i).isMissing(j)) throw new IllegalStateException("Unexpected missing ARFF value");
            }
        }
    }

    private static List<String> canonicalRules(AssociationRules rules) {
        List<String> result = new ArrayList<String>();
        for (AssociationRule rule : rules.getRules()) {
            result.add(items(rule.getPremise()) + " ==> " + items(rule.getConsequence()) + "\t"
                    + rule.getPremiseSupport() + "\t" + rule.getConsequenceSupport() + "\t"
                    + rule.getTotalSupport() + "\t" + rule.getTotalTransactions());
        }
        Collections.sort(result);
        return result;
    }

    private static String items(Collection<Item> items) {
        List<String> values = new ArrayList<String>();
        for (Item item : items) values.add(item.getAttribute().name() + "=" + item.getItemValueAsString());
        Collections.sort(values);
        return values.toString();
    }

    private static long gcCount(List<GarbageCollectorMXBean> collectors) {
        long result = 0;
        for (GarbageCollectorMXBean gc : collectors) if (gc.getCollectionCount() >= 0) result += gc.getCollectionCount();
        return result;
    }

    private static long gcTime(List<GarbageCollectorMXBean> collectors) {
        long result = 0;
        for (GarbageCollectorMXBean gc : collectors) if (gc.getCollectionTime() >= 0) result += gc.getCollectionTime();
        return result;
    }

    private static Path sibling(Path path, String suffix) {
        return Paths.get(path.toString() + suffix);
    }

    private static void awaitFile(Path path) throws Exception {
        long deadline = System.nanoTime() + HANDSHAKE_TIMEOUT_NS;
        while (!Files.exists(path)) {
            if (System.nanoTime() > deadline) throw new IOException("Handshake timeout: " + path);
            Thread.sleep(1);
        }
    }

    private static String sha256(String value) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
        StringBuilder text = new StringBuilder();
        for (byte b : digest) text.append(String.format(java.util.Locale.ROOT, "%02x", b & 0xff));
        return text.toString();
    }

    private static String quote(String value) {
        return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"")
                .replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t") + "\"";
    }

    private static void writeJson(Path path, Map<String, Object> values) throws IOException {
        StringBuilder text = new StringBuilder("{\n");
        for (Map.Entry<String, Object> entry : values.entrySet()) {
            if (text.length() > 2) text.append(",\n");
            Object value = entry.getValue();
            text.append("  ").append(quote(entry.getKey())).append(": ")
                    .append(value == null ? "null" : value instanceof Number ? value.toString() : quote(value.toString()));
        }
        text.append("\n}\n");
        Files.write(path, text.toString().getBytes(StandardCharsets.UTF_8), StandardOpenOption.CREATE_NEW);
    }

    private static final class HeapSampler implements Runnable {
        private final MemoryMXBean heap;
        private final long intervalNs;
        private final CountDownLatch prepared = new CountDownLatch(1);
        private final CountDownLatch firstSample = new CountDownLatch(1);
        private volatile boolean active;
        private volatile boolean stopped;
        private final Thread thread;
        long peak, samples, lastTime, totalGap, maxGap;
        volatile Throwable failure;

        HeapSampler(MemoryMXBean heap, int intervalMs) {
            this.heap = heap;
            this.intervalNs = TimeUnit.MILLISECONDS.toNanos(intervalMs);
            thread = new Thread(this, "benchmark-heap-sampler");
            thread.setDaemon(true);
        }

        void prepare() throws Exception {
            thread.start();
            if (!prepared.await(10, TimeUnit.SECONDS)) throw new IOException("Heap sampler did not start");
        }

        void begin(long baseline) throws Exception {
            peak = baseline;
            active = true;
            LockSupport.unpark(thread);
            if (!firstSample.await(10, TimeUnit.SECONDS)) throw new IOException("Heap sampler did not sample");
        }

        @Override public void run() {
            try {
                // Initialize the management call before the baseline GC.
                heap.getHeapMemoryUsage();
                prepared.countDown();
                while (!stopped) {
                    if (!active) {
                        LockSupport.parkNanos(TimeUnit.MILLISECONDS.toNanos(1));
                        continue;
                    }
                    sample();
                    firstSample.countDown();
                    LockSupport.parkNanos(intervalNs);
                }
            } catch (Throwable error) {
                failure = error;
                firstSample.countDown();
                prepared.countDown();
            }
        }

        private synchronized void sample() {
            long now = System.nanoTime();
            long used = heap.getHeapMemoryUsage().getUsed();
            peak = Math.max(peak, used);
            if (samples > 0) {
                long gap = now - lastTime;
                totalGap += gap;
                maxGap = Math.max(maxGap, gap);
            }
            lastTime = now;
            samples++;
        }

        void finish() throws InterruptedException {
            stopped = true;
            LockSupport.unpark(thread);
            thread.join();
            // Boundary sample immediately after return; before rule materialization and output.
            sample();
        }

        double meanIntervalMs() { return samples > 1 ? totalGap / (double) (samples - 1) / 1e6 : 0; }
    }
}
