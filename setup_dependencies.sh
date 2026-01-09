#!/usr/bin/env bash
set -euo pipefail

echo "==========================================="
echo "   PSC-scDRS - ONE-TIME SETUP"
echo "==========================================="
echo

echo "Checking Python installation..."

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python is not installed (python3 not found)."
  echo "Please install Python 3.12 (and python3.12-venv) and re-run."
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

if [ ! -d "$ENV_NAME" ]; then
  echo ">>> Creating Python virtual environment ($ENV_NAME)"
  python3 -m venv "$ENV_NAME"
else
  echo ">>> Python virtual environment ($ENV_NAME) already exists, reusing"
fi

echo ">>> Activating environment"
# shellcheck disable=SC1090
source "$ENV_NAME/bin/activate"

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

# htslib (needs submodules: htscodecs)
if [ ! -d "$HTSLIB_DIR/.git" ]; then
  echo ">>> Cloning htslib (with submodules) into $HTSLIB_DIR"
  git clone --recurse-submodules https://github.com/samtools/htslib.git "$HTSLIB_DIR"
else
  echo ">>> htslib already exists in $HTSLIB_DIR, updating"
  git -C "$HTSLIB_DIR" pull --rebase
  git -C "$HTSLIB_DIR" submodule update --init --recursive
fi

echo ">>> Building htslib"
make -C "$HTSLIB_DIR"

# bcftools
if [ ! -d "$BCFTOOLS_DIR/.git" ]; then
  echo ">>> Cloning bcftools (with submodules) into $BCFTOOLS_DIR"
  git clone --recurse-submodules https://github.com/samtools/bcftools.git "$BCFTOOLS_DIR"
else
  echo ">>> bcftools already exists in $BCFTOOLS_DIR, updating"
  git -C "$BCFTOOLS_DIR" pull --rebase
  git -C "$BCFTOOLS_DIR" submodule update --init --recursive
fi

echo ">>> Building bcftools (make)"
make -C "$BCFTOOLS_DIR" clean || true
make -C "$BCFTOOLS_DIR"

echo ">>> Done. Binary is at: $SCRIPT_DIR/$BCFTOOLS_DIR/bcftools"
echo

# --------------------------
# 3) Download dbSNP GRCh38 master catalog
# --------------------------
mkdir -p vcf
cd vcf

echo ">>> Downloading dbSNP master rsID catalogue (GRCh38)"
wget -nc https://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606_b151_GRCh38p7/VCF/00-All.vcf.gz
wget -nc https://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606_b151_GRCh38p7/VCF/00-All.vcf.gz.tbi

cd "$SCRIPT_DIR"
echo

# --------------------------
# 4) Install MAGMA resources
# --------------------------
mkdir -p magma
cd magma

echo ">>> Downloading MAGMA reference data"
curl -L -o g1000_eur.zip \
  "https://vu.data.surf.nl/index.php/s/VZNByNwpD8qqINe/download?path=%2F&files=g1000_eur.zip"
unzip -t g1000_eur.zip
unzip -o g1000_eur.zip

curl -L -o NCBI38.zip \
  "https://vu.data.surf.nl/index.php/s/yj952iHqy5anYhH/download?path=%2F&files=NCBI38.zip"
unzip -t NCBI38.zip
unzip -o NCBI38.zip

cd "$SCRIPT_DIR"
echo
echo "==========================================="
echo "   ONE-TIME SETUP COMPLETED"
echo "==========================================="
