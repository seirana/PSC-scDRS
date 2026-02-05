#!/usr/bin/env bash
set -euo pipefail

echo ">>> RUNNING FULL PSC-scDRS PIPELINE"
echo

# Absolute directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect repo root
REPO_DIR=""
if [[ -d "$SCRIPT_DIR/bin" ]]; then
  REPO_DIR="$SCRIPT_DIR"
elif [[ -d "$SCRIPT_DIR/../bin" ]]; then
  REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  echo "ERROR: Could not locate repo root (bin/ not found)."
  echo "SCRIPT_DIR=$SCRIPT_DIR"
  exit 1
fi

BIN_DIR="$REPO_DIR/bin"
OUT_DIR="$REPO_DIR/output"
DATA_DIR="$REPO_DIR/data"
MAGMA_DIR="$REPO_DIR/magma"
LOG_DIR="$OUT_DIR/logs"

mkdir -p "$OUT_DIR" "$LOG_DIR"

# Export for downstream scripts
export REPO_DIR BIN_DIR OUT_DIR DATA_DIR MAGMA_DIR

# Prefer repo-local venv python if present (matches setup_dependencies.sh)
PYTHON="python3"
if [[ -x "$REPO_DIR/pythonENV/bin/python" ]]; then
  PYTHON="$REPO_DIR/pythonENV/bin/python"
elif [[ -f "$REPO_DIR/pythonENV/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_DIR/pythonENV/bin/activate"
  PYTHON="python3"
fi
export PYTHON

# Ensure repo-local tools are used (matches setup_dependencies.sh)
export PATH="$REPO_DIR/magma:$REPO_DIR/bcftools:$REPO_DIR/htslib:$PATH"
hash -r

need_cmd () {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Required tool '$1' not found in PATH."
    echo "PATH=$PATH"
    exit 1
  }
}

# Hard requirements (since setup builds/provides these)
need_cmd "$PYTHON"
need_cmd bcftools
need_cmd bgzip
need_cmd tabix
need_cmd magma

# -----------------------------
# Preflight: verify critical inputs (prevents PersonA-type failures)
# -----------------------------
echo ">>> Preflight: checking critical input files"

DBSNP_VCF="$REPO_DIR/vcf/00-All.vcf.gz"
DBSNP_TBI="$REPO_DIR/vcf/00-All.vcf.gz.tbi"

test -s "$DBSNP_VCF" || { echo "ERROR: Missing dbSNP VCF: $DBSNP_VCF"; exit 1; }

# BGZF integrity check (stronger / more relevant than gzip -t here)
bgzip -t "$DBSNP_VCF" || { echo "ERROR: dbSNP VCF corrupted/truncated (BGZF test failed): $DBSNP_VCF"; exit 1; }

# Ensure bcftools can parse header (detects subtle corruption)
bcftools view -h "$DBSNP_VCF" >/dev/null || { echo "ERROR: bcftools cannot read dbSNP VCF: $DBSNP_VCF"; exit 1; }

# Setup script rebuilds index; here we enforce presence (or rebuild if missing)
if [[ ! -s "$DBSNP_TBI" ]]; then
  echo ">>> dbSNP index missing, creating: $DBSNP_TBI"
  tabix -p vcf "$DBSNP_VCF" || { echo "ERROR: Failed to index dbSNP VCF"; exit 1; }
fi

echo ">>> Preflight OK"
echo

# Helpful debug print
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
