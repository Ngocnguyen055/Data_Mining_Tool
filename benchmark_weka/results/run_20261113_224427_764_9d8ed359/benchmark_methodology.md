# WEKA Apriori / FP-Growth benchmark methodology

Completed UTC: 2026-11-13T15:49:31.2254511Z. Display timezone: Asia/Saigon (UTC+07:00).

## Data and implementation

- Existing ARFF: C:\Projects\Data_Mining_Tool\groceries_basket.arff
- SHA-256: 69D2CA2626095B970FD4D63FB9888358EE4D1F127B9A558E617CC4ECF218DB18
- 14,963 baskets, 167 nominal product attributes, ordered values {f,t}, no class, no missing values, unit instance weights. Validated without changing the data. No CSV was read, no filter applied, and no synthetic data used.
- Mining uses only weka.associations.Apriori and weka.associations.FPGrowth from the installed WEKA jar. The harness implements measurement and rule comparison, not mining.
- WEKA 3.8.7; jar: C:\Program Files\Weka-3-8-7\weka.jar; SHA-256: 621054B25A950E5C61C04E859D0CA5FAD5BDE55435A1A4633144389D44EC52D5.
- Java: BellSoft, 25.0.2+12-LTS, OpenJDK 64-Bit Server VM. Executable: C:\Program Files\Weka-3-8-7\jre\jre-25.0.2-full\bin\java.exe.
- Compiler: javac 25.0.1; executable: C:\Program Files\Eclipse Adoptium\jdk-25.0.1.8-hotspot\bin\javac.exe. Classes target Java 8 bytecode.
- CPU: 11th Gen Intel(R) Core(TM) i5-11400H @ 2.70GHz; 12 logical processors available to the process.
- Physical RAM: 15.729 GiB; available at start: 1.015 GiB.
- Windows kernel 10.0, amd64; build 26200.9711, display version 25H2. Registry product label: Windows 10 Home Single Language. Windows registry product labels may retain Windows 10 wording on Windows 11.
- PowerShell: 5.1.26100.9711. Machine details were read using Kernel32 and the registry because CIM access can be denied.
- JVM flags: -Xms256m -Xmx2g -XX:+UseG1GC -Dfile.encoding=UTF-8 -Djava.awt.headless=true; Java 9+ also uses --add-opens=java.base/java.lang=ALL-UNNAMED as required by the installed WEKA launcher. Collector names: [G1 Young Generation, G1 Concurrent GC, G1 Old Generation].
- WEKA package infrastructure is initialized before measurement. Each benchmark invocation uses an isolated empty WEKA_HOME inside its result directory, so external packages are not loaded and existing user package directories are not changed.

## Exact algorithm settings

- Supports: 0.01, 0.005, 0.002, 0.001; confidence threshold 0.05; confidence ranking (metric type 0); upper support bound 1.0; no class association rules.
- Apriori: treatZeroAsMissing=true (-Z), numRules=1000, lowerBoundMinSupport=support, delta=1.0-support, significanceLevel=-1, classIndex=-1, outputItemSets=false, verbose=false. The Explorer -I output flag is intentionally disabled as requested; the installed source uses it only for textual itemset output.
- FP-Growth: positiveIndex=2 (the nominal value t), maxNumberOfItems=-1, findAllRulesForSupportLevel=true (-S), lowerBoundMinSupport=support, numRulesToFind=10, delta=0.05. The latter two settings match saved Explorer output; -S disables rule-count stopping and iterative support reduction.
- All effective option strings are retained in each worker JSON and in benchmark_raw.csv.
- Installed Apriori source initializes support with 1.0-delta and uses floating-point comparisons in its support-reduction loop. The saved Explorer runs report two cycles for these settings. The benchmark preserves this behavior and does not alter WEKA to force one pass.

## Runtime

