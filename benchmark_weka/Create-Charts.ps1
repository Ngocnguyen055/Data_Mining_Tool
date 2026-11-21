param([Parameter(Mandatory=$true)][string]$ResultDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Drawing
$rows = @(Import-Csv -LiteralPath (Join-Path $ResultDirectory 'benchmark_summary.csv'))
$supports = @('0.01','0.005','0.002','0.001')
$runEnvironment = Get-Content -LiteralPath (Join-Path $ResultDirectory 'environment.json') -Raw | ConvertFrom-Json
$repeatCount = [int]$rows[0].runtime_n
$heapInterval = [int]$runEnvironment.heap_requested_interval_ms

function New-ComparisonChart {
    param([string]$FileName, [string]$Title, [string]$YAxis,
          [string]$FirstColumn, [string]$SecondColumn, [string]$FirstLabel,
          [string]$SecondLabel, [string]$Footer)
    $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    try {
        $chart.Width = 1350; $chart.Height = 800
        $chart.BackColor = [Drawing.Color]::White
        $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea 'Main'
        $area.Position.Auto = $false
        $area.Position.X = 3; $area.Position.Y = 12
        $area.Position.Width = 95; $area.Position.Height = 70
        $area.AxisX.Title = 'Minimum support'
        $area.AxisY.Title = $YAxis
        $area.AxisX.Interval = 1
        $area.AxisX.Minimum = 0.5; $area.AxisX.Maximum = 4.5
        $area.AxisY.Minimum = 0
        $area.AxisX.MajorGrid.Enabled = $false
        $area.AxisY.MajorGrid.LineColor = [Drawing.Color]::FromArgb(225,230,237)
        $area.AxisY.LabelStyle.Format = '0.##'
        $area.AxisX.TitleFont = New-Object Drawing.Font('Segoe UI',13)
        $area.AxisY.TitleFont = New-Object Drawing.Font('Segoe UI',13)
        $area.AxisX.LabelStyle.Font = New-Object Drawing.Font('Segoe UI',12)
        $area.AxisY.LabelStyle.Font = New-Object Drawing.Font('Segoe UI',11)
        $chart.ChartAreas.Add($area)
        $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend 'Legend'
        $legend.Docking = 'Bottom'; $legend.Font = New-Object Drawing.Font('Segoe UI',12)
        $chart.Legends.Add($legend)
        $titleObject = $chart.Titles.Add($Title)
        $titleObject.Font = New-Object Drawing.Font('Segoe UI',19,[Drawing.FontStyle]::Bold)
        $titleObject.Position.Auto = $false
        $titleObject.Position.X = 0; $titleObject.Position.Y = 1
        $titleObject.Position.Width = 100; $titleObject.Position.Height = 7
        $footerObject = $chart.Titles.Add($Footer)
        $footerObject.Docking = 'Bottom'
        $footerObject.Font = New-Object Drawing.Font('Segoe UI',10)
        $colors = @([Drawing.Color]::FromArgb(37,99,185),[Drawing.Color]::FromArgb(220,108,36))
        for ($seriesIndex=0; $seriesIndex -lt 2; $seriesIndex++) {
            $seriesLabel = if ($seriesIndex -eq 0) { $FirstLabel } else { $SecondLabel }
            $column = if ($seriesIndex -eq 0) { $FirstColumn } else { $SecondColumn }
            $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series $seriesLabel
            $series.ChartType = 'Column'; $series.Color = $colors[$seriesIndex]
            $series.IsXValueIndexed = $true
            $series.IsValueShownAsLabel = $true; $series.LabelFormat = '0.00'
            $series.Font = New-Object Drawing.Font('Segoe UI',10)
            foreach ($support in $supports) {
                $algorithm = if ($column -like 'runtime*') { $seriesLabel } else { $FirstLabel.Split(' ')[0] }
                $row = @($rows | Where-Object { $_.algorithm -eq $algorithm -and $_.min_support -eq $support })
                if ($row.Count -ne 1) { throw "Chart row not found: $algorithm/$support" }
                $pointIndex = $series.Points.AddY([double]$row[0].$column)
                $series.Points[$pointIndex].AxisLabel = $support
            }
            $chart.Series.Add($series)
        }
        $chart.SaveImage((Join-Path $ResultDirectory $FileName),'Png')
    } finally { $chart.Dispose() }
}

New-ComparisonChart -FileName 'runtime_comparison.png' -Title 'WEKA 3.8.7 - buildAssociations runtime' `
    -YAxis 'Mean runtime (ms)' -FirstColumn 'runtime_mean_ms' -SecondColumn 'runtime_mean_ms' `
    -FirstLabel 'Apriori' -SecondLabel 'FPGrowth' `
    -Footer "$repeatCount independent JVMs per configuration; no memory sampling. See CSV for median and sample SD."

# Four series distinguish heap baseline/peak for both algorithms. Process RAM is a separate chart.
function New-MemoryChart {
    param([string]$FileName,[string]$Title,[string]$Baseline,[string]$Peak,[string]$Footer)
    $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    try {
        $chart.Width=1350; $chart.Height=800; $chart.BackColor=[Drawing.Color]::White
        $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea 'Main'
        $area.Position.Auto=$false; $area.Position.X=3; $area.Position.Y=12
        $area.Position.Width=95; $area.Position.Height=70
        $area.AxisX.Title='Minimum support'; $area.AxisX.Interval=1
        $area.AxisX.Minimum=0.5; $area.AxisX.Maximum=4.5
        $area.AxisY.Title='Mean memory (MiB; 1 MiB = 1,048,576 bytes)'; $area.AxisY.Minimum=0
        $area.AxisX.MajorGrid.Enabled=$false
        $area.AxisY.MajorGrid.LineColor=[Drawing.Color]::FromArgb(225,230,237)
        $area.AxisY.LabelStyle.Format='0.#'
        $area.AxisX.TitleFont=New-Object Drawing.Font('Segoe UI',13)
        $area.AxisY.TitleFont=New-Object Drawing.Font('Segoe UI',13)
        $area.AxisX.LabelStyle.Font=New-Object Drawing.Font('Segoe UI',12)
        $area.AxisY.LabelStyle.Font=New-Object Drawing.Font('Segoe UI',11)
        $chart.ChartAreas.Add($area)
        $legend=New-Object System.Windows.Forms.DataVisualization.Charting.Legend 'Legend'
        $legend.Docking='Bottom'; $legend.Font=New-Object Drawing.Font('Segoe UI',11)
        $chart.Legends.Add($legend)
        $t=$chart.Titles.Add($Title); $t.Font=New-Object Drawing.Font('Segoe UI',18,[Drawing.FontStyle]::Bold)
        $t.Position.Auto=$false; $t.Position.X=0; $t.Position.Y=1; $t.Position.Width=100; $t.Position.Height=7
        $f=$chart.Titles.Add($Footer); $f.Docking='Bottom'; $f.Font=New-Object Drawing.Font('Segoe UI',10)
        $colors=@('#93B7E4','#2563B9','#F4B78C','#DC6C24')
        $index=0
        foreach ($algorithm in @('Apriori','FPGrowth')) {
            foreach ($kind in @('baseline','peak')) {
                $column=if($kind -eq 'baseline'){$Baseline}else{$Peak}
                $series=New-Object System.Windows.Forms.DataVisualization.Charting.Series "$algorithm $kind"
                $series.ChartType='Column'; $series.Color=[Drawing.ColorTranslator]::FromHtml($colors[$index])
                $series.IsXValueIndexed=$true
                $index++; $series.IsValueShownAsLabel=$true; $series.LabelFormat='0.0'
                $series.Font=New-Object Drawing.Font('Segoe UI',9)
                foreach($support in $supports){
                    $row=@($rows | Where-Object {$_.algorithm -eq $algorithm -and $_.min_support -eq $support})[0]
                    $pointIndex=$series.Points.AddY([double]$row.$column)
                    $series.Points[$pointIndex].AxisLabel=$support
                }
                $chart.Series.Add($series)
            }
        }
        $chart.SaveImage((Join-Path $ResultDirectory $FileName),'Png')
    } finally { $chart.Dispose() }
}
New-MemoryChart -FileName 'memory_comparison.png' -Title 'WEKA 3.8.7 - sampled Java heap used' `
    -Baseline 'heap_baseline_mean_mib' -Peak 'heap_peak_mean_mib' `
    -Footer "Separate memory runs; requested $heapInterval ms sampling. Sampled peaks may miss short spikes; includes dataset and harness."
New-MemoryChart -FileName 'process_memory_comparison.png' -Title 'WEKA 3.8.7 - whole JVM process RAM' `
    -Baseline 'process_baseline_mean_mib' -Peak 'process_peak_mean_mib' `
    -Footer 'PeakWorkingSet64 is the OS high-water mark for the whole process, including startup and ARFF loading.'
