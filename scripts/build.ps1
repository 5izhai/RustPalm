param(
    [string]$DevEcoRoot = 'D:\Huawei\DevEcoStudio',
    [string]$Proxy = '',
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$checkout = Join-Path $projectRoot 'third_party\rustdesk'
$app = Join-Path $projectRoot 'app'
$dist = Join-Path $projectRoot 'dist'
$local = Join-Path $projectRoot '.local'
$ndk = Join-Path $DevEcoRoot 'sdk\default\openharmony\native'
$rustBin = Join-Path $env:USERPROFILE '.cargo\bin'
$bash = 'C:\Program Files\Git\bin\bash.exe'
$vcpkgRoot = Join-Path $env:USERPROFILE '.rustdesk-ohos\vcpkg'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

foreach ($path in $bash, $vswhere, "$rustBin\rustc.exe", "$ndk\llvm\bin\clang.exe") {
    if (!(Test-Path -LiteralPath $path)) { throw "Required tool is missing: $path" }
}
$null = New-Item -ItemType Directory -Path $local -Force
$buildLock = [IO.File]::Open((Join-Path $local 'build.lock'), [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    & "$PSScriptRoot\prepare-upstream.ps1" -Proxy $Proxy
    $null = New-Item -ItemType Directory -Path $dist -Force
    $vs = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if (!$vs) { throw 'Visual Studio C++ x64 tools are required.' }
    Import-Module "$vs\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
    $env:PATH = "$rustBin;$DevEcoRoot\tools\node;$DevEcoRoot\tools\ohpm\bin;$DevEcoRoot\jbr\bin;$env:PATH"
    $env:JAVA_HOME = "$DevEcoRoot\jbr"
    $env:VCPKG_ROOT = $vcpkgRoot.Replace('\', '/')
    $env:OHOS_SDK_ROOT = $DevEcoRoot.Replace('\', '/') + '/sdk/default/openharmony'
    $env:OHOS_NDK_HOME = "$env:OHOS_SDK_ROOT/native"
    $env:MSYS2_ENV_CONV_EXCL = 'PERL5LIB'
    $env:CARGO_NET_GIT_FETCH_WITH_CLI = 'true'
    if ($Proxy) {
        $env:HTTP_PROXY = $Proxy
        $env:HTTPS_PROXY = $Proxy
        $env:CARGO_HTTP_PROXY = $Proxy
        $env:GIT_CONFIG_COUNT = '2'
        $env:GIT_CONFIG_KEY_0 = 'http.proxy'
        $env:GIT_CONFIG_VALUE_0 = $Proxy
        $env:GIT_CONFIG_KEY_1 = 'http.version'
        $env:GIT_CONFIG_VALUE_1 = 'HTTP/1.1'
    }
    $rustVersion = & "$rustBin\rustc.exe" --version
    if ($rustVersion -notmatch '^rustc 1\.99\.1 ') {
        throw "Expected Rust 1.99.1. Found $rustVersion"
    }
    $vcpkgRevision = (& git -C $vcpkgRoot rev-parse HEAD).Trim()
    if ($vcpkgRevision -ne '9eec002df1cd109f8f104cd966a763daf9751489') {
        throw 'vcpkg must use the revision documented in windows-setup.md.'
    }
    $architectures = @(
        @{ Abi = 'arm64-v8a'; Suffix = ''; Output = 'aarch64-ohos'; Receipt = 'native-build.json' },
        @{ Abi = 'x86_64'; Suffix = '-x86_64'; Output = 'x86_64-ohos'; Receipt = 'native-build-x86_64.json' }
    )
    $patchHash = (Get-FileHash "$projectRoot\patches\rustdesk-ohos.patch" -Algorithm SHA256).Hash
    $diffPath = Join-Path $local 'current-core.diff'
    & git -C $checkout diff --binary --output=$diffPath HEAD
    if ($LASTEXITCODE) { throw 'Cannot fingerprint the native source.' }
    $sourceHash = (Get-FileHash $diffPath -Algorithm SHA256).Hash


    Push-Location $projectRoot
    try {
        foreach ($architecture in $architectures) {
            $core = Join-Path $checkout ("harmonyos/client/out/" + $architecture.Output + "/librustdesk.so")
            $receiptPath = Join-Path $local $architecture.Receipt
            if (!$SkipNative) {
                $env:DEVECO_SDK_HOME = $DevEcoRoot.Replace('\', '/')
                & $bash ("third_party/rustdesk/harmonyos/client/build-ohos-deps" + $architecture.Suffix + ".sh")
                if ($LASTEXITCODE) { throw 'Native dependency build failed.' }
                & $bash ("third_party/rustdesk/harmonyos/client/build-rust" + $architecture.Suffix + ".sh")
                if ($LASTEXITCODE) { throw 'Rust core build failed.' }
                & git -C $checkout diff --binary --output=$diffPath HEAD
                if ($LASTEXITCODE -or (Get-FileHash $diffPath -Algorithm SHA256).Hash -ne $sourceHash) {
                    throw 'Native source changed during the build. Run the build again.'
                }
                @{
                    patchHash = $patchHash
                    sourceHash = $sourceHash
                    coreHash = (Get-FileHash $core -Algorithm SHA256).Hash
                    rust = $rustVersion
                } | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding utf8
            } else {
                if (!(Test-Path $receiptPath) -or !(Test-Path $core)) {
                    throw 'Run one complete build before using -SkipNative.'
                }
                $receipt = Get-Content $receiptPath -Raw | ConvertFrom-Json
                if ($receipt.patchHash -ne $patchHash -or $receipt.sourceHash -ne $sourceHash -or
                    $receipt.coreHash -ne (Get-FileHash $core -Algorithm SHA256).Hash) {
                    throw 'Core source or binary changed. Run a complete build.'
                }
            }
            $libDir = Join-Path $app ("entry/libs/" + $architecture.Abi)
            $null = New-Item -ItemType Directory -Path $libDir -Force
            Copy-Item -LiteralPath $core -Destination "$libDir\librustdesk.so" -Force
        }
        & "$DevEcoRoot\tools\node\node.exe" --test tests/remote-geometry.test.mjs tests/session-messages.test.mjs tests/remote-mouse.test.mjs tests/remote-gesture.test.mjs tests/remote-keys.test.mjs tests/favorite-model.test.mjs
        if ($LASTEXITCODE) { throw 'Input/session regression tests failed.' }
        & python "$PSScriptRoot\..\tests\test_verify_hap.py" --ndk $ndk
        if ($LASTEXITCODE) { throw 'Native package validation regression tests failed.' }
        $env:DEVECO_SDK_HOME = "$DevEcoRoot\sdk"
        Set-Location $app
        & "$DevEcoRoot\tools\ohpm\bin\ohpm.bat" install --all
        if ($LASTEXITCODE) { throw 'OHPM install failed.' }
        & "$DevEcoRoot\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap --mode module -p product=default -p buildMode=debug
        if ($LASTEXITCODE) { throw 'HAP build failed.' }
        $hap = Join-Path $app 'entry\build\default\outputs\default\entry-default-unsigned.hap'
        $verification = & python "$PSScriptRoot\verify_hap.py" $hap --ndk $ndk --abi x86_64
        if ($LASTEXITCODE) { throw 'HAP verification failed.' }
        $packageReport = $verification -join "`n" | ConvertFrom-Json
        if (!$packageReport.byAbi.'arm64-v8a' -or !$packageReport.byAbi.x86_64) {
            throw 'The universal package must contain complete ARM64 and x86_64 libraries.'
        }
        $version = (Get-Content (Join-Path $app 'AppScope/app.json5') -Raw | ConvertFrom-Json).app.versionName
        $output = Join-Path $dist "RustPalm-$version-universal-unsigned.hap"
        Copy-Item -LiteralPath $hap -Destination $output -Force
        $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $([IO.Path]::GetFileName($output))" | Set-Content "$output.sha256" -Encoding ascii
        @{
            builtAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            upstream = 'd53391e9b0b87a94c5ee1f8f40252acb25867395'
            sourceDiffSha256 = $sourceHash
            patchSha256 = $patchHash
            rust = $rustVersion
            deveco = (Get-Content "$DevEcoRoot\product-info.json" -Raw | ConvertFrom-Json).version
            sdk = (Get-Content "$DevEcoRoot\sdk\default\sdk-pkg.json" -Raw | ConvertFrom-Json).data.version
            hapSha256 = $hash
            verification = $packageReport
            deviceRun = 'pending'
        } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $dist 'build-report.json') -Encoding utf8
        Write-Output "Verified unsigned HAP: $output"
    } finally {
        Pop-Location
    }

} finally {
    $buildLock.Dispose()
}
