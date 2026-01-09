
#!/usr/bin/env bash
set -euo pipefail

echo ">>> RUNNING FULL PSC-scDRS PIPELINE"
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"

### === STEP 1: Python ===
echo ">>> [1/7] stp1_generate_input_file_for_BCFtools.py"
python3 "$BIN_DIR/stp1_generate_input_file_for_BCFtools.py"
echo

### === STEP 2: Bash ===
echo ">>> [2/7] stp2_generate_rsIDs_with_BCFtools.sh"
bash "$BIN_DIR/stp2_generate_rsIDs_with_BCFtools.sh"
echo

### === STEP 3: Python ===
echo ">>> [3/7] stp3_generate_input_file_for_MAGMA.py"
python3 "$BIN_DIR/stp3_generate_input_file_for_MAGMA.py"
echo

### === STEP 4: Bash ===
echo ">>> [4/7] stp4_MAGMA_genebased_test.sh"
bash "$BIN_DIR/stp4_MAGMA_genebased_test.sh"
echo

### === STEP 5: Python ===
echo ">>> [5/7] stp5_generate_input_file_for_scDRS.py"
python3 "$BIN_DIR/stp5_generate_input_file_for_scDRS.py"
echo

### === STEP 6: Python ===
echo ">>> [6/7] stp6_scDRS.py"
python3 "$BIN_DIR/stp6_scDRS.py"
echo

### === STEP 7: Python ===
echo ">>> [7/7] stp7_scDRS_result_evaluation.py"
python3 "$BIN_DIR/stp7_scDRS_result_evaluation.py"
echo

echo ">>> PIPELINE FINISHED SUCCESSFULLY"
