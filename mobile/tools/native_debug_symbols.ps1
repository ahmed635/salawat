# Builds the "native debug symbols" zip that Play Console asks for after an
# app bundle upload ("this bundle contains native code but no symbols").
#
# Why this exists instead of android.buildTypes.release.ndk.debugSymbolLevel:
# that setting only repackages debug info AGP finds in the merged .so files,
# and every native library we ship is already stripped before AGP sees it
# (Flutter strips libapp.so during AOT; the engine ships stripped). It emits an
# empty file, so the warning never clears.
#
# For libflutter.so we can do better than the stripped copy: Google publishes an
# unstripped build of the exact same binary, keyed by engine revision. Its GNU
# build ID matches the shipped library, which is how Play pairs a crash address
# with these symbols -- so engine frames come back with real function names
# instead of raw offsets. libapp.so (our Dart code) has no equivalent; use
# --split-debug-info + `flutter symbolize` for Dart frames.
#
# Run AFTER `flutter build appbundle`, then upload the zip in Play Console:
#   App bundle explorer -> pick the version -> Downloads -> Native debug symbols.
#
#   pwsh -File tools\native_debug_symbols.ps1          # function + file + line
#   pwsh -File tools\native_debug_symbols.ps1 -Light   # function names only
#
# -Light drops .debug_info from the engine symbols, which is ~10x smaller to
# upload and still names every frame. It needs llvm-objcopy from the Android
# NDK; without one it falls back to full symbols.

param([switch]$Light)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest's progress bar is very slow

$repo  = Split-Path -Parent $PSScriptRoot
$libs  = Join-Path $repo 'build\app\intermediates\merged_native_libs\release\mergeReleaseNativeLibs\out\lib'
$cache = Join-Path $repo 'build\engine-symbols'
$stage = Join-Path $repo 'build\native-debug-symbols'
$out   = Join-Path $repo 'build\app\outputs\native-debug-symbols.zip'

if (-not (Test-Path $libs)) {
    throw "No release native libs at $libs -- run 'flutter build appbundle' first."
}

# The engine revision printed by `flutter --version` is abbreviated; the storage
# bucket is keyed by the full hash, so read it from the SDK instead.
$sdk = ((Get-Content (Join-Path $repo 'android\local.properties') |
         Select-String '^flutter\.sdk=(.*)$').Matches.Groups[1].Value) -replace '\\\\', '\'
$engine = (Get-Content (Join-Path $sdk 'bin\internal\engine.version')).Trim()
Write-Host "Engine revision $engine"

# ABI directory name in the bundle -> engine artifact name in the bucket.
$abis = @{ 'arm64-v8a' = 'android-arm64-release'
           'armeabi-v7a' = 'android-arm-release'
           'x86_64' = 'android-x64-release' }

New-Item -ItemType Directory -Force -Path $cache | Out-Null
foreach ($abi in $abis.Keys) {
    $dir = Join-Path $cache "$engine\$abi"
    if (Test-Path (Join-Path $dir 'libflutter.so')) { continue }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $zip = Join-Path $dir 'symbols.zip'
    $url = "https://storage.googleapis.com/flutter_infra_release/flutter/$engine/$($abis[$abi])/symbols.zip"
    Write-Host "Downloading $abi symbols..."
    Invoke-WebRequest -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    Remove-Item $zip -Force
}

$objcopy = $null
if ($Light) {
    $objcopy = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\ndk\*\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-objcopy.exe" `
                   -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
    if (-not $objcopy) { Write-Warning "llvm-objcopy not found in the NDK -- keeping full debug info." }
}

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
Copy-Item $libs $stage -Recurse

foreach ($abi in $abis.Keys) {
    $src = Join-Path $cache "$engine\$abi\libflutter.so"
    $dst = Join-Path $stage "$abi\libflutter.so"
    if (-not (Test-Path $dst)) { continue }   # ABI not in this bundle
    if ($objcopy) { & $objcopy.FullName --strip-debug $src $dst } else { Copy-Item $src $dst -Force }
}

if (Test-Path $out) { Remove-Item $out -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $out

$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "Wrote $out ($mb MB)"
