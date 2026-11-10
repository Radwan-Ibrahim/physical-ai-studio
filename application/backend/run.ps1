# Windows counterpart of run.sh: start the backend from a uv-synced checkout.
param(
    [string]$Command = "serve",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)
$ErrorActionPreference = "Stop"
$env:PYTHONUNBUFFERED = "1"
Push-Location $PSScriptRoot
try {
    uv run --no-sync physicalai-studio $Command @Arguments
} finally {
    Pop-Location
}
