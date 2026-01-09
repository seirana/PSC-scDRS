#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: seirana

This program generates files needed for the MAGMA gene-based test.

input:
    ./PSC-scDRS/output/variants_with_rsID.vcf 
    ./PSC-scDRS/data/sample_single_marker_test.zip
output:
    ./PSC-scDRS/output/files_for_step2.txt
    ./PSC-scDRS/output/files_for_MAGMA.txt
"""

import sys
from pathlib import Path
sys.path.append(str(Path.home()/"PSC-scDRS"/"bin"))
import read_write as rw
import pandas as pd
import sys


in_dir = Path.home()/"PSC-scDRS"/"output"
vcf_file =  in_dir/"variants_with_rsID.vcf"

header_line_idx = None
header_cols = None

with open(vcf_file, "rt") as f:
    for i, line in enumerate(f):
        if line.startswith("#CHROM"):
            header_line_idx = i
            header_cols = line.strip().lstrip("#").split("\t")
            break

vcf = pd.read_csv(
    vcf_file,
    sep="\t",
    comment="#",   # skips all lines starting with '#'
    header=None,   # no header line inside the data section
    names=header_cols
)

data_for_MAGMA = vcf.loc[:, ['ID', 'CHROM', 'POS']].copy()
data_for_MAGMA.columns = ['Variant name', 'CHROM', 'GENPOS']

out_dir = Path.home()/"PSC-scDRS"/"output"
file = str(out_dir/"files_for_MAGMA")
rw.write_txt(file, data_for_MAGMA, ' ', False)

# .............................................................................
in_dir = Path.home()/"PSC-scDRS"/"data"
file =  in_dir/"sampleWES.zip"
df = pd.read_csv(
    file,
    sep=r"\s+",
    compression="zip"
)

data_for_step2 = df.loc[:, ['MarkerID', 'p.value']].copy()
data_for_step2.loc[:, 'MarkerID'] = vcf.loc[:, 'ID']
data_for_step2.columns = ['SNP id', 'p-value']

out_dir = Path.home() /  "PSC-scDRS" / "output"
out_dir.mkdir(parents=True, exist_ok=True)

file = str(out_dir /"files_for_step2")
rw.write_txt(file, data_for_step2, '\t', False)
