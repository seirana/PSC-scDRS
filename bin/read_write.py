#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: seirana

This function reads and writes files in various formats.

Reading:
    .txt
    .parquete
    .xlsx
    .csv
    .tsv
    .bed
    
write:
    .csv
    .txt
"""

def read_txt(x, split,h):
    import pandas as pd
    with open(x+'.txt') as f:
        lines = f.readlines()
    
    if h == True:
        clmns = lines[0]  
        clmns = list(clmns.split(split))
        l = len(clmns)
        if  clmns[l-1].endswith('\n'):
            s = clmns[l-1]
            sl = len(s)
            clmns[l-1] = s[0:sl-1]
        y = pd.DataFrame([x.strip().split(split) for x in lines], columns = clmns)
        y.drop(y.index[0], axis=0, inplace=True)
        y.reset_index(drop=True, inplace=True)
    else:
        y = pd.DataFrame([x.strip().split(split) for x in lines])

    # l = len(lines)
    # y = pd.DataFrame()
    # y = pd.DataFrame(y, columns=clmns )
    # for i in range(l):
    #     line_i = lines[i]  
    #     y.loc[i,:] = list(line_i.split(","))
    return y

def write_txt(x, y, d, h):
    import numpy as np
    import os

    p = [j for j in range(len(x)) if x.startswith('/', j)]
    path = d[0:p[len(p)-1]]
    # Check whether the specified path exists or not
    isExist = os.path.exists(path)
    if not isExist:    
       # Create a new directory because it does not exist
        os.makedirs(path)

    if h == True:
        np.savetxt(x+'.txt', y, fmt='%s', delimiter= d ,newline='\n', header=' '.join(y.columns))
    else:
        np.savetxt(x+'.txt', y, fmt='%s', delimiter= d ,newline='\n', header='')
        
def read_parquet(x):
    # read partitioned parquet files
    import pandas as pd
    from pathlib import Path
    data_dir = Path(x)
    y = pd.concat(
        pd.read_parquet(parquet_file)
        for parquet_file in data_dir.glob('*.parquet')
    )
    return y

def read_xlsx(x):
    import pandas as pd     
    # read by default 1st sheet of an excel file
    y = pd.read_excel(x+'.xlsx')
    return y

def read_tsv(x,h):
    import pandas as pd  
    from pathlib import Path
    #import csv
    # read by default 1st sheet of an tsv file
    filepath = Path(x+'.tsv')
    #y = pd.DataFrame()
    y=[]
    with open(filepath) as fd:
        #rd = csv.reader(fd, delimiter=d, quotechar=q)
        #df = pd.DataFrame([x.strip().split(' ') for x in rd])
        for row in fd:
            c = row.split('\t')
            #c = pd.DataFrame([c])
            #y = pd.concat([y, c], axis=0)
            y.append(c)
        y = pd.DataFrame(y) 
        if h == True:
            y.columns = y.loc[0,:]
            y = y.drop(index=[0])
            y.index = range(len(y))
        return y

def read_csv(x):
    # read by default 1st sheet of an csv file
    import pandas as pd
    y = pd.read_csv(x+'.csv')
    return y

def write_csv(x,y):
    from pathlib import Path
    filepath = Path(y+'.csv')
    filepath.parent.mkdir(parents=True, exist_ok=True)
    x.to_csv(filepath,index=False)