- 5 independent JVMs per algorithm/support, 40 runtime runs. No simultaneous benchmark JVMs. The first build in each JVM is measured; there are no warm-up builds. These are cold algorithm invocations, not steady-state warmed JIT measurements.
- Each JVM reads and validates the ARFF and constructs the associator before measurement. Explicit System.gc() followed by a 100 ms pause is requested before each build in both phases; GC is a request, not a guarantee of an identical live baseline.
- The measured source is exactly: start=System.nanoTime(); algorithm.buildAssociations(data); elapsed=System.nanoTime()-start. Class loading/JIT/GC triggered inside buildAssociations remain part of the measured operation.
- JVM startup, ARFF reading, external process startup, baseline preparation, rule materialization/checking, console printing, and exports are outside this interval. No algorithm model/itemset output is requested during build.
- Runtime runs have no heap-sampling thread and no PowerShell memory polling. GC counter reads occur outside the timing interval.
- For each repetition, the eight configurations are shuffled with Fisher-Yates, seed 20261113. The two phases run sequentially, runtime then memory. Execution order and worker PID are retained.
- Summary: arithmetic mean, median, sample standard deviation (denominator n-1), min and max; no observations discarded. runtime_ms is populated only for uninstrumented runs. Instrumented memory-run time is retained separately and excluded from runtime summaries.

## Java heap measurement

- A separate 40-JVM memory phase uses MemoryMXBean.getHeapMemoryUsage().getUsed(), requested every 1 ms by a dedicated daemon thread. The thread and management APIs are initialized before baseline GC.
- Baseline is heap used after ARFF loading, algorithm setup and requested GC, immediately before enabling the sampler and build. The baseline includes the dataset, the JVM's Java objects and harness objects; it is not algorithm-only memory.
- Peak is the maximum of that baseline, samples during build, and boundary samples immediately before/after the call. Sampling stops before converting/exporting rules. It is a sampled lower-bound estimate of peak total used Java heap, not exact instantaneous peak and not retained/live memory.
- Sampling can miss allocation/GC spikes between samples; scheduler delays and safepoints can enlarge gaps. getUsed includes allocated objects not yet collected and collector/TLAB accounting effects. Do not interpret it as total allocated bytes or algorithm-exclusive memory.
- Each raw row records requested interval, sample count, actual mean gap and actual maximum gap. Across memory runs, the mean of actual mean gaps was 1.387 ms; the largest observed gap was 17.588 ms.
- heap_peak_minus_baseline_bytes is explicitly sampled peak minus baseline. It is an auxiliary increase, not a peak derived from end-minus-start. No after-minus-before value is used as the peak.
- Sampling and synchronization have overhead. Memory-run runtimes are not used to judge algorithm speed.

## Whole-process RAM on Windows

- PowerShell reads Process.WorkingSet64 at a ready/go handshake after dataset loading for the process baseline.
- PowerShell polls Process.PeakWorkingSet64 with a requested 5 ms interval during each memory run. This property is the OS-retained high-water mark, not merely the highest instantaneous WorkingSet64 sample. Actual observation gaps are recorded in the raw CSV.
- The worker remains alive after writing its result until PowerShell captures the OS high-water mark and releases it. This avoids losing the peak when a short process exits.
- This process peak covers JVM startup, ARFF loading, validation, Java heap, native memory, JIT, threads, libraries, rule export and the harness up to the final capture. It is RAM for the entire JVM process lifetime up to that point, not memory exclusive to the algorithm or build interval. Late shutdown activity is outside capture.
- Working set measures resident pages and may include shared pages. It differs from private committed bytes, total allocation, Java heap capacity and heap used. Heap and process peaks are reported separately and must not be added together.
- Baseline WorkingSet64 and PeakWorkingSet64 are both retained. A baseline subtraction cannot isolate algorithm-only RAM.

## Validation and preservation

- Required counts: 10 / 57 / 219 / 450 at supports 0.01 / 0.005 / 0.002 / 0.001. Every measured run matched.
- Additionally, rule premise/consequence items and integer premise/consequence/total supports and transaction counts are canonicalized and hashed. Hashes match between both algorithms, all repetitions and both phases at each support. No rounded textual confidence comparison is used.
- First runtime repetition exports canonical *.rules.tsv for diagnosis. A count mismatch, unequal rule set, timeout or failed JVM stops the run with retained raw diagnostics; counts are never overwritten.
- All original top-level project files have matching SHA-256 before/after; the dataset hash was also checked after the run. Previous result directories are never reused or overwritten.

