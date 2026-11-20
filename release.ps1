<#
.SYNOPSIS
  Releases Gratuity: checks, commits what is left, pushes main and the version tag, then follows the upload.

.DESCRIPTION
  Pushing the tag starts the Release workflow (.github/workflows/release.yml), which builds the zip and uploads it to
  CurseForge, Wago and a GitHub release. Test in game first: this script releases to players.

  Refuses when: the version isn't like 2.1.2 (or 2.2.0-beta1), you're not on main, main is behind origin, the tag already
  exists, CHANGELOG.md has no "## <version>" section, the commit email isn't GitHub's no-reply address, or
  tools/lua_strcheck.py finds a problem in a .lua file.

.EXAMPLE
  .\release.ps1 2.1.2            # asks before committing and pushing
  .\release.ps1 2.1.2 -DryRun    # only the checks and what it would do
  .\release.ps1 2.1.2 -Yes       # no question (when you've already decided)
#>
param(
    [Parameter(Mandatory)][string]$Version,
    [string]$Message,      # commit message for changes still uncommitted (default: "<version>: <first changelog line>")
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$NoWait        # don't follow the workflow run
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
function Fail($text) { Write-Host "release: $text" -ForegroundColor Red; exit 1 }
function RunGit { & git.exe @args; if ($LASTEXITCODE -ne 0) { Fail "git $($args -join ' ') failed" } }

# --- checks -----------------------------------------------------------------------------------------------------------
if ($Version -notmatch '^\d+\.\d+\.\d+(-(alpha|beta)\d*)?$') { Fail "version '$Version' should look like 2.1.2 or 2.2.0-beta1 (no 'v')" }

$branch = git branch --show-current
if ($branch -ne "main") { Fail "on branch '$branch', not main" }

$email = git config user.email
if ($email -notlike "*@users.noreply.github.com") { Fail "commit email is '$email'; set the GitHub no-reply address first (git config user.email)" }

RunGit fetch -q origin main --tags
$behind = [int](git rev-list --count HEAD..origin/main)
if ($behind -gt 0) { Fail "main is $behind commit(s) behind origin/main; pull first" }

git rev-parse -q --verify "refs/tags/$Version" *> $null
if ($LASTEXITCODE -eq 0) { Fail "tag $Version already exists" }

$changelog = Get-Content CHANGELOG.md
$start = [array]::IndexOf($changelog, "## $Version")
if ($start -lt 0) { Fail "CHANGELOG.md has no '## $Version' section" }
$notes = $changelog[($start + 1)..($changelog.Count - 1)] | ForEach-Object { $_ } | Select-Object -First 30
$end = 0; while ($end -lt $notes.Count -and $notes[$end] -notmatch '^## ') { $end++ }
$notes = @($notes[0..([Math]::Max(0, $end - 1))] | Where-Object { $_.Trim() })

$lua = @(Get-ChildItem -Filter *.lua -File | ForEach-Object FullName)
python -I tools/lua_strcheck.py $lua
if ($LASTEXITCODE -ne 0) { Fail "lua_strcheck found problems" }

$toc = Get-Content Gratuity.toc -Raw
if ($toc -notmatch '## Version: @project-version@') { Fail "Gratuity.toc must keep '## Version: @project-version@' (the tag fills it in)" }

# --- plan -------------------------------------------------------------------------------------------------------------
$pending = @(git status --porcelain)
if (-not $Message) {
    $first = ($notes | Select-Object -First 1) -replace '^\s*-\s*', '' -replace '\*\*', ''
    if ($first.Length -gt 60) { $first = $first.Substring(0, 57) + "..." }
    $Message = "${Version}: $first"
}
Write-Host "Release Gratuity $Version" -ForegroundColor Cyan
Write-Host "Changelog:"; $notes | ForEach-Object { Write-Host "  $_" }
if ($pending.Count) {
    Write-Host "Commit $($pending.Count) change(s) as '$Message':"; $pending | ForEach-Object { Write-Host "  $_" }
} else { Write-Host "Nothing to commit." }
Write-Host "Then: push main, create tag $Version, push it (uploads to CurseForge, Wago and a GitHub release)."
if ($DryRun) { Write-Host "Dry run: nothing changed." -ForegroundColor Yellow; exit 0 }
if (-not $Yes) {
    $answer = Read-Host "Release to players now? (y/N)"
    if ($answer -notmatch '^(y|yes)$') { Write-Host "Stopped; nothing changed."; exit 0 }
}

# --- release ----------------------------------------------------------------------------------------------------------
if ($pending.Count) { RunGit add -A; RunGit commit -q -m $Message }
RunGit push -q origin main
RunGit tag -a $Version -m "Gratuity $Version"
RunGit push -q origin $Version
Write-Host "Pushed main and tag $Version." -ForegroundColor Green

if ($NoWait -or -not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Follow the upload at https://github.com/jnxldr/WoW-Gratuity/actions"
    exit 0
}
$run = $null
foreach ($i in 1..30) {
    $run = gh run list --workflow release.yml --branch $Version -L 1 --json databaseId -q '.[0].databaseId' 2>$null
    if ($run) { break }
    Start-Sleep -Seconds 2
}
if (-not $run) { Write-Host "No workflow run seen yet; check https://github.com/jnxldr/WoW-Gratuity/actions"; exit 0 }
gh run watch $run --exit-status *> $null
$ok = $LASTEXITCODE -eq 0
gh run view $run --log 2>$null | Select-String -Pattern 'Uploading|Success|ERROR|error:' |
    ForEach-Object { "  " + ($_.Line -replace '^.*?Z ', '') }
if ($ok) {
    Write-Host "Released: https://github.com/jnxldr/WoW-Gratuity/releases/tag/$Version" -ForegroundColor Green
} else {
    Fail "the workflow failed: gh run view $run --log"
}
