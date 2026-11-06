param([string]$Proxy = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$checkout = Join-Path $projectRoot 'third_party\rustdesk'
$revision = 'd53391e9b0b87a94c5ee1f8f40252acb25867395'
$gitOptions = @('-c', 'http.version=HTTP/1.1')
if ($Proxy) {
    $gitOptions += @('-c', "http.proxy=$Proxy")
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    & git @gitOptions @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $($Arguments -join ' ')" }
}

if (!(Test-Path -LiteralPath (Join-Path $checkout '.git'))) {
    $null = New-Item -ItemType Directory -Path (Split-Path $checkout) -Force
    Invoke-Git clone --filter=blob:none --no-checkout https://github.com/wanghd114/rustdesk_harmonyos.git $checkout
    Invoke-Git -C $checkout config core.autocrlf false
    Invoke-Git -C $checkout config core.eol lf
    Invoke-Git -C $checkout fetch --depth 1 origin $revision
    Invoke-Git -C $checkout checkout --detach $revision
}
Invoke-Git -C $checkout config core.autocrlf false
Invoke-Git -C $checkout config core.eol lf
$actual = (& git -C $checkout rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actual -ne $revision) {
    throw "Expected upstream $revision at $checkout. Found $actual."
}
Invoke-Git -C $checkout submodule update --init --recursive
$common = (& git -C (Join-Path $checkout 'libs\hbb_common') rev-parse HEAD).Trim()
if ($common -ne '75ef5d8cd9b2e817047fb2eb4c2a1cdac7141dbf') {
    throw 'hbb_common revision does not match the pinned source.'
}
$commonChanges = & git -C (Join-Path $checkout 'libs\hbb_common') status --porcelain --untracked-files=all
if ($commonChanges) {
    throw 'hbb_common has local changes. Record them in the source baseline before building.'
}

$patch = Join-Path $projectRoot 'patches\rustdesk-ohos.patch'
if (!(Test-Path -LiteralPath $patch)) { throw "Missing core patch: $patch" }
& git -C $checkout apply --reverse --check $patch 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Git -C $checkout apply --check $patch
    Invoke-Git -C $checkout apply --intent-to-add $patch
}
$untracked = & git -C $checkout ls-files --others --exclude-standard
if ($untracked) {
    throw "Untracked upstream files would escape source checks: $($untracked -join ', ')"
}
Write-Output "RustDesk $revision with RustPalm patch is ready."