## Results

| Support | Rules | Apriori mean +/- SD (ms) | FP-Growth mean +/- SD (ms) | Apriori heap peak (MiB) | FP-Growth heap peak (MiB) | Apriori process peak (MiB) | FP-Growth process peak (MiB) |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0.01 | 10 | 981.924 +/- 136.532 | 138.636 +/- 14.033 | 28.30 | 28.28 | 201.41 | 224.78 |
| 0.005 | 57 | 2154.261 +/- 152.353 | 145.974 +/- 21.509 | 31.30 | 29.29 | 200.28 | 230.68 |
| 0.002 | 219 | 6242.022 +/- 570.483 | 160.364 +/- 41.084 | 41.28 | 30.30 | 204.20 | 237.22 |
| 0.001 | 450 | 12852.199 +/- 1062.035 | 172.011 +/- 19.820 | 61.29 | 30.26 | 208.79 | 237.64 |

- Support 0.01: Apriori / FP-Growth mean runtime ratio = 7.083; heap peak ratio = 1.001; process peak ratio = 0.896.
- Support 0.005: Apriori / FP-Growth mean runtime ratio = 14.758; heap peak ratio = 1.068; process peak ratio = 0.868.
- Support 0.002: Apriori / FP-Growth mean runtime ratio = 38.924; heap peak ratio = 1.362; process peak ratio = 0.861.
- Support 0.001: Apriori / FP-Growth mean runtime ratio = 74.717; heap peak ratio = 2.025; process peak ratio = 0.879.

Heap/process columns above are means of five independent run peaks (or the configured repetition count), not the maximum over all repetitions. Median, sample SD, min/max and baseline measurements are in benchmark_summary.csv. All memory units are MiB (1,048,576 bytes); runtime is milliseconds.

## Interpretation limits

- These measurements apply to this ARFF, installed WEKA implementation, JVM settings and machine. They do not establish universal algorithm superiority or compare different implementations.
- Apriori's support-loop behavior and rule generation are included exactly as configured; FP-Growth -S mines one fixed support level. A difference reflects these Explorer-equivalent implementations/settings, not a controlled count of internal passes.
- Five fresh JVMs are a small sample; OS scheduling, background activity, disk-cache effects, JIT/class initialization and GC contribute variance. No CPU affinity, exclusive machine reservation, thermal/power control or statistical significance claim is made. Examine medians and SD before interpreting small differences.
- Available physical RAM at the start was 1.015 GiB out of 15.729 GiB. Background memory pressure and paging were not controlled or monitored; they may affect runtime and working-set results.
- Dataset loading is excluded from runtime, but its retained data and cache/heap effects remain. Heap/process memory are not algorithm-exclusive. Process lifetime peaks can be dominated by loading the ARFF.
- Charts: Created all three PNG charts with .NET Charting. Charts show means; the CSV also contains medians and sample SD. A separate process_memory_comparison.png prevents confusing process RAM with heap.

## Reproduction and references

Run from the project directory: powershell -NoProfile -ExecutionPolicy Bypass -File .\benchmark_weka\Run-Benchmark.ps1

The harness discovers installed paths, verifies jar version and compiles into a unique result directory. The README describes explicit path overrides and missing-JDK installation. No download is needed on the machine measured here.

- [WEKA 3.8 Apriori API](https://weka.sourceforge.io/doc.stable-3-8/weka/associations/Apriori.html)
- [WEKA 3.8 FP-Growth API](https://weka.sourceforge.io/doc.stable-3-8/weka/associations/FPGrowth.html)
- [Java MemoryMXBean](https://docs.oracle.com/en/java/javase/25/docs/api/java.management/java/lang/management/MemoryMXBean.html)
- [Windows Process.PeakWorkingSet64](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.peakworkingset64)
- The installed weka-src.jar was inspected for this exact WEKA version; jar/source locations are not guessed from online documentation.
