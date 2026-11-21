[CmdletBinding()]
param(
    [string]$Dataset,
    [string]$WekaJar,
    [string]$Java,
    [string]$Javac,
    [ValidateRange(5,100)][int]$Repetitions = 5,
    [ValidateRange(1,1000)][int]$HeapSampleMilliseconds = 1,
    [ValidateRange(1,1000)][int]$ProcessPollMilliseconds = 5,
    [ValidateRange(10,3600)][int]$RunTimeoutSeconds = 180,
    [string]$InitialHeap = '256m',
    [string]$MaximumHeap = '2g',
    [int]$Seed = 20261113,
    [switch]$SkipCharts
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
if (-not $Dataset) { $Dataset = Join-Path (Split-Path $PSScriptRoot -Parent) 'groceries_basket.arff' }
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object Text.UTF8Encoding($false)

function Write-Utf8([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Resolve-Executable([string]$Explicit,[string]$Command) {
    if ($Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }
    $found = Get-Command $Command -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}
function Quote-Argument([string]$Value) {
    # File paths on Windows cannot contain a quote; all other arguments are controlled here.
    if ($Value.Contains('"') -or $Value.EndsWith('\')) { throw "Unsupported native argument: $Value" }
    return '"' + $Value + '"'
}
function Get-SourceManifest {
    $manifest = @()
    foreach ($file in Get-ChildItem -LiteralPath (Split-Path $PSScriptRoot -Parent) -File) {
        $manifest += [pscustomobject]@{path=$file.FullName; length=$file.Length;
            sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
    }
    return $manifest
}
function Get-Statistics([double[]]$Values) {
    if ($Values.Count -lt 2) { throw 'At least two observations are required for sample SD.' }
    $sorted = @($Values | Sort-Object)
    $mean = ($Values | Measure-Object -Average).Average
    $middle = [int][Math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2) { $sorted[$middle] } else { ($sorted[$middle-1] + $sorted[$middle]) / 2.0 }
    $sumSquares = 0.0
    foreach ($value in $Values) { $sumSquares += [Math]::Pow($value - $mean,2) }
    return [pscustomobject]@{n=$Values.Count; mean=$mean; median=$median;
        sd=[Math]::Sqrt($sumSquares/($Values.Count-1)); min=$sorted[0]; max=$sorted[-1]}
}

# Resolve actual installations; never infer a jar just from a presumed directory name.
if (-not $WekaJar) {
    $candidates = @()
    if ($env:WEKA_HOME) { $candidates += Join-Path $env:WEKA_HOME 'weka.jar' }
    foreach ($root in @($env:ProgramFiles,${env:ProgramFiles(x86)},(Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            foreach ($dir in Get-ChildItem -LiteralPath $root -Directory -Filter '*weka*' -ErrorAction SilentlyContinue) {
                $candidates += Join-Path $dir.FullName 'weka.jar'
            }
        }
    }
    $candidates = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique)
    if ($candidates.Count -ne 1) {
        throw "Found $($candidates.Count) WEKA jars. Specify the installed WEKA 3.8.7 jar using -WekaJar 'actual-path\weka.jar'. Candidates: $($candidates -join ', ')"
    }
    $WekaJar = $candidates[0]
}
$WekaJar = (Resolve-Path -LiteralPath $WekaJar).Path
$Dataset = (Resolve-Path -LiteralPath $Dataset).Path
if (-not $Java) {
    $bundledRoot = Join-Path (Split-Path $WekaJar -Parent) 'jre'
    if (Test-Path -LiteralPath $bundledRoot) {
        $bundled = @(Get-ChildItem -LiteralPath $bundledRoot -Filter 'java.exe' -Recurse -File)
        if ($bundled.Count -eq 1) { $Java = $bundled[0].FullName }
    }
}
$Java = Resolve-Executable $Java 'java.exe'
$Javac = Resolve-Executable $Javac 'javac.exe'
if (-not $Javac) {
    throw 'JDK compiler javac was not found. Install a 64-bit JDK from https://adoptium.net/temurin/releases/, enable Add to PATH, open a new PowerShell, then verify javac -version. Or pass -Javac with the actual javac.exe path.'
}
if (-not $Java) { throw 'Java was not found. Install a JDK or pass -Java with the actual java.exe path.' }

$runId = 'run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$resultDirectory = Join-Path (Join-Path $PSScriptRoot 'results') $runId
[void][IO.Directory]::CreateDirectory($resultDirectory)
$buildDirectory = Join-Path $resultDirectory 'classes'
$detailDirectory = Join-Path $resultDirectory 'runs'
[void][IO.Directory]::CreateDirectory($buildDirectory)
[void][IO.Directory]::CreateDirectory($detailDirectory)
$originalWekaHome = $env:WEKA_HOME
$env:WEKA_HOME = Join-Path $resultDirectory 'weka_home'
[void][IO.Directory]::CreateDirectory($env:WEKA_HOME)
$rawPath = Join-Path $resultDirectory 'benchmark_raw.csv'
$summaryPath = Join-Path $resultDirectory 'benchmark_summary.csv'
$manifestBefore = @(Get-SourceManifest)
Write-Utf8 (Join-Path $resultDirectory 'original_files_before.json') (ConvertTo-Json -InputObject $manifestBefore -Depth 5)
Write-Host "WEKA jar : $WekaJar"
Write-Host "Java     : $Java"
Write-Host "Compiler : $Javac"
Write-Host "Results  : $resultDirectory"

$ErrorActionPreference = 'Continue'
$compilerVersion = (& $Javac -version 2>&1 | Out-String).Trim()
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw "Cannot run javac: $compilerVersion" }
$compilerArguments = @('-encoding','UTF-8','-Xlint:-options','--release','8','-cp',$WekaJar,'-d',$buildDirectory,
    (Join-Path $PSScriptRoot 'WekaBenchmark.java'))
if ($compilerVersion -match '^javac 1\.8\.') {
    $compilerArguments = @('-encoding','UTF-8','-Xlint:-options','-source','8','-target','8','-cp',$WekaJar,'-d',$buildDirectory,
        (Join-Path $PSScriptRoot 'WekaBenchmark.java'))
}
$ErrorActionPreference = 'Continue'
$compileLog = (& $Javac @compilerArguments 2>&1 | Out-String)
$ErrorActionPreference = 'Stop'
Write-Utf8 (Join-Path $resultDirectory 'compile.log') $compileLog
if ($LASTEXITCODE -ne 0) { throw "Compilation failed. See $resultDirectory\compile.log" }
$jvmArguments = @("-Xms$InitialHeap","-Xmx$MaximumHeap",'-XX:+UseG1GC','-Dfile.encoding=UTF-8',
    '-Djava.awt.headless=true','-cp',"$buildDirectory;$WekaJar",'WekaBenchmark')
$ErrorActionPreference = 'Continue'
$runtimeVersionText = (& $Java '-version' 2>&1 | Out-String)
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw "Cannot execute Java: $runtimeVersionText" }
if ($runtimeVersionText -match 'version "(?<major>\d+)') {
    if ([int]$Matches.major -ge 9) { $jvmArguments = @('--add-opens=java.base/java.lang=ALL-UNNAMED') + $jvmArguments }
}
$probePath = Join-Path $resultDirectory 'environment_java.json'
$ErrorActionPreference = 'Continue'
$probeLog = (& $Java @jvmArguments '--probe' $probePath 2>&1 | Out-String)
$ErrorActionPreference = 'Stop'
Write-Utf8 (Join-Path $resultDirectory 'probe.log') $probeLog
if ($LASTEXITCODE -ne 0) { throw "Java probe failed. See $resultDirectory\probe.log" }
$probe = Get-Content -LiteralPath $probePath -Raw | ConvertFrom-Json
if ($probe.weka_version -ne '3.8.7') { throw "WEKA 3.8.7 required, found $($probe.weka_version)" }

# WMI/CIM can be denied in managed sessions. Kernel32 and read-only registry queries suffice.
if (-not ('WekaBenchmarkNativeMemory' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WekaBenchmarkNativeMemory {
    [StructLayout(LayoutKind.Sequential)] private struct MEMORYSTATUSEX {
        public uint length, load;
        public ulong totalPhysical, availablePhysical, totalPageFile, availablePageFile;
        public ulong totalVirtual, availableVirtual, availableExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);
    public static ulong[] Read() {
        MEMORYSTATUSEX status = new MEMORYSTATUSEX();
        status.length = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        if (!GlobalMemoryStatusEx(ref status)) throw new System.ComponentModel.Win32Exception();
        return new ulong[]{status.totalPhysical,status.availablePhysical};
    }
}
'@
}
$physical = [WekaBenchmarkNativeMemory]::Read()
$cpu = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
$windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$environment = [ordered]@{
    started_utc=[DateTime]::UtcNow.ToString('o'); timezone='Asia/Saigon (UTC+07:00)';
    weka_jar=$WekaJar; weka_sha256=(Get-FileHash -LiteralPath $WekaJar -Algorithm SHA256).Hash;
    dataset=$Dataset; dataset_sha256=(Get-FileHash -LiteralPath $Dataset -Algorithm SHA256).Hash;
    java_exe=$Java; javac_exe=$Javac; compiler_version=$compilerVersion;
    java=$probe; jvm_arguments=$jvmArguments;
    isolated_weka_home=$env:WEKA_HOME; original_weka_home=$originalWekaHome;
    cpu_name=$cpu.ProcessorNameString.Trim(); logical_processors=[Environment]::ProcessorCount;
    physical_memory_bytes=$physical[0]; available_physical_memory_at_start_bytes=$physical[1];
    windows_registry_product_name=$windows.ProductName; windows_display_version=$windows.DisplayVersion;
    windows_build="$($windows.CurrentBuild).$($windows.UBR)";
    powershell_version=$PSVersionTable.PSVersion.ToString();
    repetitions_per_configuration_per_phase=$Repetitions; seed=$Seed;
    heap_requested_interval_ms=$HeapSampleMilliseconds; process_poll_requested_interval_ms=$ProcessPollMilliseconds;
    initial_heap=$InitialHeap; maximum_heap=$MaximumHeap;
    runtime_policy='First build in a fresh JVM; no warm-up builds; identical explicit GC and 100 ms pause before each run';
    source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'WekaBenchmark.java') -Algorithm SHA256).Hash
}
Write-Utf8 (Join-Path $resultDirectory 'environment.json') (ConvertTo-Json -InputObject $environment -Depth 8)

$allRows = New-Object 'System.Collections.Generic.List[object]'
$random = New-Object Random($Seed)
$configurations = @()
foreach ($support in @('0.01','0.005','0.002','0.001')) {
    $expected = @{'0.01'=10;'0.005'=57;'0.002'=219;'0.001'=450}[$support]
    foreach ($algorithm in @('Apriori','FPGrowth')) {
        $configurations += [pscustomobject]@{algorithm=$algorithm; support=$support; expected=$expected}
    }
}
$executionOrder = 0
try {
    foreach ($phase in @('runtime','memory')) {
        for ($repeat=1; $repeat -le $Repetitions; $repeat++) {
            $schedule = @($configurations)
            for ($i=$schedule.Count-1; $i -gt 0; $i--) {
                $j=$random.Next($i+1); $temporary=$schedule[$i]; $schedule[$i]=$schedule[$j]; $schedule[$j]=$temporary
            }
            foreach ($configuration in $schedule) {
                $executionOrder++
                $name = '{0:D3}_{1}_{2}_s{3}_r{4}' -f $executionOrder,$phase,$configuration.algorithm,$configuration.support,$repeat
                $jsonPath = Join-Path $detailDirectory ($name + '.json')
                $arguments = @($jvmArguments) + @($Dataset,$configuration.algorithm,$configuration.support,
                    $phase,[string]$repeat,[string]$HeapSampleMilliseconds,$jsonPath,[string]$configuration.expected)
                $argumentString = ($arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
                $process = Start-Process -FilePath $Java -ArgumentList $argumentString -PassThru -WindowStyle Hidden `
                    -RedirectStandardOutput (Join-Path $detailDirectory ($name + '.stdout.log')) `
                    -RedirectStandardError (Join-Path $detailDirectory ($name + '.stderr.log'))
                # Cache the native process handle before exit: Windows PowerShell 5.1 can
                # otherwise expose a null ExitCode for a short-lived -PassThru process.
                $null = $process.Handle
                $watch = [Diagnostics.Stopwatch]::StartNew()
                $processBaseline=$null; $processPeak=$null; $pollCount=0; $lastPoll=$null
                $gapSum=0.0; $maxGap=0.0
                try {
                    if ($phase -eq 'runtime') {
                        # No heap sampler thread or PowerShell process-memory polling in runtime runs.
                        if (-not $process.WaitForExit($RunTimeoutSeconds*1000)) { throw "Run timed out: $name" }
                    } else {
                        while (-not (Test-Path -LiteralPath ($jsonPath+'.ready'))) {
                            $process.Refresh()
                            if ($process.HasExited) { throw "JVM exited before memory baseline: $name; see stderr log" }
                            if ($watch.Elapsed.TotalSeconds -gt $RunTimeoutSeconds) { throw "Ready timeout: $name" }
                            Start-Sleep -Milliseconds $ProcessPollMilliseconds
                        }
                        $process.Refresh()
                        $processBaseline=[long]$process.WorkingSet64
                        $processPeak=[long]$process.PeakWorkingSet64
                        [IO.File]::WriteAllText($jsonPath+'.go','')
                        while ($true) {
                            $process.Refresh()
                            if ($process.HasExited) { throw "JVM exited before memory capture: $name; see stderr log" }
                            $processPeak=[Math]::Max($processPeak,[long]$process.PeakWorkingSet64)
                            $now=$watch.Elapsed.TotalMilliseconds
                            if ($null -ne $lastPoll) {
                                $gap=$now-$lastPoll; $gapSum+=$gap; $maxGap=[Math]::Max($maxGap,$gap)
                            }
                            $lastPoll=$now; $pollCount++
                            if (Test-Path -LiteralPath ($jsonPath+'.complete')) { break }
                            if ($watch.Elapsed.TotalSeconds -gt $RunTimeoutSeconds) { throw "Memory run timeout: $name" }
                            Start-Sleep -Milliseconds $ProcessPollMilliseconds
                        }
                        # OS high-water mark is retained while the worker waits at the final handshake.
                        $process.Refresh()
                        $processPeak=[Math]::Max($processPeak,[long]$process.PeakWorkingSet64)
                        [IO.File]::WriteAllText($jsonPath+'.release','')
                        if (-not $process.WaitForExit(10000)) { throw "Exit handshake timeout: $name" }
                    }
                    $process.WaitForExit()
                    if (-not (Test-Path -LiteralPath $jsonPath)) { throw "No worker result: $name; see stderr log" }
                    $row=Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
                    $row | Add-Member -NotePropertyName execution_order -NotePropertyValue $executionOrder
                    $row | Add-Member -NotePropertyName process_working_set_baseline_bytes -NotePropertyValue $processBaseline
                    $row | Add-Member -NotePropertyName process_peak_working_set_bytes -NotePropertyValue $processPeak
                    $row | Add-Member -NotePropertyName process_poll_count -NotePropertyValue $pollCount
                    $row | Add-Member -NotePropertyName process_poll_requested_ms -NotePropertyValue $(if($phase -eq 'memory'){$ProcessPollMilliseconds}else{$null})
                    $row | Add-Member -NotePropertyName process_poll_actual_mean_ms -NotePropertyValue $(if($pollCount -gt 1){$gapSum/($pollCount-1)}else{$null})
                    $row | Add-Member -NotePropertyName process_poll_actual_max_ms -NotePropertyValue $(if($pollCount -gt 1){$maxGap}else{$null})
                    $row | Add-Member -NotePropertyName worker_exit_code -NotePropertyValue $process.ExitCode
                    $row | Add-Member -NotePropertyName result_json -NotePropertyValue ('runs/'+$name+'.json')
                    $allRows.Add($row)
                    if ($allRows.Count -eq 1) { $row | Export-Csv -LiteralPath $rawPath -NoTypeInformation -Encoding UTF8 }
                    else { $row | Export-Csv -LiteralPath $rawPath -Append -NoTypeInformation -Encoding UTF8 }
                    if ($null -eq $process.ExitCode) { throw "Could not obtain JVM exit code: $name" }
                    if ($row.status -ne 'OK' -or $process.ExitCode -ne 0) {
                        throw "Rule validation/run failure: $name; expected=$($row.expected_rules), actual=$($row.actual_rules), exit=$($process.ExitCode). Raw measurements retained. Do not replace the observed rule count."
                    }
                    $metric=if($phase -eq 'runtime'){'{0:F2} ms' -f $row.runtime_ms}else{'heap {0:F2} MiB; process {1:F2} MiB' -f ($row.heap_peak_sampled_bytes/1MB),($processPeak/1MB)}
                    Write-Host ('[{0}/{1}] {2} {3} support={4} repeat={5}: {6}; rules={7}' -f $executionOrder,($Repetitions*16),$phase,$configuration.algorithm,$configuration.support,$repeat,$metric,$row.actual_rules)
                } finally {
                    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
                    $process.Dispose()
                }
            }
        }
    }

    # Compare actual rule identities and integer supports across both algorithms and all JVMs.
    foreach ($support in @('0.01','0.005','0.002','0.001')) {
        $hashes=@($allRows | Where-Object {[double]$_.min_support -eq [double]$support} | Select-Object -ExpandProperty rule_set_sha256 -Unique)
        if ($hashes.Count -ne 1) { throw "Rule sets differ at support $support. Inspect the exported *.rules.tsv and raw hashes; no valid comparison can be declared." }
    }
    $summary = @()
    foreach ($configuration in $configurations) {
        $selected=@($allRows | Where-Object {$_.algorithm -eq $configuration.algorithm -and [double]$_.min_support -eq [double]$configuration.support})
        $runtime=@($selected | Where-Object {$_.phase -eq 'runtime'})
        $memory=@($selected | Where-Object {$_.phase -eq 'memory'})
        if ($runtime.Count -ne $Repetitions -or $memory.Count -ne $Repetitions) { throw 'Incomplete measurements' }
        $runtimeStats=Get-Statistics @($runtime | ForEach-Object {[double]$_.runtime_ms})
        $heapBaseline=Get-Statistics @($memory | ForEach-Object {[double]$_.heap_baseline_bytes/1MB})
        $heapPeak=Get-Statistics @($memory | ForEach-Object {[double]$_.heap_peak_sampled_bytes/1MB})
        $heapDelta=Get-Statistics @($memory | ForEach-Object {[double]$_.heap_peak_minus_baseline_bytes/1MB})
        $processBaselineStats=Get-Statistics @($memory | ForEach-Object {[double]$_.process_working_set_baseline_bytes/1MB})
        $processPeakStats=Get-Statistics @($memory | ForEach-Object {[double]$_.process_peak_working_set_bytes/1MB})
        $record=[ordered]@{algorithm=$configuration.algorithm; min_support=$configuration.support;
            rules=$configuration.expected; validation='OK: count and rule-set SHA-256 match';
            runtime_n=$runtime.Count; memory_n=$memory.Count}
        foreach ($stat in @('mean','median','sd','min','max')) { $record['runtime_'+$stat+'_ms']=$runtimeStats.$stat }
        foreach ($metric in @(
            @('heap_baseline',$heapBaseline),@('heap_peak',$heapPeak),@('heap_peak_minus_baseline',$heapDelta),
            @('process_baseline',$processBaselineStats),@('process_peak',$processPeakStats))) {
            foreach ($stat in @('mean','median','sd','min','max')) { $record[$metric[0]+'_'+$stat+'_mib']=$metric[1].$stat }
        }
        $record['rule_set_sha256']=$selected[0].rule_set_sha256
        $summary += [pscustomobject]$record
    }
    $summary | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
    $chartStatus='Skipped by request'
    if (-not $SkipCharts) {
        try { & (Join-Path $PSScriptRoot 'Create-Charts.ps1') -ResultDirectory $resultDirectory; $chartStatus='Created all three PNG charts with .NET Charting' }
        catch { $chartStatus='Chart creation failed; CSV measurements are complete: '+$_.Exception.Message; Write-Warning $chartStatus }
    }
    $manifestAfter=@(Get-SourceManifest)
    Write-Utf8 (Join-Path $resultDirectory 'original_files_after.json') (ConvertTo-Json -InputObject $manifestAfter -Depth 5)
    foreach ($original in $manifestBefore) {
        $after=@($manifestAfter | Where-Object {$_.path -eq $original.path})
        if ($after.Count -ne 1 -or $after[0].sha256 -ne $original.sha256) { throw "Original file changed: $($original.path)" }
    }
    if ((Get-FileHash -LiteralPath $Dataset -Algorithm SHA256).Hash -ne $environment.dataset_sha256) { throw 'Input ARFF changed during benchmark' }
    $environment['finished_utc']=[DateTime]::UtcNow.ToString('o')
    $environment['all_original_files_unchanged']=$true
    $environment['chart_status']=$chartStatus
    Write-Utf8 (Join-Path $resultDirectory 'environment.json') (ConvertTo-Json -InputObject $environment -Depth 8)

    $table=@('| Support | Rules | Apriori mean +/- SD (ms) | FP-Growth mean +/- SD (ms) | Apriori heap peak (MiB) | FP-Growth heap peak (MiB) | Apriori process peak (MiB) | FP-Growth process peak (MiB) |',
        '|---|---:|---:|---:|---:|---:|---:|---:|')
    $speedLines=@()
    foreach ($support in @('0.01','0.005','0.002','0.001')) {
        $a=@($summary | Where-Object {$_.algorithm -eq 'Apriori' -and $_.min_support -eq $support})[0]
        $f=@($summary | Where-Object {$_.algorithm -eq 'FPGrowth' -and $_.min_support -eq $support})[0]
        $table += '| {0} | {1} | {2:F3} +/- {3:F3} | {4:F3} +/- {5:F3} | {6:F2} | {7:F2} | {8:F2} | {9:F2} |' -f $support,$a.rules,$a.runtime_mean_ms,$a.runtime_sd_ms,$f.runtime_mean_ms,$f.runtime_sd_ms,$a.heap_peak_mean_mib,$f.heap_peak_mean_mib,$a.process_peak_mean_mib,$f.process_peak_mean_mib
        $speedLines += '- Support {0}: Apriori / FP-Growth mean runtime ratio = {1:F3}; heap peak ratio = {2:F3}; process peak ratio = {3:F3}.' -f $support,($a.runtime_mean_ms/$f.runtime_mean_ms),($a.heap_peak_mean_mib/$f.heap_peak_mean_mib),($a.process_peak_mean_mib/$f.process_peak_mean_mib)
    }
    $heapMeanGaps=Get-Statistics @($allRows | Where-Object {$_.phase -eq 'memory'} | ForEach-Object {[double]$_.heap_actual_mean_interval_ms})
    $heapMaxGap=($allRows | Where-Object {$_.phase -eq 'memory'} | Measure-Object -Property heap_actual_max_interval_ms -Maximum).Maximum
    $methodology=@"
# WEKA Apriori / FP-Growth benchmark methodology

Completed UTC: $($environment.finished_utc). Display timezone: Asia/Saigon (UTC+07:00).

## Data and implementation

- Existing ARFF: $Dataset
- SHA-256: $($environment.dataset_sha256)
- 14,963 baskets, 167 nominal product attributes, ordered values {f,t}, no class, no missing values, unit instance weights. Validated without changing the data. No CSV was read, no filter applied, and no synthetic data used.
- Mining uses only weka.associations.Apriori and weka.associations.FPGrowth from the installed WEKA jar. The harness implements measurement and rule comparison, not mining.
- WEKA $($probe.weka_version); jar: $WekaJar; SHA-256: $($environment.weka_sha256).
- Java: $($probe.java_vendor), $($probe.java_runtime_version), $($probe.java_vm_name). Executable: $Java.
- Compiler: $compilerVersion; executable: $Javac. Classes target Java 8 bytecode.
- CPU: $($environment.cpu_name); $($environment.logical_processors) logical processors available to the process.
- Physical RAM: $([Math]::Round($physical[0]/1GB,3)) GiB; available at start: $([Math]::Round($physical[1]/1GB,3)) GiB.
- Windows kernel $($probe.os_version), $($probe.os_arch); build $($environment.windows_build), display version $($windows.DisplayVersion). Registry product label: $($windows.ProductName). Windows registry product labels may retain Windows 10 wording on Windows 11.
- PowerShell: $($environment.powershell_version). Machine details were read using Kernel32 and the registry because CIM access can be denied.
- JVM flags: -Xms$InitialHeap -Xmx$MaximumHeap -XX:+UseG1GC -Dfile.encoding=UTF-8 -Djava.awt.headless=true; Java 9+ also uses --add-opens=java.base/java.lang=ALL-UNNAMED as required by the installed WEKA launcher. Collector names: $($probe.garbage_collectors).
- WEKA package infrastructure is initialized before measurement. Each benchmark invocation uses an isolated empty WEKA_HOME inside its result directory, so external packages are not loaded and existing user package directories are not changed.

## Exact algorithm settings

- Supports: 0.01, 0.005, 0.002, 0.001; confidence threshold 0.05; confidence ranking (metric type 0); upper support bound 1.0; no class association rules.
- Apriori: treatZeroAsMissing=true (-Z), numRules=1000, lowerBoundMinSupport=support, delta=1.0-support, significanceLevel=-1, classIndex=-1, outputItemSets=false, verbose=false. The Explorer -I output flag is intentionally disabled as requested; the installed source uses it only for textual itemset output.
- FP-Growth: positiveIndex=2 (the nominal value t), maxNumberOfItems=-1, findAllRulesForSupportLevel=true (-S), lowerBoundMinSupport=support, numRulesToFind=10, delta=0.05. The latter two settings match saved Explorer output; -S disables rule-count stopping and iterative support reduction.
- All effective option strings are retained in each worker JSON and in benchmark_raw.csv.
- Installed Apriori source initializes support with 1.0-delta and uses floating-point comparisons in its support-reduction loop. The saved Explorer runs report two cycles for these settings. The benchmark preserves this behavior and does not alter WEKA to force one pass.

## Runtime

- $Repetitions independent JVMs per algorithm/support, $($Repetitions*8) runtime runs. No simultaneous benchmark JVMs. The first build in each JVM is measured; there are no warm-up builds. These are cold algorithm invocations, not steady-state warmed JIT measurements.
- Each JVM reads and validates the ARFF and constructs the associator before measurement. Explicit System.gc() followed by a 100 ms pause is requested before each build in both phases; GC is a request, not a guarantee of an identical live baseline.
- The measured source is exactly: start=System.nanoTime(); algorithm.buildAssociations(data); elapsed=System.nanoTime()-start. Class loading/JIT/GC triggered inside buildAssociations remain part of the measured operation.
- JVM startup, ARFF reading, external process startup, baseline preparation, rule materialization/checking, console printing, and exports are outside this interval. No algorithm model/itemset output is requested during build.
- Runtime runs have no heap-sampling thread and no PowerShell memory polling. GC counter reads occur outside the timing interval.
- For each repetition, the eight configurations are shuffled with Fisher-Yates, seed $Seed. The two phases run sequentially, runtime then memory. Execution order and worker PID are retained.
- Summary: arithmetic mean, median, sample standard deviation (denominator n-1), min and max; no observations discarded. runtime_ms is populated only for uninstrumented runs. Instrumented memory-run time is retained separately and excluded from runtime summaries.

## Java heap measurement

- A separate $($Repetitions*8)-JVM memory phase uses MemoryMXBean.getHeapMemoryUsage().getUsed(), requested every $HeapSampleMilliseconds ms by a dedicated daemon thread. The thread and management APIs are initialized before baseline GC.
- Baseline is heap used after ARFF loading, algorithm setup and requested GC, immediately before enabling the sampler and build. The baseline includes the dataset, the JVM's Java objects and harness objects; it is not algorithm-only memory.
- Peak is the maximum of that baseline, samples during build, and boundary samples immediately before/after the call. Sampling stops before converting/exporting rules. It is a sampled lower-bound estimate of peak total used Java heap, not exact instantaneous peak and not retained/live memory.
- Sampling can miss allocation/GC spikes between samples; scheduler delays and safepoints can enlarge gaps. getUsed includes allocated objects not yet collected and collector/TLAB accounting effects. Do not interpret it as total allocated bytes or algorithm-exclusive memory.
- Each raw row records requested interval, sample count, actual mean gap and actual maximum gap. Across memory runs, the mean of actual mean gaps was $($heapMeanGaps.mean.ToString('F3')) ms; the largest observed gap was $(([double]$heapMaxGap).ToString('F3')) ms.
- heap_peak_minus_baseline_bytes is explicitly sampled peak minus baseline. It is an auxiliary increase, not a peak derived from end-minus-start. No after-minus-before value is used as the peak.
- Sampling and synchronization have overhead. Memory-run runtimes are not used to judge algorithm speed.

## Whole-process RAM on Windows

- PowerShell reads Process.WorkingSet64 at a ready/go handshake after dataset loading for the process baseline.
- PowerShell polls Process.PeakWorkingSet64 with a requested $ProcessPollMilliseconds ms interval during each memory run. This property is the OS-retained high-water mark, not merely the highest instantaneous WorkingSet64 sample. Actual observation gaps are recorded in the raw CSV.
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

$($table -join "`n")

$($speedLines -join "`n")

Heap/process columns above are means of five independent run peaks (or the configured repetition count), not the maximum over all repetitions. Median, sample SD, min/max and baseline measurements are in benchmark_summary.csv. All memory units are MiB (1,048,576 bytes); runtime is milliseconds.

## Interpretation limits

- These measurements apply to this ARFF, installed WEKA implementation, JVM settings and machine. They do not establish universal algorithm superiority or compare different implementations.
- Apriori's support-loop behavior and rule generation are included exactly as configured; FP-Growth -S mines one fixed support level. A difference reflects these Explorer-equivalent implementations/settings, not a controlled count of internal passes.
- Five fresh JVMs are a small sample; OS scheduling, background activity, disk-cache effects, JIT/class initialization and GC contribute variance. No CPU affinity, exclusive machine reservation, thermal/power control or statistical significance claim is made. Examine medians and SD before interpreting small differences.
- Available physical RAM at the start was $([Math]::Round($physical[1]/1GB,3)) GiB out of $([Math]::Round($physical[0]/1GB,3)) GiB. Background memory pressure and paging were not controlled or monitored; they may affect runtime and working-set results.
- Dataset loading is excluded from runtime, but its retained data and cache/heap effects remain. Heap/process memory are not algorithm-exclusive. Process lifetime peaks can be dominated by loading the ARFF.
- Charts: $chartStatus. Charts show means; the CSV also contains medians and sample SD. A separate process_memory_comparison.png prevents confusing process RAM with heap.

## Reproduction and references

Run from the project directory: powershell -NoProfile -ExecutionPolicy Bypass -File .\benchmark_weka\Run-Benchmark.ps1

The harness discovers installed paths, verifies jar version and compiles into a unique result directory. The README describes explicit path overrides and missing-JDK installation. No download is needed on the machine measured here.

- [WEKA 3.8 Apriori API](https://weka.sourceforge.io/doc.stable-3-8/weka/associations/Apriori.html)
- [WEKA 3.8 FP-Growth API](https://weka.sourceforge.io/doc.stable-3-8/weka/associations/FPGrowth.html)
- [Java MemoryMXBean](https://docs.oracle.com/en/java/javase/25/docs/api/java.management/java/lang/management/MemoryMXBean.html)
- [Windows Process.PeakWorkingSet64](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.peakworkingset64)
- The installed weka-src.jar was inspected for this exact WEKA version; jar/source locations are not guessed from online documentation.
"@
    Write-Utf8 (Join-Path $resultDirectory 'benchmark_methodology.md') $methodology
    $summary | Select-Object algorithm,min_support,rules,runtime_mean_ms,runtime_median_ms,runtime_sd_ms,heap_baseline_mean_mib,heap_peak_mean_mib,process_baseline_mean_mib,process_peak_mean_mib | Format-Table -AutoSize | Out-String -Width 240 | Write-Host
    Write-Host "Completed successfully: $resultDirectory"
} catch {
    Write-Utf8 (Join-Path $resultDirectory 'FAILED.txt') ($_.Exception.ToString()+"`nPartial results and per-JVM logs are preserved. No valid complete benchmark is declared.")
    throw
} finally {
    $env:WEKA_HOME = $originalWekaHome
}
