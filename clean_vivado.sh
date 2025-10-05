#!/usr/bin/env bash
set -euo pipefail

# Project name must match bring-up script
PROJ_NAME="bringup_led_uart"
PROJ_DIR="fpga/proj/${PROJ_NAME}"

echo "About to delete generated Vivado project directory:"
echo "  ${PROJ_DIR}"
read -r -p "Continue? [y/N] " ans
[[ "${ans,,}" == "y" ]] || { echo "Aborted."; exit 0; }

# Remove ONLY generated stuff; source/scripts/constraints stay untouched
rm -rf "${PROJ_DIR}"

# Optional: prune common Vivado droppings in the repo root (created when running vivado here)
rm -rf .Xil webtalk* usage_statistics_webtalk.* *.jou *.log *.str

echo "Clean complete."
