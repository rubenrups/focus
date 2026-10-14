# Turns focus.md + repo-scan.md into two JSON snapshots for the dashboard.
# Read-only on its inputs; writes only board.json and repos.json into -OutDir.
# Repo paths are reduced to their last two segments ("Apps\Foo"): names only.
param(
    [string]$Board  = (Join-Path $PSScriptRoot 'focus.md'),
    [string]$Scan   = (Join-Path $PSScriptRoot 'repo-scan.md'),
    [string]$OutDir = (Join-Path $PSScriptRoot 'snapshots'),
    [string]$Question = 'What is the ONE thing for today, and what is done-when?',
    # Optional judgement from the morning brief: repos (as "Apps\Foo") that have no
    # card or session. When given, it overrides the name-matching heuristic.
    [string[]]$Slipping = $null
)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$now = (Get-Date).ToString('o')

function Get-Section([string[]]$lines, [string]$name) {
    $out = @(); $in = $false
    foreach ($l in $lines) {
        if ($l -match '^##\s+(.+?)\s*$') { $in = ($Matches[1] -eq $name); continue }
        if ($in) { $out += $l }
    }
    $out | Where-Object { $_ -match '^\s*-\s+' -and $_ -notmatch '^\s*<!--' } |
        ForEach-Object { ($_ -replace '^\s*-\s+', '').Trim() }
}

function Split-Pipe([string]$s) { ($s -split '\s\|\s') | ForEach-Object { $_.Trim() } }

function To-Date([string]$s) {
    if ($s -match '^\d{4}-\d{2}-\d{2}') { return $Matches[0] }
    return $null
}

$md = Get-Content -LiteralPath $Board -Encoding UTF8

# Now: "title | done when <text> | since <ISO or yyyy-mm-dd>" or "(nothing yet ...)"
$nowObj = $null
$nowLine = Get-Section $md 'Now' | Select-Object -First 1
if ($nowLine -and $nowLine -notmatch '^\(nothing') {
    $p = Split-Pipe $nowLine
    $dw = $p | Where-Object { $_ -match '^done when' } | Select-Object -First 1
    $sn = $p | Where-Object { $_ -match '^since' } | Select-Object -First 1
    $nowObj = [ordered]@{
        title    = $p[0]
        doneWhen = if ($dw) { $dw -replace '^done when:?\s*', '' } else { $null }
        since    = if ($sn) { $sn -replace '^since:?\s*', '' } else { $null }
    }
}

# Open: "title | source | started | last touched"
$open = @(Get-Section $md 'Open' | ForEach-Object {
    $p = Split-Pipe $_
    $src = if ($p.Count -gt 1) { $p[1] } else { '' }
    $kind = switch -Regex ($src) {
        '^trello'  { 'Trello'; break }
        '^session' { 'Session'; break }
        '^repo'    { 'Repo'; break }
        default    { 'Chat' }
    }
    [ordered]@{
        title   = $p[0]
        kind    = $kind
        source  = (($src -replace '^(trello|sessions?|repo):\s*', '') -replace '[A-Za-z]:\\(?:[^\\\s]+\\)*?([^\\\s]+\\[^\\\s]+)(?=\s|$)', '$1')
        started = if ($p.Count -gt 2) { To-Date $p[2] } else { $null }
        touched = if ($p.Count -gt 3) { To-Date $p[3] } else { $null }
    }
})

$parked = @(Get-Section $md 'Parked' | ForEach-Object { [ordered]@{ title = $_ } })

$log = @(Get-Section $md 'Log' | ForEach-Object {
    $p = Split-Pipe $_
    [ordered]@{ date = $p[0]; text = (($p | Select-Object -Skip 1) -join ' | ') }
})
[array]::Reverse($log)

$boardDoc = [ordered]@{
    updated  = $now
    now      = $nowObj
    question = $Question
    open     = $open
    parked   = $parked
    log      = @($log | Select-Object -First 12)
}
$boardDoc | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'board.json') -Encoding UTF8

# Repos
$openText = ($open | ForEach-Object { "$($_.title) $($_.source)" }) -join "`n"
$scanLines = Get-Content -LiteralPath $Scan -Encoding UTF8
$scanned = 0; $noUp = 0
foreach ($l in $scanLines) {
    if ($l -match '^Scanned (\d+) repos') { $scanned = [int]$Matches[1] }
    if ($l -match '^## Clean but has no upstream branch \((\d+)\)') { $noUp = [int]$Matches[1] }
}
$attention = @(
    $scanLines | Where-Object { $_ -match '^\|\s*[A-Za-z]:\\' } | ForEach-Object {
        $c = ($_ -replace '^\||\|\s*$', '') -split '\|' | ForEach-Object { $_.Trim() }
        $segs = $c[0] -split '\\' | Where-Object { $_ }
        $short = ($segs | Select-Object -Last 2) -join '\'
        $leaf  = $segs[-1]
        $days  = if ($c[4] -match '^\d+$') { [int]$c[4] } else { $null }
        [ordered]@{
            name     = $short
            branch   = $c[1]
            dirty    = [int]$c[2]
            ahead    = if ($c[3] -match '^\d+$') { [int]$c[3] } else { $null }
            lastDays = $days
            # true = has a card/session, false = slipping through, null = unknown (stale, not judged)
            tracked  = if ($null -ne $Slipping) { -not ($Slipping -contains $short) }
                       elseif ($openText -match [regex]::Escape($leaf)) { $true }
                       elseif ($null -ne $days -and $days -le 14) { $false }
                       else { $null }
        }
    }
)
$reposDoc = [ordered]@{
    updated    = $now
    scanned    = $scanned
    noUpstream = $noUp
    attention  = @($attention | Sort-Object { -[int]$_.dirty })
}
$reposDoc | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'repos.json') -Encoding UTF8

Write-Output "Wrote $OutDir\board.json ($($open.Count) open, $($parked.Count) parked) and repos.json ($($attention.Count) repos)"
