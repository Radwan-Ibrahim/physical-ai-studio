# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
# ruff: file-ignore[implicit-namespace-package]

"""Start Physical AI Studio from the Windows (MSIX) package and open it in the browser.

The package runs ``python.exe -I -X utf8 -m physicalai_studio_launcher``. The
console window shows the server log; closing it, or Ctrl+C, stops Studio.
"""

from __future__ import annotations

import ctypes
import os
import sys
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path

from cli.serve import start_server
from settings import get_default_storage_dir, get_settings

# Set once the browser was opened, so a server restart (which re-runs this module) does not open another tab.
_BROWSER_OPENED = "PHYSICALAI_LAUNCHER_BROWSER_OPENED"
_READY_TIMEOUT_S = 300.0


def _studio_url(host: str, port: int) -> str:
    browse_host = "127.0.0.1" if host in {"0.0.0.0", "::"} else host  # ruff: ignore[hardcoded-bind-all-interfaces]
    return f"http://{browse_host}:{port}"


def _is_serving(url: str) -> bool:
    try:
        with urllib.request.urlopen(f"{url}/api/system/info", timeout=2):  # ruff: ignore[suspicious-url-open-usage]
            return True
    except (urllib.error.URLError, OSError):
        return False


def _open_when_ready(url: str) -> None:
    deadline = time.monotonic() + _READY_TIMEOUT_S
    while time.monotonic() < deadline:
        if _is_serving(url):
            webbrowser.open(url)
            return
        time.sleep(1.0)


def main() -> int:
    """Run the Studio server, opening the UI once it answers.

    Returns:
        Process exit code.
    """
    app_dir = Path(sys.executable).resolve().parent.parent
    # torchcodec finds FFmpeg's DLLs through PATH; it is first loaded inside start_server.
    os.environ["PATH"] = os.pathsep.join([str(app_dir / "ffmpeg" / "bin"), os.environ.get("PATH", "")])
    os.environ.setdefault("PYTHONUNBUFFERED", "1")

    # The package directory is read-only; give relative writes somewhere to land.
    work_dir = get_default_storage_dir()
    work_dir.mkdir(parents=True, exist_ok=True)
    os.chdir(work_dir)

    settings = get_settings()
    url = _studio_url(settings.host, settings.port)
    if os.environ.get(_BROWSER_OPENED) is None:
        if _is_serving(url):
            sys.stdout.write(f"Physical AI Studio is already running at {url}\n")
            webbrowser.open(url)
            return 0
        os.environ[_BROWSER_OPENED] = "1"
        threading.Thread(target=_open_when_ready, args=(url,), daemon=True).start()

    if sys.platform == "win32":
        ctypes.windll.kernel32.SetConsoleTitleW(f"Physical AI Studio - {url}")
    sys.stdout.write(f"Starting Physical AI Studio at {url} (close this window to stop it)\n")

    start_server(settings.host, settings.port)
    return 0


if __name__ == "__main__":
    sys.exit(main())
