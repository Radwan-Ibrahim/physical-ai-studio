<#
.SYNOPSIS
    Build a Windows 11 MSIX package of Physical AI Studio.

.DESCRIPTION
    Bundles a relocatable CPython, the backend and all of its dependencies from
    the frozen lock, the built web UI, and an LGPL FFmpeg build into one MSIX.
    Run from any directory on Windows with uv, Node.js 24+ and the Windows SDK.

.EXAMPLE
    # Unsigned-for-distribution development build, signed with a throwaway self-signed certificate.
    .\application\windows\build_msix.ps1 -DevCertificate

.EXAMPLE
    # Release build signed with your code-signing certificate.
    .\application\windows\build_msix.ps1 -Extra xpu -Publisher "CN=Contoso, O=Contoso, C=US" `
        -CertificatePath .\codesign.pfx -CertificatePassword (Read-Host -AsSecureString)
#>
[CmdletBinding(DefaultParameterSetName = "Dev")]
param(
    # Which PyTorch build to bundle (see application/backend/pyproject.toml extras).
    [ValidateSet("cpu", "xpu", "cuda")]
    [string]$Extra = "cpu",

    # Four-part MSIX version; defaults to the backend version with a trailing .0.
    [string]$Version,

    # Must equal the Subject of the signing certificate.
    [string]$Publisher = "CN=PhysicalAIStudioDev",
    [string]$PublisherDisplayName = "Physical AI Studio contributors",
    [string]$IdentityName = "OpenEdgePlatform.PhysicalAIStudio",

    # A local checkout of the physicalai runtime to install over the locked release.
    [string]$RuntimeSource,

    # LGPL shared FFmpeg build for torchcodec, which supports FFmpeg 4-8. Override to pin a specific archive.
    [string]$FFmpegUrl = "https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/latest/ffmpeg-n8.1-latest-win64-lgpl-shared-8.1.zip",

    [string]$OutputDir,

    [Parameter(ParameterSetName = "Dev")]
    [switch]$DevCertificate,

    [Parameter(ParameterSetName = "Release", Mandatory = $true)]
    [string]$CertificatePath,
    [Parameter(ParameterSetName = "Release", Mandatory = $true)]
    [securestring]$CertificatePassword,

    # Reuse an existing build/stage directory's UI and dependencies (faster iteration on packaging only).
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$WindowsDir = $PSScriptRoot
$ApplicationDir = Split-Path $WindowsDir -Parent
$BackendDir = Join-Path $ApplicationDir "backend"
$UiDir = Join-Path $ApplicationDir "ui"
if (-not $OutputDir) { $OutputDir = Join-Path $WindowsDir "dist" }
$BuildDir = Join-Path $OutputDir "build"
$StageDir = Join-Path $OutputDir "stage"
$PythonDir = Join-Path $StageDir "python"
$SitePackages = Join-Path $PythonDir "Lib\site-packages"
$Venv = Join-Path $BuildDir "venv"

function Find-SdkTool([string]$Name) {
    $onPath = Get-Command $Name -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    $tool = Get-ChildItem $kits -Filter $Name -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq "x64" } |
        Sort-Object { [version]$_.Directory.Parent.Name } -Descending |
        Select-Object -First 1
    if (-not $tool) { throw "$Name not found. Install the Windows 10/11 SDK." }
    return $tool.FullName
}

function Get-BackendVersion {
    $line = Select-String -Path (Join-Path $BackendDir "pyproject.toml") -Pattern '^version\s*=\s*"([^"]+)"' | Select-Object -First 1
    $semver = $line.Matches[0].Groups[1].Value -replace '[^0-9.].*$', ''
    $parts = @($semver.Split(".") | Where-Object { $_ })
    while ($parts.Count -lt 4) { $parts += "0" }
    return ($parts[0..3] -join ".")
}

function Install-RuntimeOverlay {
    if ($RuntimeSource) {
        Write-Host "Installing physicalai runtime from $RuntimeSource"
        uv pip install --python (Join-Path $Venv "Scripts\python.exe") --no-deps --reinstall-package physicalai $RuntimeSource
    }
}

function Sync-Backend([switch]$WithoutProject) {
    $arguments = @("sync", "--frozen", "--no-default-groups", "--no-editable", "--extra", $Extra, "--compile-bytecode")
    if ($WithoutProject) { $arguments += "--no-install-project" }
    Push-Location $BackendDir
    try {
        $env:UV_PROJECT_ENVIRONMENT = $Venv
        uv @arguments
    } finally {
        Remove-Item Env:UV_PROJECT_ENVIRONMENT -ErrorAction SilentlyContinue
        Pop-Location
    }
}

function New-TileImages([string]$Destination) {
    Add-Type -AssemblyName System.Drawing
    $source = [System.Drawing.Image]::FromFile((Join-Path $ApplicationDir "..\docs\assets\physical_ai_studio.png"))
    try {
        # The banner's right edge holds the robot arm, which reads well as a square icon.
        $square = [System.Drawing.Rectangle]::new($source.Width - $source.Height - 16, 0, $source.Height, $source.Height)
        $wideHeight = [int]($source.Width * 150 / 310)
        $wide = [System.Drawing.Rectangle]::new(0, [Math]::Max(0, ($source.Height - $wideHeight) / 2), $source.Width, [Math]::Min($source.Height, $wideHeight))
        $tiles = @(
            @{ Name = "Square44x44Logo.png"; W = 44; H = 44; Crop = $square },
            @{ Name = "Square150x150Logo.png"; W = 150; H = 150; Crop = $square },
            @{ Name = "StoreLogo.png"; W = 50; H = 50; Crop = $square },
            @{ Name = "Wide310x150Logo.png"; W = 310; H = 150; Crop = $wide }
        )
        foreach ($tile in $tiles) {
            $bitmap = [System.Drawing.Bitmap]::new($tile.W, $tile.H)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, $tile.W, $tile.H), $tile.Crop, [System.Drawing.GraphicsUnit]::Pixel)
            $graphics.Dispose()
            $bitmap.Save((Join-Path $Destination $tile.Name), [System.Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose()
        }
    } finally {
        $source.Dispose()
    }
}

$makeAppx = Find-SdkTool "makeappx.exe"
$signTool = Find-SdkTool "signtool.exe"
if (-not $Version) { $Version = Get-BackendVersion }
Write-Host "Building Physical AI Studio $Version ($Extra) MSIX"

if (-not $SkipBuild) {
    Remove-Item $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $BuildDir, $StageDir | Out-Null

    # 1. Relocatable CPython (python-build-standalone) matching the backend's pin.
    $pythonVersion = (Get-Content (Join-Path $BackendDir ".python-version") -Raw).Trim()
    $pythonInstall = Join-Path $BuildDir "python-install"
    uv python install $pythonVersion --install-dir $pythonInstall
    $installed = Get-ChildItem $pythonInstall -Directory | Where-Object { Test-Path (Join-Path $_.FullName "python.exe") } | Select-Object -First 1
    if (-not $installed) { throw "uv did not install a standalone CPython into $pythonInstall" }
    Copy-Item $installed.FullName $PythonDir -Recurse
    # Studio has no Tk UI, and signtool cannot sign an MSIX containing these Tcl/Tk DLLs (0x800700C1).
    Remove-Item (Join-Path $PythonDir "DLLs\tcl86t.dll"), (Join-Path $PythonDir "DLLs\tk86t.dll"), (Join-Path $PythonDir "DLLs\_tkinter.pyd") -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $PythonDir "tcl"), (Join-Path $PythonDir "Lib\tkinter"), (Join-Path $PythonDir "Lib\idlelib"), (Join-Path $PythonDir "Lib\turtledemo") -Recurse -ErrorAction SilentlyContinue
    uv venv $Venv --python (Join-Path $PythonDir "python.exe")

    # 2. Dependencies first: the OpenAPI schema the UI is typed from needs the backend importable.
    Sync-Backend -WithoutProject
    Install-RuntimeOverlay
    $openApi = Join-Path $UiDir "src\api\openapi-spec.json"
    Push-Location (Join-Path $BackendDir "src")
    try {
        & (Join-Path $Venv "Scripts\python.exe") -c "from create_openapi import create_openapi; create_openapi(target_path=r'$openApi')"
    } finally {
        Pop-Location
    }

    # 3. Web UI; the backend wheel's build hook bundles application/ui/dist.
    Push-Location $UiDir
    try {
        npm ci --audit=false
        npm run build:api
        npm run build
    } finally {
        Pop-Location
    }
    if (-not (Test-Path (Join-Path $UiDir "dist\index.html"))) { throw "UI build did not produce dist/index.html" }

    # 4. The backend itself, then the runtime overlay again (a full sync restores the locked runtime).
    Sync-Backend
    Install-RuntimeOverlay

    # 5. Move the environment into the bundled interpreter so the package needs no venv or absolute paths.
    Copy-Item (Join-Path $Venv "Lib\site-packages\*") $SitePackages -Recurse -Force
    Remove-Item (Join-Path $SitePackages "_virtualenv.*") -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $WindowsDir "physicalai_studio_launcher.py") $SitePackages

    # 6. FFmpeg shared libraries for torchcodec.
    $ffmpegZip = Join-Path $BuildDir "ffmpeg.zip"
    Invoke-WebRequest -Uri $FFmpegUrl -OutFile $ffmpegZip
    Write-Host "FFmpeg archive SHA256: $((Get-FileHash $ffmpegZip -Algorithm SHA256).Hash)"
    $ffmpegExtract = Join-Path $BuildDir "ffmpeg"
    Expand-Archive $ffmpegZip $ffmpegExtract
    $ffmpegRoot = Get-ChildItem $ffmpegExtract -Directory | Select-Object -First 1
    $ffmpegStage = Join-Path $StageDir "ffmpeg"
    New-Item -ItemType Directory -Force $ffmpegStage | Out-Null
    Copy-Item (Join-Path $ffmpegRoot.FullName "bin") $ffmpegStage -Recurse
    Copy-Item (Join-Path $ffmpegRoot.FullName "LICENSE*") $ffmpegStage -ErrorAction SilentlyContinue
}

# 7. Manifest and tile images.
$assets = Join-Path $StageDir "Assets"
New-Item -ItemType Directory -Force $assets | Out-Null
New-TileImages $assets
Copy-Item (Join-Path $ApplicationDir "..\LICENSE") (Join-Path $StageDir "LICENSE.txt")
$manifest = (Get-Content (Join-Path $WindowsDir "AppxManifest.xml") -Raw).
    Replace("{{IDENTITY_NAME}}", $IdentityName).
    Replace("{{PUBLISHER}}", [System.Security.SecurityElement]::Escape($Publisher)).
    Replace("{{PUBLISHER_DISPLAY_NAME}}", [System.Security.SecurityElement]::Escape($PublisherDisplayName)).
    Replace("{{VERSION}}", $Version)
Set-Content (Join-Path $StageDir "AppxManifest.xml") $manifest -Encoding utf8

# 8. Pack and sign.
$msix = Join-Path $OutputDir "PhysicalAIStudio_$($Version)_$($Extra)_x64.msix"
& $makeAppx pack /o /h SHA256 /d $StageDir /p $msix

if ($PSCmdlet.ParameterSetName -eq "Release") {
    $plain = [System.Net.NetworkCredential]::new("", $CertificatePassword).Password
    & $signTool sign /fd SHA256 /td SHA256 /tr "http://timestamp.digicert.com" /f $CertificatePath /p $plain $msix
} elseif ($DevCertificate) {
    $certificate = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $Publisher -and $_.NotAfter -gt (Get-Date) } | Select-Object -First 1
    if (-not $certificate) {
        $certificate = New-SelfSignedCertificate -Type Custom -Subject $Publisher -KeyUsage DigitalSignature `
            -FriendlyName "Physical AI Studio development signing" -CertStoreLocation Cert:\CurrentUser\My `
            -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
    }
    & $signTool sign /fd SHA256 /sha1 $certificate.Thumbprint $msix
    $cer = Join-Path $OutputDir "PhysicalAIStudioDev.cer"
    Export-Certificate -Cert $certificate -FilePath $cer | Out-Null
    Write-Host "Trust the development certificate once (elevated PowerShell), then install:"
    Write-Host "  Import-Certificate -FilePath `"$cer`" -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
} else {
    Write-Warning "The package is unsigned; Windows will not install it until it is signed."
}

Write-Host "MSIX: $msix"
