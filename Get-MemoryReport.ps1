$reportPath = "d:\Project\windows-optimizer-script\Memory_Usage_Report.txt"
$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$out = @()
$out += "========================================================================"
$out += "                 FULL SYSTEM MEMORY REPORT"
$out += "                 Generated: $date"
$out += "========================================================================`n"

$os = Get-CimInstance Win32_OperatingSystem
$totalRam = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeRam = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$usedRam = $totalRam - $freeRam

$out += "--- SYSTEM OVERVIEW ---"
$out += "Total Physical RAM: $totalRam GB"
$out += "Used Physical RAM:  $usedRam GB"
$out += "Free Physical RAM:  $freeRam GB`n"

$out += "--- PROCESSES BY RAM USAGE ---"
$out += "Below is the list of all running tasks and apps consuming memory.`n"

$out | Set-Content -Path $reportPath -Encoding UTF8

Get-Process | Sort-Object WorkingSet -Descending | Select-Object `
    @{Name="Process Name";Expression={$_.Name}}, `
    @{Name="PID";Expression={$_.Id}}, `
    @{Name="RAM (MB)";Expression={"{0:N2}" -f ($_.WorkingSet / 1MB)}}, `
    @{Name="Page File (MB)";Expression={"{0:N2}" -f ($_.PagedMemorySize / 1MB)}}, `
    @{Name="Company / Description";Expression={$_.Description}} | `
    Format-Table -AutoSize | Out-String -Stream | Out-File -FilePath $reportPath -Append -Encoding UTF8

Write-Host "Memory usage report successfully generated at: $reportPath"
