#========================================================================
#input:
# 	"$HOME/PSC-scDRS/output/bcf_variants.vcf
#	"$HOME/00-All.vcf.gz
# output:
#	"$HOME/PSC-scDRS/output/bcf_variants.vcf.gz
#	"$HOME/PSC-scDRS/output/variants_with_rsID.vcf
#========================================================================
##!/bin/bash

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"   # if this script is in bin/
# If stp2 is NOT in bin/, set REPO_DIR="$SCRIPT_DIR" instead.

input_vcf="$REPO_DIR/output/bcf_variants.vcf"
output_vcf="$REPO_DIR/output/bcf_variants.vcf.gz"
annotated_vcf="$REPO_DIR/output/variants_with_rsID.vcf"

DBSNP_VCF="$REPO_DIR/vcf/00-All.vcf.gz"    # if you store dbSNP inside repo/vcf
# If you store dbSNP outside repo (e.g. ~/vcf), point to it explicitly.

if [ ! -f "$input_vcf" ]; then
  echo "File does not exist: $input_vcf"
  exit 1
fi

if [ ! -f "$DBSNP_VCF" ]; then
  echo "dbSNP VCF not found: $DBSNP_VCF"
  exit 1
fi

bgzip -f -c "$input_vcf" > "$output_vcf"
bcftools index -t "$output_vcf"
bcftools annotate -a "$DBSNP_VCF" -c ID "$output_vcf" -o "$annotated_vcf"
echo "Wrote: $annotated_vcf"
