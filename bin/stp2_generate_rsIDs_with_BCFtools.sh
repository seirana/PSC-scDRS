#!/usr/bin/env bash
set -euo pipefail

# Prefer paths exported by PSC_scDRS_run.sh
# Fallback: infer repo root as parent of this script (assumes script is in <repo>/bin/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUT_DIR="${OUT_DIR:-$REPO_DIR/output}"

# Inputs/outputs
input_vcf="$OUT_DIR/bcf_variants.vcf"
output_vcf_gz="$OUT_DIR/bcf_variants.vcf.gz"
annotated_vcf="$OUT_DIR/variants_with_rsID.vcf"

# dbSNP path (inside repo by default)
DBSNP_VCF="${DBSNP_VCF:-$REPO_DIR/vcf/00-All.vcf.gz}"

# ---- Checks ----
command -v bgzip >/dev/null 2>&1 || { echo "ERROR: bgzip not found (install tabix/htslib)."; exit 1; }
command -v bcftools >/dev/null 2>&1 || { echo "ERROR: bcftools not found."; exit 1; }

[ -f "$input_vcf" ] || { echo "ERROR: Input VCF not found: $input_vcf"; exit 1; }
[ -f "$DBSNP_VCF" ] || { echo "ERROR: dbSNP VCF not found: $DBSNP_VCF"; exit 1; }

mkdir -p "$OUT_DIR"

# ---- Work ----
bgzip -f -c "$input_vcf" > "$output_vcf_gz"
bcftools index -t "$output_vcf_gz"

# Annotate rsIDs from dbSNP (ID column)
bcftools annotate -a "$DBSNP_VCF" -c ID "$output_vcf_gz" -o "$annotated_vcf"

echo "Wrote: $annotated_vcf"
