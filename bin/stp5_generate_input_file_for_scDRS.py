#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Seirana

This program
 1. Selects 1000 genes with the highest z-score, then finds approved gene names based on Entrez IDs,
 2. generates a gene set list for the scDRS function,
 3. generates a Manhattan plot of MAGMA gene-based analyses,
 4. makes a list of genes with a significant p-value.

input:
    ./PSC-scDRS/output/files_step2.genes.out
    ./PSC-scDRS/data/magma_10kb_top1000_zscore.74_traits.rv1.gs
    
output:  
    ./PSC-scDRS/output/zscore.csv
    ./PSC-scDRS/output/PSC_geneset.gs
    ./PSC-scDRS/output/gene_based_test.png
    ./PSC-scDRS/output/significant_genes_MAGMA.csv
"""

import matplotlib.pyplot as plt
from pathlib import Path
import pandas as pd
import numpy as np
import requests

def list_maker(df):
    x_geneset = ''
    for i in range(len(df) - 1):
        c = round(float(df.iloc[i, 1]), 4)
        tmp = str(df.iloc[i, 0]) + ':' + str(c) + ','
        x_geneset = x_geneset + tmp

    tmp = str(df.iloc[i + 1, 0]) + ':' + str(df.iloc[i + 1, 1])
    x_geneset = x_geneset + tmp
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


if __name__ == '__main__':

    # Output directory
    dirc = Path.home() / "PSC-scDRS" / "output"

    file = dirc / "files_step2.genes.out"
    df = pd.read_csv(file, sep=r"\s+")

    # top 1000 z-scores
    df = df.nlargest(1000, "ZSTAT").reset_index(drop=True)
    df.loc[df["ZSTAT"] > 10, "ZSTAT"] = 10

    # Entrez IDs (first column)
    gene_ids = df.iloc[:, 0].astype(str).tolist()

    # Batch mapping (fast + robust)
    mapping = entrez_to_symbol(gene_ids)

    gene_name = pd.DataFrame({
        "gene_symbol": [mapping.get(g, "") for g in gene_ids]
    })

    df = pd.concat([df, gene_name], axis=1)

    out_csv = dirc / "zscore.csv"
    df.to_csv(out_csv, index=False)
    print("Saved:", out_csv)

    #..........................................................................
    # make geneset fine
    dirc = Path.home() /"PSC-scDRS"/"data"
    file = str(dirc/"magma_10kb_top1000_zscore.74_traits.rv1.gs")
    cntrl = pd.read_csv(file, sep="\t")
    geneset = cntrl.loc[[0], :]
    geneset.index = range(len(geneset))
    geneset.loc[0, 'TRAIT'] = 'PSC'

    df = df.loc[:, ['gene_symbol', 'ZSTAT']]
    geneset.loc[0, 'GENESET'] = list_maker(df)

    dirc = Path.home() /"PSC-scDRS"/"output"
    dirc.mkdir(parents=True, exist_ok=True)
    write_file = str(dirc/"PSC_geneset.gs")
    geneset.to_csv(write_file, sep="\t", index=False)
    
    # .........................................................................
    # build Manhattan plo
    dirc = Path.home() /"PSC-scDRS"/"output"
    file = str(dirc / "files_step2.genes.out")
    df = pd.read_csv(file, sep=r'\s+')
    df = df.loc[:, ['CHR', 'P']]
    dm = df.shape
    
    df.loc[:, 'LOG10P'] = -np.log10(df.loc[:, 'P'])
    df['ind'] = range(len(df))
    
    df.CHR = df.CHR.astype('category')
    df_grouped = df.groupby(('CHR'))
    
    # manhattan plot
    fig = plt.figure(figsize=(14, 8))  # Set the figure size
    ax = fig.add_subplot(111)
    colors = ['#7FC97F','#FDC086'] #yellow, green
    x_labels = []
    x_labels_pos = []
    for num, (name, group) in enumerate(df_grouped):
        group.plot(kind='scatter', x='ind', y='LOG10P',
                   color=colors[num % len(colors)], ax=ax)
        x_labels.append(name)
        x_labels_pos.append(
            (group['ind'].iloc[-1] - (group['ind'].iloc[-1] - group['ind'].iloc[0])/2))
    ax.set_xticks(x_labels_pos)
    ax.set_xticklabels(x_labels)
    plt.axhline(y=5.58, color='gray', linestyle='--')
    # set axis limits
    ax.set_xlim([0, len(df)])
    ax.set_ylim([0, int(df.loc[:,'LOG10P'].max()+1)])
    
    # x axis label
    ax.set_xlabel('Chromosome')
    plt.ylabel("-log10p")
    plt.title('MAGMA gene-based test', fontsize=16, fontweight='bold', loc='center', pad=20)
    
    # show the graph
    dirc = Path.home() /"PSC-scDRS"/"output"
    plt.savefig(str(dirc / "gene_based_test.png"))
    plt.show()
    # .........................................................................
    # make list of significant genes
    data = pd.DataFrame()
    
    dirc = Path.home() /"PSC-scDRS"/"output"
    file = str(dirc/"zscore.csv")
    df = pd.read_csv(file, sep=',')
    val_genes = df.loc[df['P'] <= 2.5*1e-6, ['gene_symbol', 'CHR', 'P']]
    val_genes = pd.concat([val_genes, pd.DataFrame(
        {'Column': ['SAIGE'] * len(val_genes)})], axis=1)
    data = pd.concat([data, val_genes], axis=0)
    
    file = str(dirc/"significant_genes_MAGMA.csv")
    data.to_csv(file, index=False)
