# =====================================================================
#  telegram_build_bot.ps1  (ko'p loyihali)
#  Bu mashinada doim ishlab turadigan Telegram bot (long polling).
#  Botga "build" deb yozsangiz -> loyihalar ro'yxati (tugmalar) chiqadi.
#  Tugmani bossangiz: git pull + build_windows.bat ishga tushadi va
#  progress (qabul qilindi -> build -> zip -> github -> tayyor) bitta
#  xabar ichida yangilanib boradi. Public IP KERAK EMAS.
#
#  VERSIYA TEKSHIRUVI: build'dan oldin bot git pull qiladi va
#  pubspec.yaml dagi versiyani oxirgi muvaffaqiyatli build versiyasi bilan
#  solishtiradi (.telegram_bot_state.json). Bir xil bo'lsa build BEKOR
#  qilinadi va eski release havolasi qaytariladi ("Baribir build qilish"
#  tugmasi bilan majburlash mumkin). Yangi build chiqsa - GitHub Releases
#  havolasi xabarga qo'shiladi.
#
#  AUTO UPDATE (GitHub polling): bot har $PollSec soniyada GitHub API'dan
#  har bir loyihaning default branch'idagi oxirgi commit sha'sini so'raydi.
#  Sha o'zgargan bo'lsa (= kimdir push qildi) -> Invoke-Build -Auto:
#  git pull -> versiya tekshiruvi -> versiya yangi bo'lsa build + release.
#  Nega webhook emas: bu kompyuter NAT ortida (192.168.x.x), GitHub
#  webhook'i unga yetib kela olmaydi. Polling uchun public IP/port shart emas.
#  Token: %USERPROFILE%\.github_release_token (publish_release.ps1 bilan bir xil).
#  github_webhook_listener.ps1 navbati (.webhook_queue) ham ishlayveradi.
#
#  Sozlash: yonidagi  .telegram_bot.config.txt :
#     1-qator: bot token
#     2-qator: ruxsat berilgan chat ID (vergul bilan; birinchisi = admin,
#              auto update xabarlari unga boradi)
#  Loyihalarni pastdagi $Projects va $Repos ro'yxatiga qo'shing/olib tashlang.
#  Log: yonidagi .telegram_bot.log
# =====================================================================

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Dir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Desktop = Join-Path $env:USERPROFILE 'Desktop'

# --- Loyihalar: nom -> papka (build_windows.bat shu papkada bo'lishi kerak) ---
$Projects = [ordered]@{
    'uz_ai_dev'          = (Join-Path $Desktop 'uz_ai_dev')
    'workly_app'         = (Join-Path $Desktop 'workly_app')
    'timekivi_app'       = (Join-Path $env:USERPROFILE 'timekivi_app')
    'qilinadigan_ishlar' = (Join-Path $Desktop 'qilinadigan_ishlar')
    'pos_flutter'        = 'C:\pos_flutter'
    'taxi'               = (Join-Path $Desktop 'mone-taxi-mobile')
    # Flutter loyihasi repo ichidagi papkada: web_end_bot_app_hr\hr_mobile_app
    'hr_mobile_app'      = (Join-Path $Desktop 'web_end_bot_app_hr\hr_mobile_app')
}

# --- Loyiha -> GitHub repo (owner/name). Auto update shu ro'yxatni kuzatadi. ---
$Repos = [ordered]@{
    'uz_ai_dev'          = 'Samandarchik/mone_app'
    'workly_app'         = 'Samandarchik/workly_app'
    'timekivi_app'       = 'Samandarchik/timekivi_app'
    'qilinadigan_ishlar' = 'Samandarchik/qilinadigan_ishlar'
    'pos_flutter'        = 'Samandarchik/pos_flutter'
    'taxi'               = 'Samandarchik/mone-taxi-mobile'
    'hr_mobile_app'      = 'Samandarchik/web_end_bot_app_hr'
}
$PollSec       = 60                                   # GitHub'ni tekshirish oralig'i (soniya)
$PollStatePath = Join-Path $Dir '.github_poll_state.json'
$GhTokenFile   = Join-Path $env:USERPROFILE '.github_release_token'

# --- Log fayl (konsol yopiq bo'lsa ham nima bo'lganini ko'rish uchun) ---
$LogPath = Join-Path $Dir '.telegram_bot.log'
function Write-Log([string]$Text, [string]$Color = 'Gray') {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text
    Write-Host $line -ForegroundColor $Color
    try {
        if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 5MB) { Move-Item $LogPath "$LogPath.old" -Force }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    } catch { }
}

