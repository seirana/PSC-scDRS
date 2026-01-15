#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Seirana

This program generates a file in the desired format for the bcftools function.

input:
    <repo>/data/sampleWES.zip
output:
    <repo>/output/bcf_variants.vcf
"""

import os
import pandas as pd
from pathlib import Path


def get_repo_paths() -> tuple[Path, Path, Path]:
    """
    Prefer env vars exported by PSC_scDRS_run.sh:
      REPO_DIR, DATA_DIR, OUT_DIR
    Fallback: infer repo as parent of this script's directory (bin/ -> repo/)
    """
    repo_env = os.environ.get("REPO_DIR")
    data_env = os.environ.get("DATA_DIR")
    out_env = os.environ.get("OUT_DIR")

    if repo_env:
        repo_dir = Path(repo_env).resolve()
        data_dir = Path(data_env).resolve() if data_env else (repo_dir / "data")
        out_dir = Path(out_env).resolve() if out_env else (repo_dir / "output")
        return repo_dir, data_dir, out_dir

    # Fallback if run directly (assumes script is in <repo>/bin/)
    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent
    data_dir = repo_dir / "data"
    out_dir = repo_dir / "output"
    return repo_dir, data_dir, out_dir


repo_dir, data_dir, out_dir = get_repo_paths()

# --- Input / output files ---
in_file = data_dir / "sampleWES.zip"
out_dir.mkdir(parents=True, exist_ok=True)
out_file = out_dir / "bcf_variants.vcf"

if not in_file.exists():
    raise FileNotFoundError(f"Input file not found: {in_file}")

reg = pd.read_csv(
    in_file,
    sep=r"\s+",
    compression="zip"
)

reg["reg_index"] = range(len(reg))

# Safely remove 'chr' prefix if present (works for pandas versions that may not have .removeprefix)
third_col = reg.columns[2]
reg[third_col] = reg[third_col].astype(str).str.replace(r"^chr", "", regex=True)

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

with open(out_file, "w", encoding="utf-8") as f:
    f.write("##fileformat=VCFv4.2\n")
    bcf.to_csv(f, sep="\t", index=False)

print(f"Wrote: {out_file}")
