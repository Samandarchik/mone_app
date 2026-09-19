# =====================================================================
#  github_webhook_listener.ps1
#  GitHub webhook (push) qabul qiladi va telegram_build_bot.ps1 uchun
#  navbatga "trigger" fayl yozadi. Build'ni O'ZI ISHGA TUSHIRMAYDI -
#  GitHub javobni 10 soniyada kutadi, build esa daqiqalab ketadi. Bot
#  navbatni o'qib, o'zining Invoke-Build'ini chaqiradi (git pull ->
#  versiya tekshiruvi -> bir xil bo'lsa to'xtaydi, yangi bo'lsa build).
#
#  Xavfsizlik:
#   - faqat POST /github ; boshqa hammasi 404
#   - X-Hub-Signature-256 (HMAC-SHA256, secret) - vaqt bo'yicha doimiy
#     solishtirish; imzosiz/xato imzo -> 401
#   - faqat GitHub webhook IP oraliqlaridan (pastdagi $GitHubNets)
#   - body 2 MB dan katta bo'lsa -> 413
#   - payload'dagi hech bir qiymat buyruq qatoriga tushmaydi: repo nomi
#     faqat $RepoMap oq ro'yxatidan loyiha nomini topish uchun ishlatiladi,
#     trigger fayl nomi ham shu oq ro'yxatdan olinadi
#
#  Sozlash: yonidagi  .github_webhook.config.txt  (git ga tushmaydi):
#     1-qator: webhook secret (GitHub'dagi "Secret" bilan bir xil)
#     2-qator: port (bo'sh bo'lsa 9010)
#  HttpListener "http://+:port/" uchun administrator huquqi kerak.
# =====================================================================

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Dir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$QueueDir = Join-Path $Dir '.webhook_queue'
$LogPath  = Join-Path $Dir '.github_webhook.log'
$MaxBody  = 2MB

# --- GitHub repo (owner/name, kichik harfda) -> botdagi loyiha nomi ($Projects kaliti) ---
$RepoMap = @{
    'samandarchik/mone_app'           = 'uz_ai_dev'
    'samandarchik/workly_app'         = 'workly_app'
    'samandarchik/timekivi_app'       = 'timekivi_app'
    'samandarchik/qilinadigan_ishlar' = 'qilinadigan_ishlar'
    'samandarchik/pos_flutter'        = 'pos_flutter'
    'samandarchik/mone-taxi-mobile'   = 'taxi'
    'samandarchik/web_end_bot_app_hr' = 'hr_mobile_app'
}

# --- GitHub webhook manba IP'lari (https://api.github.com/meta -> "hooks", IPv4) ---
# GitHub buni o'zgartirsa, logda "IP rad etildi" chiqadi - ro'yxatni yangilang.
$GitHubNets = @('192.30.252.0/22', '185.199.108.0/22', '140.82.112.0/20', '143.55.64.0/20')

# --- Config ---
$CfgPath = Join-Path $Dir '.github_webhook.config.txt'
if (-not (Test-Path $CfgPath)) { Write-Host "[XATO] Config topilmadi: $CfgPath" -ForegroundColor Red; exit 1 }
$cfg    = @(Get-Content $CfgPath -Encoding UTF8)
$Secret = ([string]$cfg[0]).Trim()
$Port   = 9010
if ($cfg.Count -ge 2 -and ([string]$cfg[1]).Trim() -match '^\d+$') { $Port = [int]([string]$cfg[1]).Trim() }
if ($Secret.Length -lt 32) { Write-Host "[XATO] Secret juda qisqa (kamida 32 belgi)." -ForegroundColor Red; exit 1 }
$SecretBytes = [Text.Encoding]::UTF8.GetBytes($Secret)

if (-not (Test-Path $QueueDir)) { New-Item -ItemType Directory -Path $QueueDir | Out-Null }

function Write-Log([string]$Text) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text
    Write-Host $line
    try {
        if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 5MB) { Move-Item $LogPath "$LogPath.old" -Force }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    } catch { }
}

function Test-InNets([string]$Ip) {
    $addr = $null
    if (-not [Net.IPAddress]::TryParse($Ip, [ref]$addr)) { return $false }
    if ($addr.IsIPv4MappedToIPv6) { $addr = $addr.MapToIPv4() }
    if ($addr.AddressFamily -ne 'InterNetwork') { return $false }
    $b = $addr.GetAddressBytes(); [Array]::Reverse($b); $n = [BitConverter]::ToUInt32($b, 0)
    foreach ($net in $GitHubNets) {
        $p = $net -split '/'
        $nb = ([Net.IPAddress]::Parse($p[0])).GetAddressBytes(); [Array]::Reverse($nb)
        $base = [BitConverter]::ToUInt32($nb, 0)
        $mask = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - [int]$p[1]))
        if (($n -band $mask) -eq ($base -band $mask)) { return $true }
    }
    return $false
}

