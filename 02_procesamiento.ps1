#!/usr/bin/env pwsh
param(
    [string]$InputCsv,
    [string]$OutputJson
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $InputCsv)   { $InputCsv   = Join-Path $ScriptDir 'data/metrics_raw.csv' }
if (-not $OutputJson) { $OutputJson = Join-Path $ScriptDir 'data/report.json' }

function ConvertTo-Number([string]$s) {
    return [double]::Parse(($s -replace ',', '.'),
        [System.Globalization.CultureInfo]::InvariantCulture)
}

$cfg = @{
    CPU_WARN = 75; CPU_CRIT = 90
    MEM_WARN = 80; MEM_CRIT = 90
    DISK_WARN = 80; DISK_CRIT = 90
}
$cfgFile = Join-Path $ScriptDir 'config.env'
if (Test-Path $cfgFile) {
    foreach ($line in Get-Content $cfgFile) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#') -or -not $t.Contains('=')) { continue }
        $k, $v = $t -split '=', 2
        $cfg[$k.Trim()] = $v.Trim().Trim('"').Trim("'")
    }
}

if (-not (Test-Path $InputCsv)) {
    Write-Error "No se encontro el archivo de entrada: $InputCsv"
    exit 1
}
$rows = Import-Csv -Path $InputCsv
$m = @{}
foreach ($r in $rows) { $m[$r.metric.Trim()] = ConvertTo-Number $r.value.Trim() }

function Get-Status([double]$val, [double]$warn, [double]$crit) {
    if ($val -ge $crit)      { return 'CRITICAL' }
    elseif ($val -ge $warn)  { return 'WARNING' }
    else                     { return 'OK' }
}

$defs = @(
    @{ name = 'cpu';    label = 'CPU Usage';      value = $m['cpu_usage'];    unit = 'percent'; warn = (ConvertTo-Number $cfg.CPU_WARN);  crit = (ConvertTo-Number $cfg.CPU_CRIT) },
    @{ name = 'memory'; label = 'Memory Usage';   value = $m['mem_used_pct']; unit = 'percent'; warn = (ConvertTo-Number $cfg.MEM_WARN);  crit = (ConvertTo-Number $cfg.MEM_CRIT) },
    @{ name = 'disk';   label = 'Disk Usage (/)'; value = $m['disk_used_pct']; unit = 'percent'; warn = (ConvertTo-Number $cfg.DISK_WARN); crit = (ConvertTo-Number $cfg.DISK_CRIT) }
)

$sevRank = @{ 'OK' = 0; 'WARNING' = 1; 'CRITICAL' = 2 }
$overallRank = 0
$metrics = @()
foreach ($d in $defs) {
    $st = Get-Status $d.value $d.warn $d.crit
    if ($sevRank[$st] -gt $overallRank) { $overallRank = $sevRank[$st] }
    $metrics += [ordered]@{
        name               = $d.name
        label              = $d.label
        value              = $d.value
        unit               = $d.unit
        status             = $st
        threshold_warning  = $d.warn
        threshold_critical = $d.crit
        message            = "$($d.label): $($d.value)$($d.unit) -> $st"
    }
}
$overall = @('OK', 'WARNING', 'CRITICAL')[$overallRank]

$report = [ordered]@{
    hostname       = $rows[0].host
    collected_at   = $rows[0].timestamp
    generated_at   = (Get-Date).ToString('o')
    overall_status = $overall
    metrics        = $metrics
    raw            = [ordered]@{
        cpu_usage     = $m['cpu_usage']
        mem_total     = $m['mem_total']
        mem_used      = $m['mem_used']
        mem_available = $m['mem_available']
        mem_used_pct  = $m['mem_used_pct']
        disk_total    = $m['disk_total']
        disk_used     = $m['disk_used']
        disk_available = $m['disk_available']
        disk_used_pct = $m['disk_used_pct']
    }
}

$report | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputJson -Encoding UTF8
Write-Host "[Fase 2] Reporte JSON generado -> $OutputJson (estado general: $overall)"
