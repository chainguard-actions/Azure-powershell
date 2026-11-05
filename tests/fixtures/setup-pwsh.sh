#!/usr/bin/env bash
# Ensure PowerShell (pwsh) is available and a minimal fake "Az" module (version
# 1.0.0) is discoverable, so the Azure PowerShell action can run under act
# without downloading the real (huge) Az module.
set -euo pipefail

PWSH_VERSION="7.4.6"

if ! command -v pwsh >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64|amd64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "unsupported arch $(uname -m)"; exit 1 ;;
  esac
  DEST="${RUNNER_TEMP:-/tmp}/pwsh-${PWSH_VERSION}"
  mkdir -p "$DEST"
  URL="https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-${ARCH}.tar.gz"
  echo "Downloading $URL"
  curl -fsSL "$URL" -o "${DEST}.tar.gz"
  tar -xzf "${DEST}.tar.gz" -C "$DEST"
  chmod +x "$DEST/pwsh"
  export PATH="$DEST:$PATH"
  echo "$DEST" >> "$GITHUB_PATH"
fi

# pwsh needs ICU unless globalization-invariant mode is enabled.
if ! ldconfig -p 2>/dev/null | grep -q libicu; then
  export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
  echo "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1" >> "$GITHUB_ENV"
fi

pwsh -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'

make_fake_az() {
  local root="$1"
  mkdir -p "$root/Az/1.0.0"
  pwsh -NoLogo -NoProfile -NonInteractive -Command \
    "New-ModuleManifest -Path '$root/Az/1.0.0/Az.psd1' -ModuleVersion '1.0.0' -Description 'fake Az for tests'"
}

# 1) User module path, so "Get-Module Az -ListAvailable" finds it (azPSVersion: latest).
USER_MODULES="$(pwsh -NoLogo -NoProfile -NonInteractive -Command '($env:PSModulePath -split [IO.Path]::PathSeparator)[0]')"
echo "User module path: $USER_MODULES"
make_fake_az "$USER_MODULES"

# 2) "az_1.0.0" folder in every candidate default install folder the action may
#    pick (/usr/share, RUNNER_TOOL_CACHE, cwd), so a pinned version 1.0.0 is
#    resolved from the local folder instead of being downloaded.
for cand in /usr/share "${RUNNER_TOOL_CACHE:-}" "$PWD"; do
  if [ -n "$cand" ] && [ -d "$cand" ] && [ -w "$cand" ]; then
    make_fake_az "$cand/az_1.0.0"
    echo "Created fake Az 1.0.0 under $cand/az_1.0.0"
  fi
done