# --- Config (token + chat id) ---
$CfgPath = Join-Path $Dir '.telegram_bot.config.txt'
if (-not (Test-Path $CfgPath)) {
    Write-Host "[XATO] Config topilmadi: $CfgPath" -ForegroundColor Red
    Read-Host "Chiqish uchun Enter"; exit 1
}
$cfg      = Get-Content $CfgPath -Encoding UTF8
$Token    = ($cfg | Select-Object -First 1).Trim()
$AllowedRaw = ''
if ($cfg.Count -ge 2) { $AllowedRaw = ($cfg[1]).Trim() }
$Allowed  = @($AllowedRaw -split '[,; ]+' | Where-Object { $_ -ne '' })
if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Host "[XATO] Token bo'sh." -ForegroundColor Red; Read-Host "Enter"; exit 1
}

$Api = "https://api.telegram.org/bot$Token"
$env:UZ_BOT = '1'   # build_windows.bat "pause" qilmasligi uchun

# --- Telegram yordamchilari ---
function Send-Msg([string]$ChatId, [string]$Text, $Markup=$null) {
    $b = @{ chat_id = $ChatId; text = $Text; disable_web_page_preview = 'true' }
    if ($Markup) { $b.reply_markup = $Markup }
    try { return Invoke-RestMethod -Uri "$Api/sendMessage" -Method Post -TimeoutSec 30 -Body $b }
    catch { Write-Log "[ogoh] send: $($_.Exception.Message)" 'DarkYellow'; return $null }
}
function Edit-Msg([string]$ChatId, [string]$MsgId, [string]$Text) {
    try { Invoke-RestMethod -Uri "$Api/editMessageText" -Method Post -TimeoutSec 30 -Body @{
        chat_id = $ChatId; message_id = $MsgId; text = $Text; disable_web_page_preview = 'true' } | Out-Null
    } catch { }
}
function Answer-Cb([string]$CbId) {
    try { Invoke-RestMethod -Uri "$Api/answerCallbackQuery" -Method Post -TimeoutSec 15 -Body @{ callback_query_id = $CbId } | Out-Null } catch { }
}

# =====================================================================
#  Versiya holati: oxirgi muvaffaqiyatli build (loyiha -> versiya + link)
#  Fayl:  .telegram_bot_state.json  (git ga tushmaydi)
# =====================================================================
$StatePath = Join-Path $Dir '.telegram_bot_state.json'

function Get-State {
    $h = @{}
    if (Test-Path $StatePath) {
        try {
            $o = Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) {
                $h[$p.Name] = @{
                    version = [string]$p.Value.version
                    url     = [string]$p.Value.url
                    at      = [string]$p.Value.at
                }
            }
        } catch { }
    }
    return $h
}

function Get-LastBuild([string]$Name) {
    $s = Get-State
    if ($s.ContainsKey($Name)) { return $s[$Name] }
    return @{ version = ''; url = ''; at = '' }
}

function Set-LastBuild([string]$Name, [string]$Version, [string]$Url) {
    $s = Get-State
    $s[$Name] = @{
        version = $Version
        url     = $Url
        at      = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    }
    try { ($s | ConvertTo-Json -Depth 5) | Set-Content $StatePath -Encoding UTF8 }
    catch { Write-Log "[ogoh] state saqlanmadi: $($_.Exception.Message)" 'DarkYellow' }
}

# pubspec.yaml -> "0.5.7+57" (build raqami bilan). pubspec yo'q bo'lsa -> git commit.
function Get-ProjectVersion([string]$Path) {
    $pub = Join-Path $Path 'pubspec.yaml'
    if (Test-Path $pub) {
        try {
            foreach ($line in (Get-Content $pub -Encoding UTF8)) {
                if ($line -match '^\s*version:\s*(\S+)') { return $Matches[1].Trim() }
            }
        } catch { }
    }
    try {
        $sha = (& git -C $Path rev-parse --short HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $sha) { return "git:$(([string]$sha).Trim())" }
    } catch { }
    return ''
}

