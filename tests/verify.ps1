#requires -Version 5.1
<#
.SYNOPSIS
    Verifikasi end-to-end API Gateway (OpenResty) + service API.
.DESCRIPTION
    Menjalankan matriks uji: health, auth JWT, authorization role, validasi request,
    load balancing, rate limiter, dan circuit breaker/failover.
    Prasyarat: stack berjalan (docker compose up -d) dan Docker CLI tersedia.
.EXAMPLE
    pwsh -File tests/verify.ps1
    pwsh -File tests/verify.ps1 -BaseUrl http://localhost:8080 -SkipChaos
#>
param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$AdminUser = "admin",
    [string]$AdminPass = "admin123",
    [string]$ViewerUser = "viewer",
    [string]$ViewerPass = "viewer123",
    [int]$Burst = 300,
    [switch]$SkipChaos
)

$ErrorActionPreference = "Stop"

$script:Pass = 0
$script:Fail = 0

function Write-Pass([string]$Name) {
    $script:Pass++
    Write-Host ("[PASS] " + $Name) -ForegroundColor Green
}

function Write-Fail([string]$Name, [string]$Detail) {
    $script:Fail++
    Write-Host ("[FAIL] " + $Name + " -> " + $Detail) -ForegroundColor Red
}

function Test-Check([string]$Name, [bool]$Condition, [string]$Detail) {
    if ($Condition) { Write-Pass $Name } else { Write-Fail $Name $Detail }
}

function Invoke-Check {
    param(
        [string]$Method = "GET",
        [string]$Path,
        [hashtable]$Headers,
        [string]$Body,
        [string]$ContentType
    )
    $params = @{
        Method           = $Method
        Uri              = ($BaseUrl + $Path)
        UseBasicParsing  = $true
        TimeoutSec       = 10
    }
    if ($Headers) { $params.Headers = $Headers }
    if ($PSBoundParameters.ContainsKey("Body")) { $params.Body = $Body }
    if ($ContentType) { $params.ContentType = $ContentType }

    try {
        $r = Invoke-WebRequest @params
        return [pscustomobject]@{ Code = [int]$r.StatusCode; Body = $r.Content; Upstream = $r.Headers["X-Upstream-Addr"] }
    }
    catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            return [pscustomobject]@{ Code = [int]$resp.StatusCode; Body = $reader.ReadToEnd(); Upstream = $resp.Headers["X-Upstream-Addr"] }
        }
        return [pscustomobject]@{ Code = -1; Body = $_.Exception.Message; Upstream = $null }
    }
}

function Get-Token([string]$User, [string]$Pass) {
    $r = Invoke-Check -Method POST -Path "/auth/login" -Body "username=$User&password=$Pass" -ContentType "application/x-www-form-urlencoded"
    if ($r.Code -ne 200) { throw "login '$User' gagal ($($r.Code)): $($r.Body)" }
    return ($r.Body | ConvertFrom-Json).access_token
}

function Auth([string]$Token) { return @{ Authorization = "Bearer $Token" } }

function Invoke-Burst([string]$Path, [int]$Count) {
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    [System.Net.ServicePointManager]::DefaultConnectionLimit = [Math]::Max(100, $Count)
    [System.Net.ServicePointManager]::Expect100Continue = $false
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(30)

    $tasks = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task[System.Net.Http.HttpResponseMessage]]
    for ($i = 0; $i -lt $Count; $i++) { $tasks.Add($client.GetAsync($BaseUrl + $Path)) }

    $codes = @{}
    foreach ($t in $tasks) {
        $code = -1
        try { $code = [int]$t.Result.StatusCode } catch { $code = -1 }
        $codes[$code] = ([int]$codes[$code]) + 1
    }
    $client.Dispose()
    return $codes
}

function Get-ApiContainers {
    $names = docker ps --filter "name=load-balance-dabd-api-" --format "{{.Names}}" 2>$null
    return @($names | Where-Object { $_ })
}

