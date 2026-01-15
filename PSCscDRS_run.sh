#!/usr/bin/env bash
set -euo pipefail

echo ">>> RUNNING FULL PSC-scDRS PIPELINE"
echo

# Absolute directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If this script lives in <repo>/scripts/, repo root is one level up.
# If it lives directly in <repo>/, repo root is SCRIPT_DIR.
REPO_DIR="$(cd "$SCRIPT_DIR" && pwd)"
if [[ -d "$SCRIPT_DIR/bin" ]]; then
  # script is probably at repo root (repo/bin exists)
  REPO_DIR="$SCRIPT_DIR"
elif [[ -d "$SCRIPT_DIR/../bin" ]]; then
  # script is probably inside scripts/ (repo/bin exists one level up)
  REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  echo "ERROR: Could not locate repo root (bin/ not found)."
  echo "SCRIPT_DIR=$SCRIPT_DIR"
  exit 1
fi

BIN_DIR="$REPO_DIR/bin"

# Standard project dirs (adjust/add if you use more)
OUT_DIR="$REPO_DIR/output"
DATA_DIR="$REPO_DIR/data"
MAGMA_DIR="$REPO_DIR/magma"
LOG_DIR="$OUT_DIR/logs"

mkdir -p "$OUT_DIR" "$LOG_DIR"

# Export for ALL downstream bash + python steps (so no /home vs /work hardcoding)
export REPO_DIR BIN_DIR OUT_DIR DATA_DIR MAGMA_DIR

# Optional: helpful debug print (keeps invisible chars visible)
printf 'REPO_DIR=[%q]\nBIN_DIR=[%q]\nOUT_DIR=[%q]\nDATA_DIR=[%q]\nMAGMA_DIR=[%q]\n' \
  "$REPO_DIR" "$BIN_DIR" "$OUT_DIR" "$DATA_DIR" "$MAGMA_DIR"
echo

run_py () {
  local script="$1"
  echo ">>> $script"
  python3 "$BIN_DIR/$script" 2>&1 | tee "$LOG_DIR/${script%.py}.log"
  echo
}

run_sh () {
  local script="$1"
  echo ">>> $script"
  bash "$BIN_DIR/$script" 2>&1 | tee "$LOG_DIR/${script%.sh}.log"
  echo
}

echo ">>> [1/7] stp1_generate_input_file_for_BCFtools.py"
run_py "stp1_generate_input_file_for_BCFtools.py"

echo ">>> [2/7] stp2_generate_rsIDs_with_BCFtools.sh"
run_sh "stp2_generate_rsIDs_with_BCFtools.sh"

echo ">>> [3/7] stp3_generate_input_file_for_MAGMA.py"
run_py "stp3_generate_input_file_for_MAGMA.py"

echo ">>> [4/7] stp4_MAGMA_genebased_test.sh"
run_sh "stp4_MAGMA_genebased_test.sh"

echo ">>> [5/7] stp5_generate_input_file_for_scDRS.py"
run_py "stp5_generate_input_file_for_scDRS.py"

echo ">>> [6/7] stp6_scDRS.py"
run_py "stp6_scDRS.py"

echo ">>> [7/7] stp7_scDRS_result_evaluation.py"
run_py "stp7_scDRS_result_evaluation.py"

echo ">>> PIPELINE FINISHED SUCCESSFULLY"