# Build'dan oldin kodni yangilash. Qaytaradi: $true = pull o'tdi.
# MUHIM: 3 daqiqa timeout bilan. GitHub'dan pack yuklab olish tarmoq sabab
# o'rtasida qotib qolsa git o'zi hech qachon uzmaydi, bot esa sinxron kutgani
# uchun BUTUN bot "versiya tekshirilmoqda..." da abadiy bloklanib qolardi.
# Endi jarayon daraxti o'ldiriladi va $false qaytadi (build eski kod bilan
# davom etadi yoki versiya bir xil bo'lsa bekor qilinadi).
function Invoke-GitPull([string]$Path) {
    $script:LastPullOut = ''
    $ok = Invoke-GitPullOnce $Path
    if ($ok) { return $true }

    # --- Avto-tuzatish: "local changes would be overwritten by merge" ---
    # Flutter generated fayllarni (GeneratedPluginRegistrant.swift va h.k.) LF
    # bilan qayta yozadi; autocrlf=true da git ularni "o'zgargan" deb ko'radi,
    # mazmun esa HEAD bilan bir xil. Bunday fayl pull'ni butunlay to'sib qo'yardi.
    # FAQAT mazmuni HEAD bilan bir xil (git diff --quiet = 0) fayllar tiklanadi -
    # haqiqiy lokal o'zgarishga TEGILMAYDI (u holda pull XATO bo'lib qoladi).
    $m = [regex]::Match($script:LastPullOut, '(?s)would be overwritten by merge:\s*\r?\n(.*?)\r?\nPlease commit')
    if (-not $m.Success) { return $false }
    $files = @($m.Groups[1].Value -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($files.Count -eq 0) { return $false }
    # MUHIM: git cmd orqali chaqiriladi va stderr cmd'ning o'zida yutiladi.
    # PS 5.1 da ErrorActionPreference='Stop' + "2>$null" bo'lsa git'ning oddiy
    # "LF will be replaced by CRLF" ogohlantirishi ham istisnoga aylanadi.
    foreach ($f in $files) {
        & $env:ComSpec /c "git -C `"$Path`" diff --quiet -- `"$f`" >nul 2>nul"
        if ($LASTEXITCODE -ne 0) {
            Write-Log "    git pull: '$f' da HAQIQIY lokal o'zgarish bor - avto-tuzatilmaydi." 'DarkYellow'
            return $false
        }
    }
    foreach ($f in $files) {
        & $env:ComSpec /c "git -C `"$Path`" checkout -- `"$f`" >nul 2>nul"
        Write-Log "    git pull: '$f' faqat qator-oxiri farqi edi - tiklandi (kod $LASTEXITCODE)." 'DarkGray'
    }
    return (Invoke-GitPullOnce $Path)
}

function Invoke-GitPullOnce([string]$Path) {
    $outLog = Join-Path $env:TEMP 'uzbot_gitpull.out.log'
    $errLog = Join-Path $env:TEMP 'uzbot_gitpull.err.log'
    try {
        $p = Start-Process -FilePath 'git' `
            -ArgumentList '-C', "`"$Path`"", 'pull' `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog
        # PS 5.1 tuzog'i: Handle o'qilmasa va WaitForExit(ms) dan keyin
        # WaitForExit() chaqirilmasa $p.ExitCode $null bo'lib qoladi -
        # "Already up to date" bo'lsa ham pull XATO deb hisoblanardi.
        $null = $p.Handle
        if (-not $p.WaitForExit(180000)) {
            & taskkill /T /F /PID $p.Id 2>$null | Out-Null
            Write-Log "[ogoh] git pull 3 daqiqada tugamadi - to'xtatildi (tarmoq qotgan?)" 'DarkYellow'
            return $false
        }
        $p.WaitForExit()
        $code = $p.ExitCode
        $out = ''
        foreach ($f in @($outLog, $errLog)) {
            try { if (Test-Path $f) { $out += (Get-Content $f -Raw -Encoding UTF8) } } catch { }
        }
        $script:LastPullOut = $out
        Write-Log "    git pull (kod $code): $($out.Trim())" 'DarkGray'
        return ($code -eq 0)
    } catch {
        Write-Log "[ogoh] git pull: $($_.Exception.Message)" 'DarkYellow'
        return $false
    }
}

# Build logidan GitHub release havolasini ajratib olish
function Get-ReleaseUrl([string]$LogText) {
    if (-not $LogText) { return '' }
    $m = [regex]::Match($LogText, 'https://github\.com/[^\s''"]+/releases/tag/[^\s''"]+')
    if ($m.Success) { return $m.Value.TrimEnd('.', ',') }
    return ''
}

# --- Loyihalar menyusi (inline tugmalar) ---
function Show-Menu([string]$ChatId) {
    $btns = @()
    foreach ($k in $Projects.Keys) {
        $btns += , (@(@{ text = $k; callback_data = "b:$k" }))
    }
    # SH5 qoldiqlarini qo'lda yangilash (rk7_bridge sh5-remains) - test rejimi,
    # daemon yo'q: faqat tugma bosilganda yangilanadi.
    $btns += , (@(@{ text = "Ostatka yangilash (SH5)"; callback_data = "sh5:refresh" }))
    $markup = (@{ inline_keyboard = $btns } | ConvertTo-Json -Depth 6 -Compress)
    Send-Msg $ChatId "Qaysi loyihani build qilamiz? Tugmani bosing:" $markup | Out-Null
}

# --- SH5 qoldiqlarini yangilash (rk7_bridge sh5-remains) ---
# SH5 (StoreHouse) dan qoldiqlarni o'qib Mone'ga push qiladi - ilovadagi
# "Ostatka (SH5)" ekrani yangi raqamlarni ko'radi. Bridge config'i o'z
# papkasidan o'qiladi, shuning uchun Push-Location shart.
$Sh5BridgeDir = 'C:\112233\rk7_bridge'

function Invoke-Sh5Refresh([string]$ChatId) {
    $r = Send-Msg $ChatId "Ostatka yangilanmoqda (SH5 -> Mone)..."
    $mid = $null
    if ($r -and $r.result) { $mid = [string]$r.result.message_id }

    $exe = Join-Path $Sh5BridgeDir 'rk7bridge.exe'
    if (-not (Test-Path $exe)) {
        $txt = "XATO: rk7bridge.exe topilmadi:`n$exe"
        if ($mid) { Edit-Msg $ChatId $mid $txt } else { Send-Msg $ChatId $txt | Out-Null }
        return
    }

    $out = ''
    try {
        Push-Location $Sh5BridgeDir
        $out = ((& .\rk7bridge.exe sh5-remains 2>&1) | ForEach-Object { "$_" }) -join "`n"
        $code = $LASTEXITCODE
    } finally { Pop-Location }

    # Oxirgi qatorlar yetarli (masalan "omborlar=40 tovar satrlari=3269").
    $tail = (($out -split "`n") | Select-Object -Last 4) -join "`n"
    if ($code -eq 0) {
        $txt = "Ostatka yangilandi (SH5 -> Mone).`n$tail`nIlovada `"Ostatka (SH5)`" ni oching."
    } else {
        $txt = "Ostatka yangilash XATO (kod $code):`n$tail"
    }
    if ($mid) { Edit-Msg $ChatId $mid $txt } else { Send-Msg $ChatId $txt | Out-Null }
    Write-Log ">>> ostatka yangilash: kod=$code" 'Cyan'
}

# --- Bitta loyihani build qilish + progress ---
$Stages = @(
    @{ re = '\[0/[45]\] git pull'; msg = 'git pull - oxirgi kod olinmoqda...' },
    @{ re = '\[1/[45]\]';          msg = 'Loyiha nusxalanmoqda...' },
    @{ re = '\[2/[45]\]';          msg = 'flutter pub get...' },
    @{ re = '\[3/[45]\]';          msg = 'BUILD qilinmoqda (biroz kuting)...' },
    @{ re = '\[4/[45]\]';          msg = 'Zip yaratilmoqda...' },
    @{ re = '\[5/5\]';           msg = "GitHub Releases'ga yuborilmoqda..." }
)

# $Auto = auto update (GitHub'da yangi push topildi, hech kim tugma bosmagan):
# versiya bir xil bo'lsa faqat git pull qilinadi va Telegram'ga HECH NARSA
# yozilmaydi; versiya yangi bo'lsa odatdagi build + progress xabari ketadi.
function Invoke-Build([string]$ChatId, [string]$Name, [bool]$Force = $false, [bool]$Auto = $false) {
    $path = $Projects[$Name]
    $bat  = Join-Path $path 'build_windows.bat'
    if (-not (Test-Path $bat)) {
        Send-Msg $ChatId "XATO: $Name - build_windows.bat topilmadi:`n$bat" | Out-Null
        return
    }

    $mid = $null
    if (-not $Auto) {
        $r = Send-Msg $ChatId "[$Name]`nQabul qilindi. git pull - versiya tekshirilmoqda..."
        if ($r -and $r.result) { $mid = [string]$r.result.message_id }
    }

    # --- Avval kodni yangilaymiz, keyin versiyani solishtiramiz ---
    $pullOk = Invoke-GitPull $path
    $ver    = Get-ProjectVersion $path
    $prev   = Get-LastBuild $Name

    if ($Auto) {
        if (-not $pullOk) {
            Write-Log ">>> [$Name] auto update: git pull XATO - build qilinmaydi." 'Yellow'
            Send-Msg $ChatId "[$Name]`nGitHub'ga push keldi, lekin git pull XATO berdi (lokal o'zgarish/konflikt?). Build qilinmadi." | Out-Null
            return
        }
        if ($ver -and $prev.version -and $prev.version -eq $ver) {
            Write-Log ">>> [$Name] auto update: git pull ok, versiya bir xil ($ver) - build yo'q." 'Yellow'
            return
        }
        Write-Log ">>> [$Name] auto update: yangi versiya $ver (oldingi: $($prev.version)) - build boshlanadi." 'Cyan'
        $r = Send-Msg $ChatId "[$Name]`nGitHub push - yangi versiya: $ver (oldingi: $($prev.version))"
        if ($r -and $r.result) { $mid = [string]$r.result.message_id }
    }

    if (-not $Force -and $ver -and $prev.version -and $prev.version -eq $ver) {
        $txt = "[$Name]`nBUILD BEKOR QILINDI - versiya bir xil: $ver"
        if ($prev.at)  { $txt += "`nOxirgi build: $($prev.at)" }
        if ($prev.url) { $txt += "`nRelease: $($prev.url)" }
        else           { $txt += "`n(oxirgi release havolasi saqlanmagan)" }
        if (-not $pullOk) { $txt += "`nESLATMA: git pull xato berdi - kod yangilanmagan bo'lishi mumkin." }
        if ($mid) { Edit-Msg $ChatId $mid $txt } else { Send-Msg $ChatId $txt | Out-Null }

        $markup = (@{ inline_keyboard = @(, (@(@{ text = "Baribir build qilish"; callback_data = "f:$Name" }))) } | ConvertTo-Json -Depth 6 -Compress)
        Send-Msg $ChatId "Yangi o'zgarish yo'q. Baribir build qilaymi?" $markup | Out-Null
        Write-Log ">>> [$Name] versiya bir xil ($ver) - build bekor qilindi." 'Yellow'
        return
    }

    $hdr = "[$Name] v$ver"
    if ($Force -and $prev.version -eq $ver) { $hdr += " (majburiy)" }
    if ($mid) { Edit-Msg $ChatId $mid "$hdr`nIshga tushirilmoqda..." }

    $log = Join-Path $env:TEMP ("uzbot_" + $Name + ".log")
    if (Test-Path $log) { Remove-Item $log -Force }

    Write-Log ">>> [$Name] build boshlandi (v$ver)..." 'Cyan'
    $proc = Start-Process -FilePath $env:ComSpec `
                          -ArgumentList '/c', "`"`"$bat`" > `"$log`" 2>&1`"" `
                          -WorkingDirectory $path -WindowStyle Hidden -PassThru

    $lastIdx = -1
    while (-not $proc.HasExited) {
        Start-Sleep -Seconds 2
        $c = $null
        try { $c = Get-Content $log -Raw -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
        if ($c) {
            $idx = -1
            for ($i = 0; $i -lt $Stages.Count; $i++) { if ($c -match $Stages[$i].re) { $idx = $i } }
            if ($idx -gt $lastIdx) {
                $lastIdx = $idx
                if ($mid) { Edit-Msg $ChatId $mid "$hdr`n$($Stages[$idx].msg)" }
                Write-Host "    [$Name] $($Stages[$idx].msg)"
            }
        }
    }

    $tail = ''
    $full = ''
    if (Test-Path $log) {
        try { $tail = (Get-Content $log -Tail 20 -Encoding UTF8) -join "`n" } catch { }
        if ($tail.Length -gt 3000) { $tail = $tail.Substring($tail.Length - 3000) }
        try { $full = Get-Content $log -Raw -Encoding UTF8 } catch { }
    }
    $relUrl = Get-ReleaseUrl $full

    if ($proc.ExitCode -eq 0) {
        $done = "$hdr`nTAYYOR!"
        if ($relUrl) {
            $done += "`nRelease: $relUrl"
        } else {
            # Release chiqmadi -> versiyani "chiqarilgan" deb yozmaymiz, keyingi
            # bosishda qayta urinib ko'rsin (versiya tekshiruvi to'smasin).
            $done += "`nOGOH: GitHub Releases'ga chiqmadi (havola topilmadi) - loglarga qarang."
        }
        if ($mid) { Edit-Msg $ChatId $mid $done } else { Send-Msg $ChatId $done | Out-Null }
        if ($ver -and $relUrl) { Set-LastBuild $Name $ver $relUrl }
        if (-not $relUrl -and $tail) { Send-Msg $ChatId "Loglar:`n$tail" | Out-Null }
    } else {
        $fail = "$hdr`nBUILD XATO (kod $($proc.ExitCode))."
        if ($mid) { Edit-Msg $ChatId $mid $fail } else { Send-Msg $ChatId $fail | Out-Null }
        if ($tail) { Send-Msg $ChatId "Loglar:`n$tail" | Out-Null }
    }
    Write-Log ">>> [$Name] tugadi, kod=$($proc.ExitCode) release=$relUrl" 'Cyan'
}

# =====================================================================
#  AUTO UPDATE navbati (.webhook_queue\<loyiha>.trigger)
#  Trigger faylni GitHub poller (pastda) yoki github_webhook_listener.ps1
#  yozadi. Build'lar bot bilan bitta oqimda, ketma-ket ketadi. Fayl build'dan
#  OLDIN o'chiriladi: build paytida kelgan yangi push qayta navbatga tushadi.
# =====================================================================
$QueueDir = Join-Path $Dir '.webhook_queue'

function Add-Trigger([string]$Name, [string]$Sha) {
    if (-not (Test-Path $QueueDir)) { New-Item -ItemType Directory -Path $QueueDir | Out-Null }
    Set-Content -Path (Join-Path $QueueDir "$Name.trigger") -Value ("{0} {1}" -f (Get-Date -Format 's'), $Sha) -Encoding ASCII
}

function Invoke-WebhookQueue {
    if (-not (Test-Path $QueueDir)) { return }
    if ($Allowed.Count -eq 0) { return }
    foreach ($f in @(Get-ChildItem $QueueDir -Filter '*.trigger' -File | Sort-Object LastWriteTime)) {
        $name = $f.BaseName
        try { Remove-Item $f.FullName -Force } catch { continue }
        if (-not $Projects.Contains($name)) { continue }
        Write-Log ">>> [$name] auto update - navbatdan olindi" 'Cyan'
        try { Invoke-Build ([string]$Allowed[0]) $name $false $true }
        catch { Write-Log "[ogoh] auto update build: $($_.Exception.Message)" 'DarkYellow' }
    }
}

# =====================================================================
#  GITHUB POLLER - auto update manbai
#  Har $PollSec soniyada har bir repo'ning default branch'idagi oxirgi commit
#  sha'si olinadi (GitHub API, token bilan - private repolar uchun ham).
#  Oldingi sha (.github_poll_state.json) dan farq qilsa -> trigger yoziladi.
#  Birinchi ko'rishda (state yo'q) faqat eslab qolinadi, build boshlanmaydi.
#  Sha faylda saqlanadi: bot qayta ishga tushsa ham o'tkazib yubormaydi.
# =====================================================================
$script:PollNext     = [DateTime]::MinValue
$script:PollLast     = $null
$script:PollErr      = ''
$script:PollDisabled = $false
$script:DefaultBranch = @{}

function Get-GhHeaders {
    if (-not (Test-Path $GhTokenFile)) { return $null }
    $t = (Get-Content $GhTokenFile -Raw -Encoding UTF8).Trim()
    if (-not $t) { return $null }
    return @{ Authorization = "token $t"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'uz-ai-dev-build-bot' }
}

function Get-PollState {
    $h = @{}
    if (Test-Path $PollStatePath) {
        try {
            $o = Get-Content $PollStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) {
                $h[$p.Name] = @{ sha = [string]$p.Value.sha; at = [string]$p.Value.at }
            }
        } catch { }
    }
    return $h
}

function Set-PollState($State) {
    try { ($State | ConvertTo-Json -Depth 5) | Set-Content $PollStatePath -Encoding UTF8 }
    catch { Write-Log "[ogoh] poll state saqlanmadi: $($_.Exception.Message)" 'DarkYellow' }
}

# Repo default branch'idagi oxirgi commit sha'si (40 belgi).
function Get-RemoteSha([string]$Repo, $Headers) {
    if (-not $script:DefaultBranch.ContainsKey($Repo)) {
        $info = Invoke-RestMethod -Headers $Headers -Uri "https://api.github.com/repos/$Repo" -TimeoutSec 15
        $br = [string]$info.default_branch
        if (-not $br) { $br = 'main' }
        $script:DefaultBranch[$Repo] = $br
    }
    $branch = [uri]::EscapeDataString($script:DefaultBranch[$Repo])
    $c = Invoke-RestMethod -Headers $Headers -Uri "https://api.github.com/repos/$Repo/commits/$branch" -TimeoutSec 15
    return [string]$c.sha
}

function Invoke-GitHubPoll {
    if ($script:PollDisabled) { return }
    if ((Get-Date) -lt $script:PollNext) { return }
    $script:PollNext = (Get-Date).AddSeconds($PollSec)
    if ($Allowed.Count -eq 0) { return }

    $hdrs = Get-GhHeaders
    if (-not $hdrs) {
        $script:PollDisabled = $true
        $script:PollErr = "GitHub token topilmadi: $GhTokenFile"
        Write-Log "[poll] O'CHIRILDI - $($script:PollErr)" 'Red'
        Send-Msg ([string]$Allowed[0]) "Auto update ISHLAMAYDI: GitHub token topilmadi:`n$GhTokenFile" | Out-Null
        return
    }

    $st = Get-PollState
    $changed = $false
    $errs = @()
    foreach ($name in $Repos.Keys) {
        if (-not $Projects.Contains($name)) { continue }
        $repo = $Repos[$name]
        $sha = ''
        try { $sha = Get-RemoteSha $repo $hdrs }
        catch {
            $errs += "$name : $($_.Exception.Message)"
            Write-Log "[poll] $name ($repo) XATO: $($_.Exception.Message)" 'DarkYellow'
            continue
        }
        if (-not $sha) { continue }

        $prevSha = ''
        if ($st.ContainsKey($name)) { $prevSha = [string]$st[$name].sha }
        if ($prevSha -and $prevSha -ne $sha) {
            Write-Log "[poll] $name : yangi push $($prevSha.Substring(0,7)) -> $($sha.Substring(0,7)) - navbatga qo'yildi" 'Green'
            Add-Trigger $name $sha
        } elseif (-not $prevSha) {
            Write-Log "[poll] $name : boshlang'ich sha $($sha.Substring(0,7)) eslab qolindi"
        }
        if ($prevSha -ne $sha) {
            $st[$name] = @{ sha = $sha; at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
            $changed = $true
        }
    }
    $script:PollLast = Get-Date
    $script:PollErr  = ($errs -join "`n")
    if ($changed) { Set-PollState $st }
}

# --- "auto" buyrug'i: poller holati ---
function Get-PollStatusText {
    $lines = @()
    if ($script:PollDisabled) { $lines += "Auto update O'CHIQ: $($script:PollErr)" }
    elseif ($script:PollLast) { $lines += "Auto update ishlayapti (GitHub har $PollSec s tekshiriladi). Oxirgi tekshiruv: $($script:PollLast.ToString('HH:mm:ss'))" }
    else { $lines += "Auto update: hali tekshirilmadi." }
    $st = Get-PollState
    foreach ($name in $Repos.Keys) {
        if ($st.ContainsKey($name) -and $st[$name].sha) {
            $lines += "$name : $($st[$name].sha.Substring(0,7))  ($($st[$name].at))"
        } else {
            $lines += "$name : hali ko'rilmagan"
        }
    }
    if ($script:PollErr -and -not $script:PollDisabled) { $lines += "Oxirgi xatolar:`n$($script:PollErr)" }
    return ($lines -join "`n")
}

# --- Ishga tushirish ---
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  uz_ai_dev  Telegram build bot (ko'p loyihali) ishga tushdi" -ForegroundColor Green
Write-Host "  Loyihalar: $($Projects.Keys -join ', ')" -ForegroundColor Green
if ($Allowed.Count -gt 0) {
    Write-Host "  Ruxsat: $($Allowed -join ', ')" -ForegroundColor Green
} else {
    Write-Host "  DIQQAT: chat ID sozlanmagan - botga yozing, ID sini aytadi." -ForegroundColor Yellow
}
Write-Host "  Auto update: GitHub polling har $PollSec s, admin = $(if ($Allowed.Count) { $Allowed[0] } else { '-' })" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Log "bot ishga tushdi (auto update: GitHub polling har $PollSec s)" 'Green'

# Backlog (bot o'chik turgandagi) xabarlarni tashlab yuboramiz
$offset = 0
try {
    $init = Invoke-RestMethod -Uri "$Api/getUpdates?timeout=0&offset=-1" -TimeoutSec 20
    if ($init.ok -and $init.result.Count -gt 0) { $offset = [int]$init.result[-1].update_id + 1 }
} catch { }

while ($true) {
    try {
        Invoke-GitHubPoll
        Invoke-WebhookQueue
        # timeout=10: poller/navbat ko'pi bilan ~10 soniyada ko'riladi
        $r = Invoke-RestMethod -Uri "$Api/getUpdates?timeout=10&offset=$offset" -TimeoutSec 25
        if (-not $r.ok) { Start-Sleep 2; continue }

        foreach ($u in $r.result) {
            $offset = [int]$u.update_id + 1

            # --- Tugma bosildi (callback) ---
            if ($u.callback_query) {
                $cb     = $u.callback_query
                $chatId = [string]$cb.message.chat.id
                $fromId = [string]$cb.from.id
                Answer-Cb $cb.id
                if ($Allowed.Count -gt 0 -and $Allowed -notcontains $fromId) {
                    Send-Msg $chatId "Ruxsat yo'q. Sizning ID: $fromId" | Out-Null; continue
                }
                $data = [string]$cb.data
                if ($data -eq 'sh5:refresh') {
                    Invoke-Sh5Refresh $chatId
                    continue
                }
                if ($data -like 'b:*' -or $data -like 'f:*') {
                    $force = $data.StartsWith('f:')   # "Baribir build qilish" - versiya tekshiruvisiz
                    $name  = $data.Substring(2)
                    if ($Projects.Contains($name)) { Invoke-Build $chatId $name $force }
                    else { Send-Msg $chatId "Noma'lum loyiha: $name" | Out-Null }
                }
                continue
            }

            # --- Oddiy xabar ---
            $msg = $u.message
            if ($null -eq $msg) { continue }
            $chatId = [string]$msg.chat.id
            $fromId = [string]$msg.from.id
            $text   = ''
            if ($msg.text) { $text = $msg.text.Trim() }
            Write-Host ("[{0}] {1}" -f $chatId, $text)

            if ($Allowed.Count -eq 0) {
                Send-Msg $chatId "Sizning chat ID: $chatId`nUni serverda .telegram_bot.config.txt 2-qatoriga qo'ying va botni qayta ishga tushiring." | Out-Null
                continue
            }
            if ($Allowed -notcontains $fromId) {
                Send-Msg $chatId "Ruxsat yo'q. Sizning ID: $fromId" | Out-Null; continue
            }

            $cmd = ($text -replace '@\w+$', '').ToLower()
            switch -Regex ($cmd) {
                '^/?(build|menu|start|loyiha)$' { Show-Menu $chatId }
                '^/?(ostatka|astatka)$'         { Invoke-Sh5Refresh $chatId }
                '^/?(auto|poll|avto)$'          { Send-Msg $chatId (Get-PollStatusText) | Out-Null }
                '^/?(status|ping)$'             { Send-Msg $chatId "Bot tirik. Loyihalar: $($Projects.Keys -join ', '). 'build' - menyu, 'ostatka' - SH5 qoldiqni yangilash, 'auto' - auto update holati, 'versiya' - oxirgi build'lar." | Out-Null }
                '^/?(versiya|version)$'         {
                    $st    = Get-State
                    $lines = @("Oxirgi build qilingan versiyalar:")
                    foreach ($k in $Projects.Keys) {
                        if ($st.ContainsKey($k) -and $st[$k].version) {
                            $lines += "$k : v$($st[$k].version)  ($($st[$k].at))"
                            if ($st[$k].url) { $lines += "   $($st[$k].url)" }
                        } else {
                            $lines += "$k : hali build qilinmagan"
                        }
                    }
                    Send-Msg $chatId ($lines -join "`n") | Out-Null
                }
                default                         { Send-Msg $chatId "'build' - loyihalar ro'yxati. 'versiya' - oxirgi build versiyalari. 'ostatka' - SH5 qoldiqni yangilash. 'auto' - auto update holati." | Out-Null }
            }
        }
    }
    catch {
        Write-Log "[ogoh] loop: $($_.Exception.Message)" 'DarkYellow'
        Start-Sleep 3
    }
}