function Get-ContainerAddr([string]$Name) {
    $ip = (docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" $Name 2>$null | Select-Object -First 1)
    if (-not $ip) { return $null }
    return "$ip`:8000"
}

function Get-GatewayStatus([string]$Token) {
    $r = Invoke-Check -Path "/_gateway/status" -Headers (Auth $Token)
    if ($r.Code -ne 200) { throw "status endpoint gagal ($($r.Code)): $($r.Body)" }
    return ($r.Body | ConvertFrom-Json)
}

Write-Host "== Verifikasi gateway: $BaseUrl ==" -ForegroundColor Cyan
Write-Host ""

Write-Host "-- Prasyarat & health --"
$health = Invoke-Check -Path "/_gateway/health"
Test-Check "gateway health 200" ($health.Code -eq 200) "code=$($health.Code)"

try {
    $admin = Get-Token $AdminUser $AdminPass
    Test-Check "login admin mendapat token" ([bool]$admin) "token kosong"
}
catch {
    Write-Fail "login admin" $_.Exception.Message
    Write-Host "Tidak bisa lanjut tanpa token admin." -ForegroundColor Red
    exit 1
}

$viewer = $null
try { $viewer = Get-Token $ViewerUser $ViewerPass; Test-Check "login viewer mendapat token" ([bool]$viewer) "token kosong" }
catch { Write-Fail "login viewer" $_.Exception.Message }

Write-Host ""
Write-Host "-- Authentication --"
$r = Invoke-Check -Path "/menu"
Test-Check "GET /menu tanpa token -> 401" ($r.Code -eq 401) "code=$($r.Code)"

$r = Invoke-Check -Path "/menu" -Headers (Auth "not-a-valid-token")
Test-Check "GET /menu token invalid -> 401" ($r.Code -eq 401) "code=$($r.Code)"

$r = Invoke-Check -Path "/menu" -Headers (Auth $admin)
Test-Check "GET /menu admin -> 200" ($r.Code -eq 200) "code=$($r.Code)"

if ($viewer) {
    $r = Invoke-Check -Path "/menu" -Headers (Auth $viewer)
    Test-Check "GET /menu viewer -> 200" ($r.Code -eq 200) "code=$($r.Code)"
}

Write-Host ""
Write-Host "-- Authorization --"
if ($viewer) {
    $r = Invoke-Check -Method POST -Path "/menu" -Headers (Auth $viewer) -ContentType "application/json" -Body '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":10}'
    Test-Check "POST /menu viewer -> 403" ($r.Code -eq 403) "code=$($r.Code) body=$($r.Body)"
}

$r = Invoke-Check -Path "/_gateway/status" -Headers (Auth $viewer)
Test-Check "GET /_gateway/status viewer -> 403" ($r.Code -eq 403) "code=$($r.Code)"

Write-Host ""
Write-Host "-- Request validation (POST /menu, admin) --"
$valid = '{"id_stand":1,"id_kategori":1,"nama_menu":"Soto Uji","harga":15000,"status":"tersedia"}'
$r = Invoke-Check -Method POST -Path "/menu" -Headers (Auth $admin) -ContentType "application/json" -Body $valid
Test-Check "POST /menu valid -> 201" ($r.Code -eq 201) "code=$($r.Code) body=$($r.Body)"

$cases = @(
    @{ Name = "harga <= 0";          Body = '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":0}' },
    @{ Name = "field asing";         Body = '{"id_stand":1,"id_kategori":1,"nama_menu":"X","harga":10,"foo":1}' },
    @{ Name = "field wajib kurang";  Body = '{"id_kategori":1,"nama_menu":"X","harga":10}' },
    @{ Name = "JSON rusak";          Body = '{not-json' }
)
foreach ($c in $cases) {
    $r = Invoke-Check -Method POST -Path "/menu" -Headers (Auth $admin) -ContentType "application/json" -Body $c.Body
    Test-Check ("POST /menu " + $c.Name + " -> 400") ($r.Code -eq 400) "code=$($r.Code) body=$($r.Body)"
}

Write-Host ""
Write-Host "-- Load balancing --"
$addrs = @()
for ($i = 0; $i -lt 6; $i++) {
    $r = Invoke-Check -Path "/menu" -Headers (Auth $admin)
    if ($r.Upstream) { $addrs += [string]$r.Upstream }
}
$distinct = @($addrs | Sort-Object -Unique)
Write-Host ("    upstream terlihat: " + ($distinct -join ", "))
Test-Check "round-robin menyentuh >= 2 replica" ($distinct.Count -ge 2) "distinct=$($distinct.Count)"

Write-Host ""
Write-Host "-- Service discovery / status --"
$status = Get-GatewayStatus $admin
Test-Check "status endpoint 200 + node_count >= 1" ($status.node_count -ge 1) "node_count=$($status.node_count)"

Write-Host ""
Write-Host "-- Rate limiter (burst paralel $Burst ke /) --"
$codes = Invoke-Burst "/" $Burst
$summary = ($codes.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "
Write-Host ("    hasil: " + $summary)
Test-Check "burst memicu 429" ([int]$codes[429] -gt 0) "tidak ada 429"

if ($SkipChaos) {
    Write-Host ""
    Write-Host "-- Circuit breaker / failover: DILEWATI (-SkipChaos) --" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "-- Circuit breaker / failover --"
    $apis = Get-ApiContainers
    Test-Check ">= 2 replica API berjalan" ($apis.Count -ge 2) "ditemukan=$($apis.Count)"

    if ($apis.Count -ge 2) {
        $victim = $apis[0]
        $victimAddr = Get-ContainerAddr $victim
        Write-Host ("    menghentikan replica: $victim ($victimAddr)")
        try {
            docker stop $victim | Out-Null
            Start-Sleep -Seconds 1

            $ok = 0; $err = 0
            for ($i = 0; $i -lt 15; $i++) {
                $r = Invoke-Check -Path "/menu" -Headers (Auth $admin)
                if ($r.Code -eq 200) { $ok++ } else { $err++ }
                Start-Sleep -Milliseconds 300
            }
            Test-Check "failover: mayoritas request tetap 200" ($ok -ge 10) "ok=$ok err=$err"

            $status = Get-GatewayStatus $admin
            $open = @($status.upstream_nodes | Where-Object { $_.circuit -eq "open" })
            $stillListed = @($status.upstream_nodes | Where-Object { $_.addr -eq $victimAddr }).Count -gt 0
            Write-Host ("    node terbuka: " + (@($open | ForEach-Object { $_.addr }) -join ", "))
            Test-Check "circuit breaker OPEN atau node di-deregister" (($open.Count -ge 1) -or (-not $stillListed)) "open=$($open.Count) listed=$stillListed"
        }
        finally {
            docker start $victim | Out-Null
            Write-Host "    menyalakan ulang $victim, menunggu pemulihan (~12s)..."
            Start-Sleep -Seconds 12
            for ($i = 0; $i -lt 6; $i++) { Invoke-Check -Path "/menu" -Headers (Auth $admin) | Out-Null; Start-Sleep -Milliseconds 300 }
            $status = Get-GatewayStatus $admin
            $open = @($status.upstream_nodes | Where-Object { $_.circuit -eq "open" })
            Test-Check "pemulihan: semua node CLOSED" ($open.Count -eq 0) "masih open=$($open.Count)"
        }
    }
}

Write-Host ""
Write-Host "== Ringkasan: $($script:Pass) PASS, $($script:Fail) FAIL ==" -ForegroundColor Cyan
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
