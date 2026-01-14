#!/usr/bin/env bash
set -euo pipefail

echo "==========================================="
echo "   PSC-scDRS - ONE-TIME SETUP"
echo "==========================================="
echo

# --------------------------
# 0) Basic tool checks
# --------------------------
for cmd in git make gcc wget curl unzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    echo "On Ubuntu/Debian, install with:"
    echo "  sudo apt update && sudo apt install -y git build-essential wget curl unzip"
    exit 1
  fi
done

echo "Checking Python installation..."

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python is not installed (python3 not found)."
  echo "Install Python 3.12 (and python3.12-venv) and re-run."
  exit 1
fi

PY_VER=$(python3 - <<'EOF'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
EOF
)
echo "Found Python $PY_VER"

if [[ "$PY_VER" < "3.12" ]]; then
  echo "Python >=3.12 is required."
  exit 1
fi

# Work inside the repo (script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --------------------------
# 1) Python virtual env + deps
# --------------------------
ENV_NAME="pythonENV"
VENV_PATH="$SCRIPT_DIR/$ENV_NAME"

if [ ! -d "$VENV_PATH" ]; then
  echo ">>> Creating Python virtual environment ($ENV_NAME)"
  python3 -m venv "$VENV_PATH"
else
  echo ">>> Python virtual environment ($ENV_NAME) already exists, reusing"
fi

if [ ! -f "$VENV_PATH/bin/activate" ]; then
  echo "Virtual environment activation script not found: $VENV_PATH/bin/activate"
  echo "Try removing $VENV_PATH and re-running setup_dependencies.sh"
  exit 1
fi

echo ">>> Activating environment"
# shellcheck disable=SC1090
source "$VENV_PATH/bin/activate"

REQ_FILE="$SCRIPT_DIR/env/requirements.txt"
echo ">>> Installing Python dependencies from $REQ_FILE"

if [ ! -f "$REQ_FILE" ]; then
  echo "requirements.txt not found at $REQ_FILE"
  exit 1
fi

python3 -m pip install --upgrade pip
python3 -m pip install -r "$REQ_FILE"

echo
echo ">>> Python environment ready."
echo

# --------------------------
# 2) HTSlib + BCFtools
# --------------------------
HTSLIB_DIR="htslib"
BCFTOOLS_DIR="bcftools"
HTSLIB_PATH="$SCRIPT_DIR/$HTSLIB_DIR"
BCFTOOLS_PATH="$SCRIPT_DIR/$BCFTOOLS_DIR"

# htslib (needs submodules: htscodecs)
if [ ! -d "$HTSLIB_PATH/.git" ]; then
  echo ">>> Cloning htslib (with submodules) into $HTSLIB_DIR"
  git clone --recurse-submodules https://github.com/samtools/htslib.git "$HTSLIB_PATH"
else
  echo ">>> htslib already exists in $HTSLIB_DIR, updating"
  git -C "$HTSLIB_PATH" pull --rebase
  git -C "$HTSLIB_PATH" submodule update --init --recursive
fi

echo ">>> Building htslib (provides bgzip/tabix)"
if ! make -C "$HTSLIB_PATH"; then
  echo "htslib build failed."
  echo "On Ubuntu/Debian you may need:"
  echo "  sudo apt install -y libcurl4-openssl-dev libbz2-dev liblzma-dev"
  exit 1
fi

# bcftools
if [ ! -d "$BCFTOOLS_PATH/.git" ]; then
  echo ">>> Cloning bcftools (with submodules) into $BCFTOOLS_DIR"
  git clone --recurse-submodules https://github.com/samtools/bcftools.git "$BCFTOOLS_PATH"
else
  echo ">>> bcftools already exists in $BCFTOOLS_DIR, updating"
  git -C "$BCFTOOLS_PATH" pull --rebase
  git -C "$BCFTOOLS_PATH" submodule update --init --recursive
fi

echo ">>> Building bcftools (make)"
make -C "$BCFTOOLS_PATH" clean || true
make -C "$BCFTOOLS_PATH"

# Make bgzip/tabix/bcftools available in THIS shell session
export PATH="$HTSLIB_PATH:$BCFTOOLS_PATH:$PATH"

echo
echo ">>> Tool availability check"
command -v bgzip >/dev/null 2>&1 || { echo "bgzip not found in PATH after build"; exit 1; }
command -v bcftools >/dev/null 2>&1 || { echo "bcftools not found in PATH after build"; exit 1; }
echo "bgzip:    $(command -v bgzip)"
echo "bcftools: $(command -v bcftools)"
echo
echo ">>> For new terminals, add to ~/.bashrc:"
echo "export PATH=\"$HTSLIB_PATH:$BCFTOOLS_PATH:\$PATH\""
echo

# --------------------------
# 3) Download dbSNP GRCh38 master catalog
# --------------------------
mkdir -p "$SCRIPT_DIR/vcf"
cd "$SCRIPT_DIR/vcf"

