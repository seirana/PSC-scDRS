#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Seirana

This program:
  1) calculates the variables of log-threshold formula -> threshold = a + b / log10(cell_count)
  2) reads the result of scDRS analyses and reports associated cell-types

input:
  min_cell_count = 150
  up_threshold = 5
  factor = 100
  <repo>/output/{trait}.scdrs_group.cell_ontology_class

output:
  <repo>/output/log_threshold.png
  <repo>/output/{trait}_cell_association_with_{tissue}.csv
"""

import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from sympy import symbols, Eq, log, solve


def get_paths() -> tuple[Path, Path, Path]:
    """
    Prefer env vars exported by PSC_scDRS_run.sh:
      REPO_DIR, BIN_DIR, OUT_DIR
    Fallback: infer repo as parent of this script's directory (bin/ -> repo/)
    """
    repo_env = os.environ.get("REPO_DIR")
    bin_env = os.environ.get("BIN_DIR")
    out_env = os.environ.get("OUT_DIR")

    if repo_env:
        repo_dir = Path(repo_env).resolve()
        bin_dir = Path(bin_env).resolve() if bin_env else (repo_dir / "bin")
        out_dir = Path(out_env).resolve() if out_env else (repo_dir / "output")
        return repo_dir, bin_dir, out_dir

    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent
    bin_dir = repo_dir / "bin"
    out_dir = repo_dir / "output"
    return repo_dir, bin_dir, out_dir


repo_dir, bin_dir, out_dir = get_paths()
out_dir.mkdir(parents=True, exist_ok=True)

# Make sure we can import read_write from repo/bin
sys.path.insert(0, str(bin_dir))
import read_write as rw  # noqa: E402


def log_threshold(out_dirc: Path):
    a, b = symbols("a b")

    min_cell_count = 150
    up_threshold = 5

    factor = 100
    max_cell_count = min_cell_count * factor
    low_threshold = up_threshold / factor

    eq1 = Eq(a + b / log(min_cell_count, 10), up_threshold)
    eq2 = Eq(a + b / log(max_cell_count, 10), low_threshold)

    solution = solve((eq1, eq2), (a, b))
    a_fit, b_fit = solution[a], solution[b]

    def tr(x, a_=a_fit, b_=b_fit):
        return a_ + b_ / np.log10(x)

    x_values = np.logspace(2.1, 6, 100)
    y_values = np.maximum(tr(x_values), 1)

    fig = plt.figure(figsize=(8, 6))
    plt.plot(
        x_values,
        y_values,
        label=f"tr(x) = {float(a_fit):.2f} + {float(b_fit):.2f}/log10(x)",
        color="b",
    )
    plt.axhline(y=1, color="green", linestyle="--", label="minimum threshold")
    plt.xscale("log")
    plt.xlabel("Cell Count")
    plt.ylabel("Threshold (%)")
    plt.title("Logarithmic Threshold Model")
    plt.grid(True, which="both", ls="--", linewidth=0.5)
    plt.legend()

    plot_path = out_dirc / "log_threshold.png"
    plt.savefig(str(plot_path), dpi=200, bbox_inches="tight")
    plt.close(fig)
    print("Saved:", plot_path)

    return float(a_fit), float(b_fit)


def read_scdrs_group_file(trait: str, out_dirc: Path) -> pd.DataFrame:
    """
    Reads: <out_dir>/{trait}.scdrs_group.cell_ontology_class
    This is typically a TSV.
    """
    fpath = out_dirc / f"{trait}.scdrs_group.cell_ontology_class"
    if not fpath.exists():
        return pd.DataFrame()

    # Usually scDRS outputs tab-separated text with header
    df = pd.read_csv(fpath, sep="\t")
    if "group" in df.columns:
        df["group"] = df["group"].astype(str).str.replace(",", "_", regex=False)
    return df


def float_to_number(db: pd.DataFrame) -> pd.DataFrame:
    for col in ["n_fdr_0.05", "assoc_mcp", "hetero_mcp", "n_cell"]:
        if col in db.columns:
            db[col] = db[col].replace({"": 0}).astype(float)
    return db


if __name__ == "__main__":

    # You can override these from the run script if you want later:
    trait = os.environ.get("TRAIT", "PSC")
    tissue = os.environ.get("TISSUE", "Liver")

    a, b = log_threshold(out_dir)

    columns = [
        "tissue",
        "trait",
        "cell",
        "n cell",
        "assoc.",
        "hetero.",
        "percentage of associated cells with fdr. 0.05",
        "threshold",
        "significancy",
    ]

    dig = 5
    final_results = pd.DataFrame(columns=columns)

    db = read_scdrs_group_file(trait, out_dir)
    if db.empty:
        print(f"WARNING: No scDRS group file found for trait={trait} in {out_dir}")
        sys.exit(0)

    required_cols = {"group", "n_cell", "assoc_mcp", "hetero_mcp", "n_fdr_0.05"}
    missing = required_cols - set(db.columns)
    if missing:
        raise ValueError(f"Missing columns {missing} in scDRS group file. Found: {list(db.columns)}")

    db = float_to_number(db)

    for d in range(len(db)):
        cell = str(db.loc[d, "group"])
        n_cell = float(db.loc[d, "n_cell"])
        assoc = round(float(db.loc[d, "assoc_mcp"]), dig)
        hetero = round(float(db.loc[d, "hetero_mcp"]), dig)
        n_fdr = float(db.loc[d, "n_fdr_0.05"])

        pct = round((n_fdr / n_cell) * 100, dig) if n_cell > 0 else 0.0

        # threshold only meaningful if n_fdr > 0
        thr = None
        signif = 0
        if n_fdr > 0 and n_cell > 0:
            thr = max(a + (b / np.log10(n_cell)), 0.005)
            signif = 1 if pct >= thr else 0
        else:
            thr = 0.0

        # your filtering logic
        if (n_cell >= 150 and assoc <= 0.05 and n_fdr > 0):
            final_results.loc[len(final_results)] = [
                tissue,
                trait,
                cell,
                int(n_cell),
                assoc,
                hetero,
                pct,
                thr,
                signif,
            ]

    out_csv = out_dir / f"{trait}_cell_association_with_{tissue}.csv"
    rw.write_csv(final_results, str(out_csv.with_suffix("")))  # rw likely appends .csv itself
    # If rw.write_csv does NOT append, replace the line above with:
    # final_results.to_csv(out_csv, index=False)

    print("Saved:", out_csv)
