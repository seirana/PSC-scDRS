
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

# -----------------------------
# Environment bootstrap (portable)
# -----------------------------

# Prefer repo-local venv python if present (no user edits required)
PYTHON="python3"
if [[ -x "$REPO_DIR/pythonENV/bin/python" ]]; then
  PYTHON="$REPO_DIR/pythonENV/bin/python"
elif [[ -f "$REPO_DIR/pythonENV/bin/activate" ]]; then
  # fallback: activate if present (helps if python exists but isn't executable for some reason)
  # shellcheck disable=SC1091
  source "$REPO_DIR/pythonENV/bin/activate"
  PYTHON="python3"
fi
export PYTHON

# Add repo-local tools to PATH (NO ~ hardcoding)
# This replaces: export PATH=~/PSC-scDRS/magma:~/PSC-scDRS/bcftools:~/PSC-scDRS/htslib:$PATH
export PATH="$REPO_DIR/magma:$REPO_DIR/bcftools:$REPO_DIR/htslib:$PATH"

need_cmd () {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Required tool '$1' not found in PATH."
    echo "PATH=$PATH"
    echo "Fix options:"
    echo "  - Install '$1' system-wide, OR"
    echo "  - Put it in the repo under one of: magma/ bcftools/ htslib/"
    exit 1
  }
}

# Fail fast (clear errors instead of later cryptic failures)
need_cmd "$PYTHON"
need_cmd bcftools
need_cmd magma
# If your step scripts use these, keep them strict; otherwise leave as warnings:
if ! command -v tabix >/dev/null 2>&1; then
  echo "WARNING: 'tabix' not found in PATH. If your pipeline uses tabix, install it or provide it under htslib/."
fi
if ! command -v bgzip >/dev/null 2>&1; then
  echo "WARNING: 'bgzip' not found in PATH. If your pipeline uses bgzip, install it or provide it under htslib/."
fi

# Optional: helpful debug print (keeps invisible chars visible)
printf 'REPO_DIR=[%q]\nBIN_DIR=[%q]\nOUT_DIR=[%q]\nDATA_DIR=[%q]\nMAGMA_DIR=[%q]\nPYTHON=[%q]\n' \
  "$REPO_DIR" "$BIN_DIR" "$OUT_DIR" "$DATA_DIR" "$MAGMA_DIR" "$PYTHON"
echo

run_py () {
  local script="$1"
  echo ">>> $script"
  "$PYTHON" "$BIN_DIR/$script" 2>&1 | tee "$LOG_DIR/${script%.py}.log"
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
