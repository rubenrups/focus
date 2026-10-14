# Read-only scan of local git repos. Never modifies anything: only runs
# `git status`, `git rev-parse`, `git rev-list`, `git log`.
#
# Works with any layout: one or many roots, repos at any depth up to -Depth,
# plus explicit single repos via -Repos. Skips dependency/build folders.
#
# Examples:
#   .\scan-repos.ps1 -Roots 'C:\Code'
#   .\scan-repos.ps1 -Roots 'D:\dev','C:\Users\me\Documents' -Depth 4 -Out 'C:\Users\me\focus\repo-scan.md'
#   .\scan-repos.ps1 -Repos 'C:\random\thing','E:\old\project'
param(
    [string[]]$Roots   = @(),
    [string[]]$Repos   = @(),
    [int]     $Depth   = 4,
    [string[]]$Exclude = @(),   # extra substrings; a path containing any is skipped
    [string]  $Out     = (Join-Path $PSScriptRoot 'repo-scan.md')
)

# Folders never worth descending into.
$skipDirs = @('node_modules','vendor','.venv','venv','__pycache__','dist','build',
              '.next','.gradle','Pods','target','.cache','AppData','$RECYCLE.BIN',
              'Windows','Program Files','Program Files (x86)')

$found = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)

function Find-Repos([string]$dir, [int]$left) {
    if ($left -lt 0) { return }
    if (Test-Path -LiteralPath (Join-Path $dir '.git')) { [void]$found.Add($dir) }
    $kids = Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue
    foreach ($k in $kids) {
        if ($k.Name -eq '.git' -or $skipDirs -contains $k.Name) { continue }
        if ($Exclude | Where-Object { $_ -and $k.FullName -like "*$_*" }) { continue }
        Find-Repos $k.FullName ($left - 1)
    }
}

foreach ($r in $Roots) { if (Test-Path -LiteralPath $r) { Find-Repos (Resolve-Path -LiteralPath $r).Path $Depth } else { Write-Warning "Root not found: $r" } }
foreach ($r in $Repos) { if (Test-Path -LiteralPath (Join-Path $r '.git')) { [void]$found.Add((Resolve-Path -LiteralPath $r).Path) } else { Write-Warning "Not a git repo: $r" } }

$rows = foreach ($r in ($found | Sort-Object)) {
    $branch   = (git -C $r rev-parse --abbrev-ref HEAD 2>$null)
    $dirty    = @(git -C $r status --porcelain 2>$null).Count
    $upstream = (git -C $r rev-parse --abbrev-ref '@{u}' 2>$null)
    $ahead    = if ($upstream) { [int](git -C $r rev-list --count '@{u}..HEAD' 2>$null) } else { $null }
    $lastIso  = (git -C $r log -1 --format=%cI 2>$null)
    $lastDays = if ($lastIso) { [int]((Get-Date) - [datetime]$lastIso).TotalDays } else { $null }
    [pscustomobject]@{
        Repo = $r; Branch = $branch; Dirty = $dirty; Ahead = $ahead
        NoRemote = (-not $upstream); LastDays = $lastDays
    }
}

$attention = $rows | Where-Object { $_.Dirty -gt 0 -or ($_.Ahead -gt 0) }
$noUp      = $rows | Where-Object { $_.NoRemote -and $_.Dirty -eq 0 }

$md = @()
$md += "# Repo scan - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$md += ""
$md += "Scanned $(@($rows).Count) repos. Roots: $($Roots -join ', ') | Extra repos: $(@($Repos).Count) | Depth: $Depth"
$md += ""
$md += "## Needs attention (uncommitted changes or unpushed commits)"
if ($attention) {
    $md += "| Repo | Branch | Uncommitted files | Unpushed commits | Last commit (days ago) |"
    $md += "|---|---|---|---|---|"
    foreach ($a in ($attention | Sort-Object -Property Dirty -Descending)) {
        $md += "| $($a.Repo) | $($a.Branch) | $($a.Dirty) | $(if ($null -eq $a.Ahead) {'n/a'} else {$a.Ahead}) | $($a.LastDays) |"
    }
} else { $md += "_Nothing._" }
$md += ""
$md += "## Clean but has no upstream branch ($(@($noUp).Count))"
$md += ($noUp | ForEach-Object { "- $($_.Repo) ($($_.Branch))" })

$md -join "`n" | Set-Content -LiteralPath $Out -Encoding UTF8
Write-Output "Wrote $Out ($(@($rows).Count) repos, $(@($attention).Count) need attention)"
