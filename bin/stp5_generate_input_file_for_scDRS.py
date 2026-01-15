#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Seirana

This program:
 1) Selects 1000 genes with the highest z-score, then finds approved gene names based on Entrez IDs.
 2) Generates a gene set list for the scDRS function.
 3) Generates a Manhattan plot of MAGMA gene-based analyses.
 4) Makes a list of genes with a significant p-value.

input:
    <repo>/output/files_step2.genes.out
    <repo>/data/magma_10kb_top1000_zscore.74_traits.rv1.gs

output:
    <repo>/output/zscore.csv
    <repo>/output/PSC_geneset.gs
    <repo>/output/gene_based_test.png
    <repo>/output/significant_genes_MAGMA.csv
"""

import os
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import requests


def get_paths() -> tuple[Path, Path, Path]:
    """
    Prefer env vars exported by PSC_scDRS_run.sh: REPO_DIR, OUT_DIR, DATA_DIR
    Fallback: infer repo as parent of this script's directory (bin/ -> repo/)
    """
    repo_env = os.environ.get("REPO_DIR")
    out_env = os.environ.get("OUT_DIR")
    data_env = os.environ.get("DATA_DIR")

    if repo_env:
        repo_dir = Path(repo_env).resolve()
        out_dir = Path(out_env).resolve() if out_env else (repo_dir / "output")
        data_dir = Path(data_env).resolve() if data_env else (repo_dir / "data")
        return repo_dir, out_dir, data_dir

    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent
    out_dir = repo_dir / "output"
    data_dir = repo_dir / "data"
    return repo_dir, out_dir, data_dir


def list_maker(df: pd.DataFrame) -> str:
    # df columns: gene_symbol, ZSTAT
    x_geneset = ""
    for i in range(len(df) - 1):
        c = round(float(df.iloc[i, 1]), 4)
        x_geneset += f"{df.iloc[i, 0]}:{c},"
    # last one (no trailing comma)
    x_geneset += f"{df.iloc[-1, 0]}:{df.iloc[-1, 1]}"
    return x_geneset


def entrez_to_symbol(entrez_ids, batch_size=1000):
    """
    Batch convert Entrez Gene IDs -> gene symbols using mygene.info.
    Returns dict: {entrez_id(str): symbol(str)}
    """
    entrez_ids = [str(x) for x in entrez_ids]
    out = {}

    url = "https://mygene.info/v3/gene"
    for i in range(0, len(entrez_ids), batch_size):
        chunk = entrez_ids[i:i + batch_size]
        r = requests.post(
            url,
            json={"ids": chunk, "fields": ["symbol"], "species": "human"},
            timeout=60,
        )
        r.raise_for_status()

        for rec in r.json():
            _id = str(rec.get("_id", ""))
            out[_id] = rec.get("symbol", "")

    return out


if __name__ == "__main__":

    repo_dir, out_dir, data_dir = get_paths()
    out_dir.mkdir(parents=True, exist_ok=True)

    magma_genes_out = out_dir / "files_step2.genes.out"
    if not magma_genes_out.exists():
        raise FileNotFoundError(f"Missing MAGMA output: {magma_genes_out}")

    df = pd.read_csv(magma_genes_out, sep=r"\s+")

    if "ZSTAT" not in df.columns:
        raise ValueError(f"ZSTAT column not found in {magma_genes_out}. Found: {list(df.columns)}")

    # top 1000 z-scores
    df_top = df.nlargest(1000, "ZSTAT").reset_index(drop=True).copy()
    df_top.loc[df_top["ZSTAT"] > 10, "ZSTAT"] = 10

    # Entrez IDs (first column)
    gene_ids = df_top.iloc[:, 0].astype(str).tolist()

    # Batch mapping
    mapping = entrez_to_symbol(gene_ids)

    gene_name = pd.DataFrame({"gene_symbol": [mapping.get(g, "") for g in gene_ids]})
    df_top = pd.concat([df_top, gene_name], axis=1)

    out_csv = out_dir / "zscore.csv"
    df_top.to_csv(out_csv, index=False)
    print("Saved:", out_csv)

    # -------------------------------------------------------------------------
    # Make PSC geneset (.gs) based on a template control gs file
    template_gs = data_dir / "magma_10kb_top1000_zscore.74_traits.rv1.gs"
    if not template_gs.exists():
        raise FileNotFoundError(f"Missing template geneset file: {template_gs}")

    cntrl = pd.read_csv(template_gs, sep="\t")
    geneset = cntrl.loc[[0], :].copy()
    geneset.index = range(len(geneset))
    geneset.loc[0, "TRAIT"] = "PSC"

    # Keep only mapped symbols
    df_genes = df_top.loc[:, ["gene_symbol", "ZSTAT"]].copy()
    df_genes = df_genes[df_genes["gene_symbol"].astype(str).str.len() > 0].reset_index(drop=True)

    if df_genes.empty:
        raise ValueError("All gene_symbol mappings are empty; cannot build PSC geneset.")

    geneset.loc[0, "GENESET"] = list_maker(df_genes)

    write_file = out_dir / "PSC_geneset.gs"
    geneset.to_csv(write_file, sep="\t", index=False)
    print("Saved:", write_file)

    # -------------------------------------------------------------------------
    # Manhattan plot
    df_manh = df.loc[:, ["CHR", "P"]].copy()
    df_manh["LOG10P"] = -np.log10(df_manh["P"])
    df_manh["ind"] = range(len(df_manh))

    df_manh["CHR"] = df_manh["CHR"].astype("category")
    df_grouped = df_manh.groupby("CHR")

    fig = plt.figure(figsize=(14, 8))
    ax = fig.add_subplot(111)

    colors = ["#7FC97F", "#FDC086"]  # keep your colors
    x_labels = []
    x_labels_pos = []

    for num, (name, group) in enumerate(df_grouped):
        group.plot(kind="scatter", x="ind", y="LOG10P",
                   color=colors[num % len(colors)], ax=ax)
        x_labels.append(name)
        x_labels_pos.append(group["ind"].iloc[-1] - (group["ind"].iloc[-1] - group["ind"].iloc[0]) / 2)

    ax.set_xticks(x_labels_pos)
    ax.set_xticklabels(x_labels)

    plt.axhline(y=5.58, color="gray", linestyle="--")
    ax.set_xlim([0, len(df_manh)])
    ax.set_ylim([0, int(df_manh["LOG10P"].max() + 1)])

    ax.set_xlabel("Chromosome")
    plt.ylabel("-log10p")
    plt.title("MAGMA gene-based test", fontsize=16, fontweight="bold", loc="center", pad=20)

    plot_file = out_dir / "gene_based_test.png"
    plt.savefig(str(plot_file), dpi=200, bbox_inches="tight")
    plt.close(fig)
    print("Saved:", plot_file)

    # -------------------------------------------------------------------------
    # Significant genes list
    # Use df_top (zscore.csv) and filter by P threshold
    if "P" not in df_top.columns or "CHR" not in df_top.columns:
        raise ValueError(f"Expected P and CHR in MAGMA genes output. Found: {list(df_top.columns)}")

    val_genes = df_top.loc[df_top["P"] <= 2.5e-6, ["gene_symbol", "CHR", "P"]].copy()
    val_genes = pd.concat([val_genes, pd.DataFrame({"Column": ["SAIGE"] * len(val_genes)})], axis=1)

    sig_out = out_dir / "significant_genes_MAGMA.csv"
    val_genes.to_csv(sig_out, index=False)
    print("Saved:", sig_out)
