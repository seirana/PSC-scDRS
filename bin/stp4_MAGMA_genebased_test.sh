#==============================================================================================================
# This program applies MAGMA gene-based test on data
# input:
#	N=5023 equal to the all samples in the study, cases and controls
#	"$HOME/PSC-scDRS/output/files_for_MAGMA.txt"
#	"$HOME/PSC-scDRS/output/files_for_step2.txt"
#	"$HOME/PSC-scDRS/output/files_step1.genes.annot"
# output:
#	"$HOME/PSC-scDRS/output/files_step1"
#	"$HOME/PSC-scDRS/output/files_step2"
#==============================================================================================================
#!/bin/bash

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT_DIR="$REPO_DIR/output"
MAGMA_DIR="$REPO_DIR/magma"

annot_file="$OUT_DIR/files_for_MAGMA.txt"
step1_out="$OUT_DIR/files_step1"
step2_pval="$OUT_DIR/files_for_step2.txt"
step1_genes_annot="$OUT_DIR/files_step1.genes.annot"
step2_out="$OUT_DIR/files_step2"

GENE_LOC="$MAGMA_DIR/NCBI38.gene.loc"
BFILE="$MAGMA_DIR/g1000_eur"

# Safety checks (important)
[ -f "$annot_file" ] || { echo "Missing: $annot_file"; exit 1; }
[ -f "$GENE_LOC" ] || { echo "Missing: $GENE_LOC"; exit 1; }
[ -f "$BFILE.bed" ] || { echo "Missing: $BFILE.* (bed/bim/fam)"; exit 1; }
[ -f "$step2_pval" ] || { echo "Missing: $step2_pval"; exit 1; }

magma --annotate \
  --snp-loc "$annot_file" \
  --gene-loc "$GENE_LOC" \
  --out "$step1_out"

magma --bfile "$BFILE" \
  --pval "$step2_pval" N=5023 \
  --gene-annot "$step1_genes_annot" \
  --out "$step2_out"
