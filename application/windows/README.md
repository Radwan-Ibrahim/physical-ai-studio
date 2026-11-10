# Windows packaging

Builds Physical AI Studio as a Windows 11 MSIX package.

| File                                                             | Purpose                                                           |
|------------------------------------------------------------------|-------------------------------------------------------------------|
| [build_msix.ps1](./build_msix.ps1)                               | Builds, packs and signs the MSIX.                                 |
| [AppxManifest.xml](./AppxManifest.xml)                           | Package manifest template; the build fills in identity and version. |
| [physicalai_studio_launcher.py](./physicalai_studio_launcher.py) | Package entry point: starts the server and opens the browser.     |

## What the package contains

```text
python\          relocatable CPython (python-build-standalone) with every dependency in site-packages
ffmpeg\bin\      LGPL shared FFmpeg, which torchcodec loads through PATH
Assets\          tile images
```

The entry point runs `python\python.exe -I -X utf8 -m physicalai_studio_launcher`. Dependencies are
installed from `application/backend/uv.lock` exactly as `uv sync --frozen --extra <cpu|xpu|cuda>` would,
so the PyTorch build matches the chosen extra.

The manifest disables file-system write virtualization so that `%LOCALAPPDATA%\physicalai`
(datasets, models, database) is the real folder: it is shared with non-MSIX installs and
survives uninstalling the app.

## Build

Prerequisites: Windows 10/11 SDK (for `makeappx.exe` and `signtool.exe`), [uv](https://docs.astral.sh/uv/),
and Node.js 24.

```powershell
# Development build signed with a self-signed certificate (created once in Cert:\CurrentUser\My).
.\application\windows\build_msix.ps1 -Extra cpu -DevCertificate

# Release build with a real code-signing certificate. -Publisher must equal the certificate's Subject.
.\application\windows\build_msix.ps1 -Extra xpu -Publisher "CN=..., O=..., C=..." `
    -CertificatePath .\codesign.pfx -CertificatePassword (Read-Host -AsSecureString)
```

The package is written to `application\windows\dist\`. Useful options:

- `-RuntimeSource ..\physicalai` installs a local checkout of the `physicalai` runtime over the
  locked release, to test runtime changes before they are published.
- `-SkipBuild` repacks the existing `dist\stage` without rebuilding the UI or dependencies.
- `-FFmpegUrl` pins a different FFmpeg archive; the build prints the archive's SHA-256.

The [Windows MSIX workflow](../../.github/workflows/windows-msix.yml) builds the package in CI. Set
the `WINDOWS_SIGNING_PFX_BASE64` and `WINDOWS_SIGNING_PFX_PASSWORD` secrets and the
`WINDOWS_SIGNING_PUBLISHER` variable to sign with a real certificate.

## Install and run

See [Install on Windows 11](../docs/01-installation.md#install-on-windows-11-msix).

## Known limitations

- Trossen arms (`physicalai-trossen-plugin`) and Basler/GenICam cameras are not available on Windows.
- Remote SSH trainers must run Linux; Windows can drive them as a client.
- iceoryx2 0.9 keeps its shared-memory files in `C:\Temp\iceoryx2`; the runtime creates the folder on first use.
