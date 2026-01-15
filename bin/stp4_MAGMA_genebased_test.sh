#!/usr/bin/env bash
set -euo pipefail

# Prefer paths exported by PSC_scDRS_run.sh
# Fallback: infer repo root as parent of this script (assumes script is in <repo>/bin/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

OUT_DIR="${OUT_DIR:-$REPO_DIR/output}"
MAGMA_DIR="${MAGMA_DIR:-$REPO_DIR/magma}"

mkdir -p "$OUT_DIR"

annot_file="$OUT_DIR/files_for_MAGMA.txt"
step1_out_prefix="$OUT_DIR/files_step1"
step2_pval="$OUT_DIR/files_for_step2.txt"
step1_genes_annot="$OUT_DIR/files_step1.genes.annot"
step2_out_prefix="$OUT_DIR/files_step2"

GENE_LOC="$MAGMA_DIR/NCBI38.gene.loc"
BFILE="$MAGMA_DIR/g1000_eur"

# ---- Checks ----
command -v magma >/dev/null 2>&1 || { echo "ERROR: magma not found in PATH."; exit 1; }

[ -f "$annot_file" ] || { echo "ERROR: Missing: $annot_file"; exit 1; }
[ -f "$GENE_LOC" ] || { echo "ERROR: Missing: $GENE_LOC"; exit 1; }
[ -f "$BFILE.bed" ] && [ -f "$BFILE.bim" ] && [ -f "$BFILE.fam" ] || {
  echo "ERROR: Missing: $BFILE.(bed/bim/fam)"
  exit 1
}
[ -f "$step2_pval" ] || { echo "ERROR: Missing: $step2_pval"; exit 1; }

# ---- Run MAGMA ----
magma --annotate \
  --snp-loc "$annot_file" \
  --gene-loc "$GENE_LOC" \
  --out "$step1_out_prefix"

magma --bfile "$BFILE" \
  --pval "$step2_pval" N=5023 \
  --gene-annot "$step1_genes_annot" \
  --out "$step2_out_prefix"

echo "Wrote MAGMA outputs with prefixes:"
echo "  $step1_out_prefix"
echo "  $step2_out_prefix"
