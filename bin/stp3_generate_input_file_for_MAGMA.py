#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: seirana

This program generates files needed for the MAGMA gene-based test.

input:
    <repo>/output/variants_with_rsID.vcf
    <repo>/data/sampleWES.zip
output:
    <repo>/output/files_for_step2.txt
    <repo>/output/files_for_MAGMA.txt
"""

import os
import sys
from pathlib import Path

import pandas as pd


def get_paths() -> tuple[Path, Path, Path, Path]:
    """
    Prefer env vars exported by PSC_scDRS_run.sh:
      REPO_DIR, BIN_DIR, OUT_DIR, DATA_DIR
    Fallback: infer repo as parent of this script's directory (bin/ -> repo/)
    """
    repo_env = os.environ.get("REPO_DIR")
    bin_env = os.environ.get("BIN_DIR")
    out_env = os.environ.get("OUT_DIR")
    data_env = os.environ.get("DATA_DIR")

    if repo_env:
        repo_dir = Path(repo_env).resolve()
        bin_dir = Path(bin_env).resolve() if bin_env else (repo_dir / "bin")
        out_dir = Path(out_env).resolve() if out_env else (repo_dir / "output")
        data_dir = Path(data_env).resolve() if data_env else (repo_dir / "data")
        return repo_dir, bin_dir, out_dir, data_dir

    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent
    bin_dir = repo_dir / "bin"
    out_dir = repo_dir / "output"
    data_dir = repo_dir / "data"
    return repo_dir, bin_dir, out_dir, data_dir


repo_dir, bin_dir, out_dir, data_dir = get_paths()
out_dir.mkdir(parents=True, exist_ok=True)

# Make sure we can import read_write from the repo's bin/
sys.path.insert(0, str(bin_dir))
import read_write as rw  # noqa: E402


# -----------------------
# Part 1: files_for_MAGMA
# -----------------------
vcf_file = out_dir / "variants_with_rsID.vcf"
if not vcf_file.exists():
    raise FileNotFoundError(f"VCF file not found: {vcf_file}")

header_cols = None
with open(vcf_file, "rt", encoding="utf-8") as f:
    for line in f:
        if line.startswith("#CHROM"):
            header_cols = line.strip().lstrip("#").split("\t")
            break

if header_cols is None:
    raise ValueError(f"Could not find VCF header line starting with #CHROM in: {vcf_file}")

vcf = pd.read_csv(
    vcf_file,
    sep="\t",
    comment="#",
    header=None,
    names=header_cols
)

# Some VCFs use '#CHROM' or 'CHROM' depending on how you parse.
# After lstrip('#'), it should be 'CHROM'.
required = {"ID", "CHROM", "POS"}
missing = required - set(vcf.columns)
if missing:
    raise ValueError(f"VCF is missing columns {missing}. Found columns: {list(vcf.columns)}")

data_for_MAGMA = vcf.loc[:, ["ID", "CHROM", "POS"]].copy()
data_for_MAGMA.columns = ["Variant name", "CHROM", "GENPOS"]

magma_out = out_dir / "files_for_MAGMA.txt"
rw.write_txt(str(magma_out), data_for_MAGMA, " ", False)


# -----------------------
# Part 2: files_for_step2
# -----------------------
wes_file = data_dir / "sampleWES.zip"
if not wes_file.exists():
    raise FileNotFoundError(f"WES input not found: {wes_file}")

df = pd.read_csv(
    wes_file,
    sep=r"\s+",
    compression="zip"
)

if "MarkerID" not in df.columns or "p.value" not in df.columns:
    raise ValueError(f"Expected columns MarkerID and p.value in {wes_file}. Found: {list(df.columns)}")

data_for_step2 = df.loc[:, ["MarkerID", "p.value"]].copy()

# Replace MarkerID with rsID from annotated VCF
data_for_step2.loc[:, "MarkerID"] = vcf.loc[:, "ID"].values
data_for_step2.columns = ["SNP id", "p-value"]

step2_out = out_dir / "files_for_step2.txt"
rw.write_txt(str(step2_out), data_for_step2, "\t", False)

print(f"Wrote: {magma_out}")
print(f"Wrote: {step2_out}")
