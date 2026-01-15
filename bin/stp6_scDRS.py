#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Seirana

Runs scDRS for a given trait and tissue.

input:
    <repo>/data/{tissue}.h5ad   (or <repo>/data/HumanLiverHealthyscRNAseqData.zip as source)
    <repo>/output/{trait}_geneset.gs

output:
    <repo>/output/{tissue}_cov.tsv
    <repo>/output/{trait}.full_score.gz  (and other scDRS outputs)
    <repo>/bin/figures/cell_ontology_classes_{tissue}.png
    <repo>/bin/figures/associated_cells_of_{tissue}_to_{trait}.png
"""

import os
import sys
import zipfile
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import scanpy as sc
import subprocess

import scdrs_

warnings.filterwarnings("ignore")


def get_paths() -> tuple[Path, Path, Path, Path]:
    """
    Prefer env vars exported by PSC_scDRS_run.sh:
      REPO_DIR, BIN_DIR, DATA_DIR, OUT_DIR
    Fallback: infer repo as parent of this script's directory (bin/ -> repo/)
    """
    repo_env = os.environ.get("REPO_DIR")
    bin_env = os.environ.get("BIN_DIR")
    data_env = os.environ.get("DATA_DIR")
    out_env = os.environ.get("OUT_DIR")

    if repo_env:
        repo_dir = Path(repo_env).resolve()
        bin_dir = Path(bin_env).resolve() if bin_env else (repo_dir / "bin")
        data_dir = Path(data_env).resolve() if data_env else (repo_dir / "data")
        out_dir = Path(out_env).resolve() if out_env else (repo_dir / "output")
        return repo_dir, bin_dir, data_dir, out_dir

    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent
    bin_dir = repo_dir / "bin"
    data_dir = repo_dir / "data"
    out_dir = repo_dir / "output"
    return repo_dir, bin_dir, data_dir, out_dir


def find_compute_score_py() -> Path:
    """
    Find scDRS compute_score.py.
    Priority:
      1) env var SCDRS_DIR (expects compute_score.py inside it)
      2) <repo>/scDRS/compute_score.py
      3) ~/scDRS/compute_score.py
    """
    scdrs_dir = os.environ.get("SCDRS_DIR")
    candidates = []

    if scdrs_dir:
        candidates.append(Path(scdrs_dir) / "compute_score.py")

    # common locations
    repo_dir, _, _, _ = get_paths()
    candidates.append(repo_dir / "scDRS" / "compute_score.py")
    candidates.append(Path.home() / "scDRS" / "compute_score.py")

    for c in candidates:
        if c.exists():
            return c.resolve()

    raise FileNotFoundError(
        "Could not find scDRS compute_score.py. "
        "Set env var SCDRS_DIR to the folder containing compute_score.py, "
        "or place scDRS under <repo>/scDRS/."
    )


# -------------------------
# User-configurable settings
# -------------------------
trait = os.environ.get("TRAIT", "PSC")
tissue = os.environ.get("TISSUE", "Liver")
hm = os.environ.get("SCDRS_SPECIES", "hsapiens")  # scDRS species string

repo_dir, bin_dir, data_dir, out_dir = get_paths()
out_dir.mkdir(parents=True, exist_ok=True)

fig_dir = bin_dir / "figures"
fig_dir.mkdir(parents=True, exist_ok=True)

# Make scanpy save figures exactly where we want
sc.settings.figdir = str(fig_dir)


# -------------------------
# Prepare h5ad (extract if needed)
# -------------------------
zip_path = data_dir / "HumanLiverHealthyscRNAseqData.zip"
target_h5ad = data_dir / f"{tissue}.h5ad"

if not target_h5ad.exists():
    if not zip_path.exists():
        raise FileNotFoundError(
            f"Neither {target_h5ad} nor zip source {zip_path} exists."
        )

    with zipfile.ZipFile(zip_path) as z:
        h5ads = [n for n in z.namelist() if n.endswith(".h5ad")]
        if not h5ads:
            raise ValueError(f"No .h5ad found inside: {zip_path}")

        # choose first .h5ad
        h5ad_inside = h5ads[0]

        extracted_path = Path(z.extract(h5ad_inside, data_dir)).resolve()

        # If extracted path equals target, fine; else move/rename safely
        if extracted_path != target_h5ad:
            # If target exists now for some reason, don't overwrite silently
            if target_h5ad.exists():
                extracted_path.unlink(missing_ok=True)
            else:
                extracted_path.replace(target_h5ad)

print(f"Using h5ad: {target_h5ad}")

adata = sc.read_h5ad(target_h5ad)

# -------------------------
# Build covariates file
# -------------------------
cell_id = adata.obs.index.to_series().reset_index(drop=True).to_frame(name="cell_id")

if "n_genes" not in adata.obs.columns:
    raise ValueError("Expected adata.obs['n_genes'] to exist, but it is missing.")

n_genes = adata.obs.loc[:, ["n_genes"]].reset_index(drop=True)

const = pd.DataFrame({"const": np.ones(len(cell_id), dtype=int)})

cov = pd.concat([cell_id, n_genes, const], axis=1)
cov_file = out_dir / f"{tissue}_cov.tsv"
cov.to_csv(cov_file, sep="\t", index=False)
print(f"Wrote: {cov_file}")

# -------------------------
# Run scDRS compute_score.py
# -------------------------
compute_score_py = find_compute_score_py()

gs_file = out_dir / f"{trait}_geneset.gs"
if not gs_file.exists():
    raise FileNotFoundError(f"Geneset file not found: {gs_file}")

args = [
    "--h5ad_file", str(target_h5ad),
    "--h5ad_species", hm,
    "--cov_file", str(cov_file),
    "--gs_file", str(gs_file),
    "--gs_species", "hsapiens",
    "--ctrl_match_opt", "mean_var",
    "--weight_opt", "vs",
    "--flag_raw_count", "False",
    "--n_ctrl", "1000",
    "--flag_return_ctrl_raw_score", "False",
    "--flag_return_ctrl_norm_score", "True",
    "--out_folder", str(out_dir),
]

# Use current python interpreter (venv-safe)
cmd = [sys.executable, str(compute_score_py)] + args
print("Running:", " ".join(cmd))
subprocess.run(cmd, check=True)

# scDRS typically writes <trait>.full_score.gz (trait comes from gs file TRAIT field)
full_score = out_dir / f"{trait}.full_score.gz"

# -------------------------
# Load scores + plots
# -------------------------
if full_score.exists():
    df_score = pd.read_csv(full_score, sep="\t", index_col=0)
    if "norm_score" in df_score.columns:
        adata.obs[trait] = df_score["norm_score"]
    else:
        print(f"WARNING: norm_score not found in {full_score}; available: {list(df_score.columns)}")

    sc.set_figure_params(figsize=[2.5, 2.5], dpi=150)

    # 1) cell ontology classes
    sc.pl.umap(
        adata,
        color="cell_ontology_class",
        ncols=1,
        color_map="RdBu_r",
        vmin=-5,
        vmax=5,
        show=False,
        save=f"cell_ontology_classes_{tissue}.png",
    )

    # 2) associated cells for trait
    sc.pl.umap(
        adata,
        color=[trait],
        color_map="RdBu_r",
        vmin=-5,
        vmax=5,
        s=20,
        show=False,
        save=f"associated_cells_of_{tissue}_to_{trait}.png",
    )

    print(f"Figures saved to: {fig_dir}")

    # downstream group analysis
    scdrs_.perform_downstream(
        h5ad_file=str(target_h5ad),
        score_file=str(full_score),
        out_folder=str(out_dir),
        group_analysis="cell_ontology_class",
    )
else:
    print(f"WARNING: scDRS score file not found: {full_score}")