# Vaqt bo'yicha doimiy solishtirish (imzoni belgima-belgi taxmin qilishga qarshi)
function Test-EqualConstTime([string]$A, [string]$B) {
    if ($A.Length -ne $B.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $diff = $diff -bor ([int]$A[$i] -bxor [int]$B[$i]) }
    return ($diff -eq 0)
}

function Send-Reply($Ctx, [int]$Code, [string]$Text) {
    try {
        $Ctx.Response.StatusCode = $Code
        $Ctx.Response.ContentType = 'text/plain'
        $buf = [Text.Encoding]::UTF8.GetBytes($Text)
        $Ctx.Response.ContentLength64 = $buf.Length
        $Ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
    } catch { }
    try { $Ctx.Response.Close() } catch { }
}

function Invoke-Request($Ctx) {
    $req = $Ctx.Request
    $ip  = $req.RemoteEndPoint.Address.ToString()

    if ($req.HttpMethod -ne 'POST' -or $req.Url.AbsolutePath.TrimEnd('/') -ne '/github') {
        Send-Reply $Ctx 404 ''; return
    }
    if (-not (Test-InNets $ip)) {
        Write-Log "IP rad etildi: $ip"
        Send-Reply $Ctx 403 ''; return
    }
    if ($req.ContentLength64 -le 0 -or $req.ContentLength64 -gt $MaxBody) {
        Write-Log "body hajmi yaroqsiz ($($req.ContentLength64)) - $ip"
        Send-Reply $Ctx 413 ''; return
    }

    # Body'ni xom baytlarda o'qiymiz (HMAC aynan shu baytlar ustidan)
    $len = [int]$req.ContentLength64
    $body = New-Object byte[] $len
    $read = 0
    while ($read -lt $len) {
        $n = $req.InputStream.Read($body, $read, $len - $read)
        if ($n -le 0) { break }
        $read += $n
    }
    if ($read -ne $len) { Send-Reply $Ctx 400 ''; return }

    $sig = [string]$req.Headers['X-Hub-Signature-256']
    $hmac = New-Object Security.Cryptography.HMACSHA256 (, $SecretBytes)
    try { $hex = -join ($hmac.ComputeHash($body) | ForEach-Object { $_.ToString('x2') }) } finally { $hmac.Dispose() }
    if (-not $sig -or -not (Test-EqualConstTime $sig.ToLower() "sha256=$hex")) {
        Write-Log "IMZO XATO - $ip"
        Send-Reply $Ctx 401 ''; return
    }

    $ghEvent = [string]$req.Headers['X-GitHub-Event']
    if ($ghEvent -eq 'ping') { Write-Log "ping OK - $ip"; Send-Reply $Ctx 200 'pong'; return }
    if ($ghEvent -ne 'push') { Send-Reply $Ctx 200 'ignored: event'; return }

    try { $j = [Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json }
    catch { Send-Reply $Ctx 400 ''; return }

    $repo = ([string]$j.repository.full_name).ToLower()
    if (-not $RepoMap.ContainsKey($repo)) {
        Write-Log "noma'lum repo (imzo to'g'ri): $repo"
        Send-Reply $Ctx 200 'ignored: repo'; return
    }
    $name = $RepoMap[$repo]
    $want = 'refs/heads/' + [string]$j.repository.default_branch
    if ([string]$j.ref -ne $want -or $j.deleted) {
        Send-Reply $Ctx 200 'ignored: branch'; return
    }

    # Navbat: loyiha boshiga bitta fayl (ketma-ket push'lar bitta build'ga birlashadi)
    $sha = ([string]$j.after) -replace '[^0-9a-fA-F]', ''
    $trigger = Join-Path $QueueDir "$name.trigger"
    Set-Content -Path $trigger -Value ("{0} {1}" -f (Get-Date -Format 's'), $sha) -Encoding ASCII
    Write-Log "push: $repo -> [$name] navbatga qo'yildi ($sha)"
    Send-Reply $Ctx 202 "queued: $name"
}

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://+:$Port/github/")
$listener.Start()
# Sekin/osilib qolgan ulanishlar listener'ni band qilmasin
$listener.TimeoutManager.HeaderWait       = [TimeSpan]::FromSeconds(10)
$listener.TimeoutManager.EntityBody       = [TimeSpan]::FromSeconds(15)
$listener.TimeoutManager.IdleConnection   = [TimeSpan]::FromSeconds(15)
Write-Log "GitHub webhook listener ishga tushdi: port $Port, yo'l /github"

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try { Invoke-Request $ctx }
        catch {
            Write-Log "so'rov xatosi: $($_.Exception.Message)"
            try { $ctx.Response.Abort() } catch { }
        }
    }
} finally {
    try { $listener.Stop() } catch { }
}
