# Installation

This guide helps you install Physical AI Studio and confirm that the UI is ready.

## Choose how to run

Docker is the recommended path for most users:

- Docker starts both backend and UI together.
- You open one URL and can begin setting up projects right away.

On Windows 11, install the [MSIX package](#install-on-windows-11-msix) instead.

Use our native setup if you are planning to contribute to the project and want to make changes to either the backend or UI.

## Install with Docker (recommended)

Install [Docker Engine](https://docs.docker.com/engine/install/ubuntu/) 24.0+ with Docker Compose v2.24.0+.
For hardware-specific setup, see the [Docker README](../docker/README.md).

Check your installed versions with:

```bash
docker version
docker compose version
```

Then from `application/docker/`:

```bash
./setup-devices.sh --xpu # or use --cuda, or --cpu
docker compose up -d
```

When startup is done, open `http://localhost:7860`.

## Install on Windows 11 (MSIX)

The MSIX package bundles Python, the backend, the UI and FFmpeg; nothing else needs installing.

1. Download `PhysicalAIStudio_<version>_<cpu|xpu|cuda>_x64.msix` (pick `xpu` for Intel GPUs, `cuda` for NVIDIA GPUs).
2. Double-click it and choose **Install**. For a development build signed with the throwaway
   certificate, first trust the bundled `.cer` from an elevated PowerShell:

   ```powershell
   Import-Certificate -FilePath .\PhysicalAIStudioDev.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
   ```

3. Start **Physical AI Studio** from the Start menu. A console window shows the server log and the
   UI opens in your browser at `http://127.0.0.1:7860`. Close the console window to stop Studio.

Data is kept in `%LOCALAPPDATA%\physicalai` and survives uninstalling or upgrading the app.

On Windows, USB cameras appear through Media Foundation and robot arms as `COM` ports.
Trossen arms and Basler/GenICam cameras are not supported on Windows yet. To build the package
yourself, see the [Windows packaging README](../windows/README.md).

## First UI check

| **Project list**               |
|--------------------------------|
| ![Project list][projects-list] |

[projects-list]: ./assets/03-projects-list.png

After opening the app, you should see the projects page.
You can now create your first project. See [our getting started guide](./03-getting-started.md).

## If something does not open
[//]: # (Screenshot suggestion: Docker Desktop or terminal status indicating containers running, plus browser URL bar at localhost:7860.)

- Confirm Docker is running.
- Confirm no other app is already using the same port.
- Restart the stack from `application/docker/`.

## Alternatively install natively

You may choose to run the backend and UI directly on your system using your local python and node setup. This is mainly intended as a development setup, and requires installing prerequisites on your system.

### Prerequisites

Before starting the backend, install the system libraries.

On Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y \
  ffmpeg \
  libgl1 \
  libglib2.0-0 \
  libusb-1.0-0 \
  libusb-1.0-0-dev \
  libclang-dev \
  pkg-config \
  build-essential \
  g++ \
  git
```

If you are using another Linux distribution, install equivalent packages before running
the native setup steps below.

On Windows, install [uv](https://docs.astral.sh/uv/getting-started/installation/), Node.js 24, and a
[shared FFmpeg 4-8 build](https://www.ffmpeg.org/download.html#build-windows) whose `bin` folder is on
`PATH`. Start the backend with `.\run.ps1` from `backend/` after `uv sync --extra cpu` (or `xpu`/`cuda`).

### Backend

Install the [uv package manager](https://docs.astral.sh/uv/getting-started/installation/), then run:

```bash
cd backend
cp .env.example .env
# or `--extra cpu` or `--extra cuda`
uv run --extra xpu physicalai-studio serve
```

The backend runs at http://localhost:7860

If you plan to train Hugging Face Hub-backed policies (for example, SmolVLA,
Pi0.5, and others), configure a token in Settings > General > Hugging Face in
the UI. See [Hugging Face Integration](../backend/docs/huggingface_integration.md).

### Frontend

Install [Node.js v24](https://nodejs.org/en/download) (we recommend using nvm), then run:

```bash
cd ui
npm install
npm run start
```

UI runs at http://localhost:3000

## Next

- Continue with [Getting Started](./03-getting-started.md).
- If you are upgrading an existing setup, use [Update Existing Installation](./02-update-existing-installation.md).
