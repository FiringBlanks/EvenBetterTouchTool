#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
"$project_dir/install.sh"
printf '\nInstallation finished. You can close this Terminal window.\n'
