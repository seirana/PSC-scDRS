#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Seirana


This program:
    1. calculates the variables of log-threshold formula -> threshold = a + b / log10(cell_count)
    2. reads the result of scDRS analyses and reports associated cell-types

input:
    min_cell_count = 150
    up_threshold = 5
    factor = 100
    ./PSC-scDRS/output/{trait}.scdrs_group.cell_ontology_class
    
output:
    ./PSC-scDRS/output/log_threshod.png
    ./PSC-scDRS/output/{trait}_cell assiciation with_{tissue}
"""


import sys
from pathlib import Path
sys.path.append(str(Path.home() / "PSC-scDRS" / "bin"))

from sympy import symbols, Eq, log, solve
import matplotlib.pyplot as plt
import read_write as rw
import pandas as pd
import numpy as np
import os

def log_threshold(out_dirc):
    # Define symbols for a and b
    a, b = symbols("a b")
    
    min_cell_count = 150
    up_threshold = 5
    
    factor = 100
    max_cell_count = 150 * factor
    low_threshold = up_threshold/factor
    
    # Set up the two equations based on the given conditions
    eq1 = Eq(a + b / log(min_cell_count, 10), up_threshold)
    eq2 = Eq(a + b / log(max_cell_count, 10), low_threshold)
    
    # Solve the system of equations for a and b
    solution = solve((eq1, eq2), (a, b))
    a_fit, b_fit = solution[a], solution[b]
    #print(a_fit,b_fit)
    
    # Define the threshold function with the solved parameters
    def tr(x, a=a_fit, b=b_fit):
        return a + b / np.log10(x)
    
    # Generate x values for plotting the fitted curve
    x_values = np.logspace(2.1, 6, 100)  # From 100 to 10000, logarithmic scale
    y_values = np.maximum(tr(x_values),1)
    
    # Plot the fitted curve and the original data points
    plt.figure(figsize=(8, 6))
    plt.plot(x_values, y_values, label=f"Threshold function: $tr(x) = {a_fit:.2f} + {b_fit:.2f}/\\log_{{10}}(x)$", color="b")
    plt.axhline(y=1, color="green", linestyle="--", label="minimum threshold")
    plt.xscale("log")
    plt.yscale("linear")
    plt.xlabel("Cell Count")
    plt.ylabel("Threshold (%)")
    plt.title("Logarithmic Threshold Model")
    plt.grid(True, which="both", ls="--", linewidth=0.5)
    plt.legend()
    plt.savefig(str(out_dirc / "log_threshod.png"))
    plt.show()
    return a_fit,b_fit


def read_file(trait, tissue, out_dirc):
    file = str(out_dirc / f"{trait}.scdrs_group.cell_ontology_class")
    if os.path.exists(file):
        with open(file) as f:
            lines = f.readlines()

        split = ("	")
        clmns = lines[0]
        clmns = list(clmns.split(split))
        l = len(clmns)
        if clmns[l-1].endswith("\n"):
            s = clmns[l-1]
            sl = len(s)
            clmns[l-1] = s[0:sl-1]
    
        y = pd.DataFrame([x.strip().split(split)
                         for x in lines], columns=clmns)
        y.reset_index(drop=True, inplace=True)
    
        y.columns = y.loc[0, :]
        y.drop(y.index[0], axis=0, inplace=True)
        y.reset_index(drop=True, inplace=True)
        y["group"] = y["group"].str.replace(",", "_", regex=False)
        return y
    else:
        y = pd.DataFrame()
        return y


def floatTOnumber(db):
    db.replace({"n_fdr_0.05": {"": 0}}, inplace=True)
    db["n_fdr_0.05"] = db["n_fdr_0.05"].astype(float)

    db.replace({"assoc_mcp": {"": 0}}, inplace=True)
    db["assoc_mcp"] = db["assoc_mcp"].astype(float)

    db.replace({"hetero_mcp": {"": 0}}, inplace=True)
    db["hetero_mcp"] = db["hetero_mcp"].astype(float)
    return db


if __name__ == "__main__":
    out_dirc = Path.home() / "PSC-scDRS" / "output"
    a,b = log_threshold(out_dirc)
    columns = ["tissue", "trait", "cell", "n cell","assoc.", "hetero.", "percentage of associated cells with fdr. 0.05", "threshold", "significancy"]
    
    trait = "PSC"
    tissue = "Liver"
    
   
    dig = 5
    final_results = pd.DataFrame(columns=columns)

    db = read_file(trait, tissue, out_dirc)
    
    if not db.empty:
        cells = db.loc[:, "group"]
        cnt = db.loc[:, "n_cell"]
        clmn = pd.DataFrame(index=range(len(cells)), columns=columns[4:9])

        db = floatTOnumber(db)
        for d in range(len(db)):
            clmn.iloc[d, 0] = round(float(db.loc[d, "assoc_mcp"]), dig)
            clmn.iloc[d, 1] = round(float(db.loc[d, "hetero_mcp"]), dig)
            clmn.iloc[d, 2] = round(
                float(db.loc[d, "n_fdr_0.05"])/float(db.loc[d, "n_cell"]), dig)*100
            if float(db.loc[d, "n_fdr_0.05"]) > 0:
                clmn.iloc[d, 3] = max(a+(b/np.log10(float(db.loc[d, "n_cell"]))),0.005)
                if clmn.iloc[d, 2] >= clmn.iloc[d, 3]: 
                    clmn.iloc[d, 4] = 1
                else:
                    clmn.iloc[d, 4] = 0
            else:
                clmn.iloc[d, 4] = 0

            if (float(db.loc[d, "n_cell"]) >= 150 and
               float(db.loc[d, "assoc_mcp"]) <= 0.05 and
               float(db.loc[d, "n_fdr_0.05"]) > 0):
                final_results.loc[len(final_results)] = [
                    tissue,          # "tissue"
                    trait,           # "trait"
                    cells.iloc[d],   # "cell"
                    cnt.iloc[d],     # "n cell"
                    clmn.iloc[d, 0],  # "assoc."
                    clmn.iloc[d, 1],  # "hetero."
                    clmn.iloc[d, 2],  # "fdr. 0.05"
                    clmn.iloc[d, 3],  # "threshold"
                    clmn.iloc[d, 4],  # "significancy"
                ]

        file = str(out_dirc/f"{trait}_cell assiciation with_{tissue}")
        rw.write_csv(final_results, file)
