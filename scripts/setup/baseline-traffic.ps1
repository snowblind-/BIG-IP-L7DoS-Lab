# baseline-traffic.ps1
#
# Windows-native baseline HTTP traffic generator for BADoS learning, for hosts
# that can't run the bash baseline-traffic.sh (e.g. the Windows client).
#
# Run from win-client (10.1.10.4) so the XFF traffic-shaping iRule tags it as a
# "good" source. Pre-stage this file at C:\lab\ and run:
#
#   powershell -ExecutionPolicy Bypass -File C:\lab\baseline-traffic.ps1 `
#       -Target http://10.1.10.63/ -DurationSec 600
#
param(
    [string]$Target      = "http://10.1.10.63/",
    [int]   $DurationSec = 600,   # default 10 minutes
    [int]   $Rps         = 20
)

$uris = @("/", "/index.html", "/about", "/products", "/api/status",
          "/images/logo.png", "/css/main.css")
$base = $Target.TrimEnd('/')
$end  = (Get-Date).AddSeconds($DurationSec)
$count = 0

Write-Host "Baseline traffic to $base for ${DurationSec}s (~${Rps} req/s). Ctrl+C to stop."
while ((Get-Date) -lt $end) {
    $uri = $base + ($uris | Get-Random)
    try {
        Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 5 -Method GET | Out-Null
    } catch { }   # ignore per-request errors; keep the baseline flowing
    $count++
    Start-Sleep -Milliseconds ([int](1000 / [Math]::Max($Rps,1)))
}
Write-Host "Baseline complete. $count requests sent."
