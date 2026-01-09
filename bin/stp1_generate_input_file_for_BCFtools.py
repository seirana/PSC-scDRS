#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Seirana

This program generates a file in the desired format for the bcftools function.

input: 
    './PSC-scDRS/data/sample_single_marker_test.zip'
output:
    ./PSC-scDRS/output/bcf_variants.vcf'
"""

import pandas as pd
from pathlib import Path

in_dir = Path.home()/"PSC-scDRS"

file = in_dir /"data/sampleWES.zip"
reg = pd.read_csv(
    file,
    sep=r"\s+",
    compression="zip"
)
reg["reg_index"] = range(len(reg))

third_col = reg.columns[2]
reg[third_col] = reg[third_col].astype(str).str.removeprefix("chr")

bcf = pd.DataFrame({
    "#CHROM": reg.iloc[:, 0],
    "POS": reg.iloc[:, 1],
    "ID": ".",
    "REF": reg.iloc[:, 3],
    "ALT": reg.iloc[:, 4],
    "QUAL": ".",
    "FILTER": ".",
    "INFO": "."
})

out_dir = Path.home()/"PSC-scDRS"/"output"
out_dir.mkdir(parents=True, exist_ok=True)


with open(out_dir / "bcf_variants.vcf", 'w') as f:
    f.write("##fileformat=VCFv4.2\n")
    bcf.to_csv(f, sep="\t", index=False)
