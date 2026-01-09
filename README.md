# PSC-scDRS
PSC-scDRS is designed to link single-variant analysis scores with polygenic disease risk at single-cell RNA sequencing. It identifies cells with excess expression of disease-associated genes identified by Whole Exome Sequencing (WES).  

In the [Quick Start](#quick-start) section, you can follow the instructions to install the requirements and run a sample.
To learn more about the functions, refer to the flowcharts in the [Flowcharts](https://github.com/ikmb/PSC-scDRS/tree/main/Flowcharts). Additionally, there, you can find detailed instructions on the data type and formats required as input for the PSC-scDRS function.
 
# Table of contents
- [Pipeline structure](#pipeline-structure)
- [Quick Start](#quick-start)
	- [Prerequisites and Configuration](#prerequisites-and-configuration)
    - [Downloads](#downloads)
    - [Installing dependencies](installing-dependencies)
    - [Data](#data)
	- [Running PSC-scDRS](#running-PSC-scDRS)
  
# Pipeline Structure
![Image Alt Text](https://github.com/ikmb/PSC-scDRS/blob/main/Flowcharts/Pipeline%20Structure.png)

# Quick Start
## Prerequisites and Configuration
PSC-scDRS requires significant computational resources. Ensure your system meets the following minimum requirements.<br/>
System requirements for the sample dataset:<br/>
&nbsp; 	 - CPU: ≥ 16 cores <br/>
&nbsp; 	 - Memory: ≥ 32 GB RAM (scDRS may require up to 360 GB depending on dataset size) <br/>
&nbsp;	 - Storage: ≥ 20 GB free disk space <br/>

** The pipeline with sample files was tested on a Dell XPS 15 9530 workstation running Ubuntu 22.04.5 LTS, equipped with 32 GB of RAM and a 13th-generation Intel® Core™ i9-13900H processor (20 cores).

Note: For large datasets, it is recommended to run the pipeline on a high-performance computing (HPC) system, as the scDRS method may require it, depending on the input files.

## Downloads
### Clone PSC-scDRS
All the codes and needed files for the sample file will be downloaded in this step.

1) Create a workspace to keep data and files for the PSC-scDRS project.
```bash   
mkdir -p "$HOME"
```

2) Clone if missing,
```bash
cd "$HOME"
git clone https://github.com/ikmb/PSC-scDRS.git
cd PSC-scDRS
```

or re-download
```bash
rm -rf "$HOME/PSC-scDRS"
cd "$HOME"
git clone https://github.com/ikmb/PSC-scDRS.git
cd PSC-scDRS
```

## Installing dependencies
PSC-scDRS needs some extra software to run:
### step 1: Install scDRS
Pipeline will install it. If there is a problem, check [their page](https://pypi.org/project/scdrs/).
### step 2: Install the bcftools
Pipeline will install it. If there is a problem, check [here](https://samtools.github.io/bcftools/howtos/install.html).
### step 3: Install MAGMA
Pipeline will install it. If there is a problem, check [here](https://cncr.nl/research/magma/). <br/>

#### This command installs Python libraries, scDRS, bcftools, and MAGMA.
```bash
cd "$HOME/PSC-scDRS"
bash setup_dependencies.sh
```
## Data
Summary statistics for the GAISE single-marker test on PSC whole-exome sequencing data are available in the sampleWES.zip file. <br/>
The single-cell RNA sequencing data from the healthy human liver in the study by Andrews, T.S. et al. (PMID: 38199298) is provided as a sample dataset after applying the required modifications using the scDRS (PMID: 36050550) method, in the HumanLiverHealthyscRNAseqData.h5ad file. <br/>

## Running PSC-scDRS
The pipeline will run the code smoothly.
```bash
cd "$HOME/PSC-scDRS"
bash PSC_scDRS_run.sh
```