echo ">>> Downloading dbSNP master rsID catalogue (GRCh38)"
wget -nc https://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606_b151_GRCh38p7/VCF/00-All.vcf.gz
wget -nc https://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606_b151_GRCh38p7/VCF/00-All.vcf.gz.tbi

cd "$SCRIPT_DIR"
echo

# --------------------------
# 4) MAGMA (binary + reference data)
# --------------------------
MAGMA_DIR="$SCRIPT_DIR/magma"
mkdir -p "$MAGMA_DIR"
cd "$MAGMA_DIR" || { echo "ERROR: cannot cd to $MAGMA_DIR"; exit 1; }

echo ">>> Setting up MAGMA in: $MAGMA_DIR"
echo ">>> (cwd) $(pwd)"

# Helper: download -> test -> unzip -> cleanup (all with absolute paths)
download_and_unzip() {
  local url="$1"
  local zip_path="$2"
  local out_dir="$3"

  echo ">>> Downloading: $zip_path"
  curl -L --fail -o "$zip_path" "$url"

  echo ">>> Testing zip integrity: $zip_path"
  unzip -t "$zip_path" >/dev/null

  echo ">>> Extracting to: $out_dir"
  unzip -o "$zip_path" -d "$out_dir" >/dev/null
}

# 4a) 1000G EUR reference panel (LD reference for MAGMA)
if [[ ! -f "$MAGMA_DIR/g1000_eur.bed" || ! -f "$MAGMA_DIR/g1000_eur.bim" || ! -f "$MAGMA_DIR/g1000_eur.fam" ]]; then
  echo ">>> Downloading 1000G EUR reference panel"
  download_and_unzip \
    "https://vu.data.surf.nl/index.php/s/VZNByNwpD8qqINe/download?path=%2F&files=g1000_eur.zip" \
    "$MAGMA_DIR/g1000_eur.zip" \
    "$MAGMA_DIR"
else
  echo ">>> 1000G EUR reference already present"
fi

# 4b) Gene locations (GRCh38 / hg38)
if [[ ! -f "$MAGMA_DIR/NCBI38.gene.loc" ]]; then
  echo ">>> Downloading NCBI38 gene locations"
  download_and_unzip \
    "https://vu.data.surf.nl/index.php/s/yj952iHqy5anYhH/download?path=%2F&files=NCBI38.zip" \
    "$MAGMA_DIR/NCBI38.zip" \
    "$MAGMA_DIR"
else
  echo ">>> NCBI38.gene.loc already present"
fi

# 4c) MAGMA binary (repo-local)
# Guard against previous bad state where "magma" is a directory
if [[ -d "$MAGMA_DIR/magma" ]]; then
  echo ">>> WARNING: $MAGMA_DIR/magma is a directory (should be a binary). Removing it."
  rm -rf "$MAGMA_DIR/magma"
fi

if [[ ! -f "$MAGMA_DIR/magma" ]]; then
  echo ">>> Downloading MAGMA binary"
  download_and_unzip \
    "https://vu.data.surf.nl/index.php/s/zkKbNeNOZAhFXZB/download" \
    "$MAGMA_DIR/magma_v1.10.zip" \
    "$MAGMA_DIR"
fi

# Ensure executable bit is set
chmod +x "$MAGMA_DIR/magma" 2>/dev/null || true

# Validate MAGMA binary exists
if [[ ! -f "$MAGMA_DIR/magma" ]]; then
  echo "ERROR: MAGMA binary not found at $MAGMA_DIR/magma"
  echo "       Contents of $MAGMA_DIR:"
  ls -la "$MAGMA_DIR" | head -n 80
  exit 1
fi

# Force pipeline to use repo-local MAGMA (prefer over /usr/local/bin/magma)
export PATH="$MAGMA_DIR:$PATH"
hash -r

command -v magma >/dev/null 2>&1 || { echo "ERROR: magma not available in PATH"; exit 1; }

echo ">>> Using MAGMA: $(command -v magma)"
echo ">>> MAGMA version: $(magma --version 2>/dev/null | head -n 1 || true)"

# Sanity checks for required MAGMA resources
[[ -f "$MAGMA_DIR/NCBI38.gene.loc" ]] || { echo "ERROR: Missing $MAGMA_DIR/NCBI38.gene.loc"; exit 1; }
[[ -f "$MAGMA_DIR/g1000_eur.bed" && -f "$MAGMA_DIR/g1000_eur.bim" && -f "$MAGMA_DIR/g1000_eur.fam" ]] || {
  echo "ERROR: Missing one of g1000_eur.{bed,bim,fam} in $MAGMA_DIR"
  exit 1
}

echo ">>> MAGMA ready"
echo ">>> LD reference prefix: $MAGMA_DIR/g1000_eur"
echo ">>> Gene location file:  $MAGMA_DIR/NCBI38.gene.loc"
echo

# Return to repo root for subsequent steps
cd "$SCRIPT_DIR"
echo "==========================================="
echo "   ONE-TIME SETUP COMPLETED"
echo "==========================================="
