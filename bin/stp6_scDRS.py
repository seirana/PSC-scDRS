#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Seirana

This function runs scDRS across the desired traits and tissues.

input:
    ./PSC-scDRS/data/{tissue}.h5ad
    ./PSC-scDRS/output/{trait}_geneset.gs
    
output:
    ./PSC-scDRS/output/{tissue}_cov.tsv
    ./PSC-scDRS/output/{tissue}_{trait}.full_score.gz
    ./PSC-scDRS/output/{tissue}_{trait}.score.gz
    ./PSC-scDRS/output/{tissue}_{trait}.scdrs_group.cell_ontology_class
    ./PSC-scDRS/bin/figures/cell_ontology_classes_{tissue}.png
    ./PSC-scDRS/bin/figures/associated_cells_of_{tissue}_to_{geneset}.png
"""

from pathlib import Path
import pandas as pd
import scanpy as sc
import numpy as np
import subprocess
import warnings
import zipfile
import scdrs_
import os

warnings.filterwarnings("ignore")

trait = 'PSC'
tissue = "Liver"

hm = 'hsapiens'

data_dirc = Path.home() /"PSC-scDRS" / "data"
out_dirc = Path.home() / "PSC-scDRS" / "output"

zip_path = data_dirc / "HumanLiverHealthyscRNAseqData.zip"
target_path = data_dirc / "Liver.h5ad"
with zipfile.ZipFile(zip_path) as z:
    h5ad_inside = [n for n in z.namelist() if n.endswith(".h5ad")][0]
    extracted_path = z.extract(h5ad_inside, data_dirc)
    Path(extracted_path).rename(target_path)
    
adata = sc.read_h5ad(data_dirc / f"{tissue}.h5ad")

cell_id = adata.obs.index
cell_id = cell_id.to_frame(index=False)

n_genes = adata.obs.loc[:, ['n_genes']]
n_genes.index = range(len(n_genes))

const = np.ones((len(cell_id), 1), dtype=int)
const = pd.DataFrame(columns=['const'], data=const)
cov = pd.concat([cell_id, n_genes, const], axis=1)
cov.to_csv(str(out_dirc/f"{tissue}_cov.tsv"), sep="\t", index=False)

args = [
    '--h5ad_file',  str(data_dirc/ f'{tissue}.h5ad'),
    '--h5ad_species', hm,
    '--cov_file', str(out_dirc/ f'{tissue}_cov.tsv'),
    '--gs_file', str(out_dirc/f'{trait}_geneset.gs'),
    '--gs_species', 'hsapiens',
    '--ctrl_match_opt', "mean_var",
    '--weight_opt', "vs",
    '--flag_raw_count', "False",
    '--n_ctrl', "1000",
    '--flag_return_ctrl_raw_score', "False",
    '--flag_return_ctrl_norm_score', "True",
    '--out_folder', str(out_dirc)
]

subprocess.run(
    ['python', str(Path.home() /'scDRS/compute_score.py')] + args)

geneset = str(out_dirc/f'{trait}_geneset.gs')
df_gs = pd.read_csv(geneset, sep="\t", index_col=0)
dict_score = {
    trait: pd.read_csv(
        out_dirc/f"{trait}.full_score.gz", sep="\t", index_col=0)
    for trait in df_gs.index
    if os.path.isfile(str(out_dirc/f"{trait}.full_score.gz"))
}

for trait in dict_score:
    if os.path.isfile(str(out_dirc/f"{trait}.full_score.gz")):
        adata.obs[trait] = dict_score[trait]["norm_score"]

if len(dict_score) > 0:
    sc.set_figure_params(figsize=[2.5, 2.5], dpi=150)
    sc.pl.umap(
        adata,
        color="cell_ontology_class",
        ncols=1,
        color_map="RdBu_r",
        vmin=-5,
        vmax=5,
        save=f'_cell_ontology_classes_{tissue}.png'
    )

    sc.pl.umap(
        adata,
        color=dict_score.keys(),
        color_map="RdBu_r",
        vmin=-5,
        vmax=5,
        s=20,
        save=f'_associated_cells_of_{tissue}_to_{trait}.png'
    )

if os.path.isfile(str(out_dirc/f"{trait}.full_score.gz")):
    scdrs_.perform_downstream(
        h5ad_file = str(data_dirc/ f'{tissue}.h5ad'),
        score_file = str(out_dirc/f"{trait}.full_score.gz"),
        out_folder = str(out_dirc),
        group_analysis="cell_ontology_class",
    )
