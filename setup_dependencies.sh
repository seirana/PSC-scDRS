#!/usr/bin/env bash
set -euo pipefail

echo "==========================================="
echo "   PSC-scDRS - ONE-TIME SETUP (ROBUST)"
echo "==========================================="
echo

# ------------------------------------------------------------------
# Settings you may want to tweak (safe defaults)
# ------------------------------------------------------------------
: "${DOWNLOAD_RETRIES:=8}"          # retries for flaky networks
: "${DOWNLOAD_RETRY_DELAY:=2}"      # seconds
: "${DOWNLOAD_TIMEOUT:=30}"         # seconds per request
: "${ALLOW_RESUME:=1}"              # 1 = allow resume (curl -C -), 0 = fresh only
: "${FORCE_REDOWNLOAD:=0}"          # 1 = always re-download critical files
: "${SCDRS_BRANCH:=}"               # optionally pin a branch/tag/commit for scDRS (empty = default)
: "${HTSLIB_REF:=}"                 # optionally pin htslib ref (empty = default)
: "${BCFTOOLS_REF:=}"               # optionally pin bcftools ref (empty = default)

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/output/logs"
LOG_DIR="$SCRIPT_DIR/output/logs"
PIP_LOG="$LOG_DIR/pip_install.log"
SETUP_LOG="$LOG_DIR/setup_dependencies.log"

# Log everything to file + console
exec > >(tee -a "$SETUP_LOG") 2>&1

die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
}

# Download to a temp file, validate externally, then atomically move into place.
# This prevents truncated/partial files from being left as "complete".
download_atomic() {
  local url="$1"
  local out="$2"
  local tmp="${out}.tmp.$$"
  local out_dir
  out_dir="$(dirname "$out")"
  mkdir -p "$out_dir"

  if [[ -f "$out" && "$FORCE_REDOWNLOAD" -eq 0 ]]; then
    echo ">>> Download skip (already exists): $out"
    return 0
  fi

  echo ">>> Downloading: $url"
  echo ">>> -> $out"

  rm -f "$tmp"

  # Resume support (optional). Still safe because we only move after success.
  local resume_args=()
  if [[ "$ALLOW_RESUME" -eq 1 ]]; then
    resume_args=(-C -)
  fi

  curl -L --fail \
    --retry "$DOWNLOAD_RETRIES" \
    --retry-delay "$DOWNLOAD_RETRY_DELAY" \
    --connect-timeout "$DOWNLOAD_TIMEOUT" \
    "${resume_args[@]}" \
    -o "$tmp" \
    "$url" || die "Download failed: $url"

  # Basic sanity: file must be non-empty
  [[ -s "$tmp" ]] || die "Downloaded file is empty: $out"

  mv -f "$tmp" "$out"
}

# Download ZIP, test zip integrity, unzip to target dir.
download_zip_and_unzip() {
  local url="$1"
  local zip_path="$2"
  local out_dir="$3"

  download_atomic "$url" "$zip_path"
  echo ">>> Testing zip integrity: $zip_path"
  unzip -t "$zip_path" >/dev/null || die "ZIP integrity test failed: $zip_path"

  echo ">>> Extracting to: $out_dir"
  mkdir -p "$out_dir"
  unzip -o "$zip_path" -d "$out_dir" >/dev/null || die "Unzip failed: $zip_path"
}

echo ">>> Repo root: $SCRIPT_DIR"
echo ">>> Logs: $SETUP_LOG"
echo

# ------------------------------------------------------------------
# 0) Basic tool checks
# ------------------------------------------------------------------
for cmd in git make gcc curl unzip; do
  need_cmd "$cmd"
done

# (wget is optional; we use curl, but keep it as helpful)
if ! command -v wget >/dev/null 2>&1; then
  echo "NOTE: wget not found (OK). Using curl for downloads."
fi

echo ">>> Checking Python installation..."
need_cmd python3

python3 - <<'PY'
import sys
maj, minor = sys.version_info[:2]
print(f"Found Python {maj}.{minor}")
if (maj, minor) < (3, 12):
    raise SystemExit("Python >= 3.12 is required.")
PY

# Work inside the repo
cd "$SCRIPT_DIR"

# ------------------------------------------------------------------
# 1) Python virtual env + deps
# ------------------------------------------------------------------
ENV_NAME="pythonENV"
VENV_PATH="$SCRIPT_DIR/$ENV_NAME"

if [[ ! -d "$VENV_PATH" ]]; then
  echo ">>> Creating Python virtual environment ($ENV_NAME)"
  python3 -m venv "$VENV_PATH"
else
  echo ">>> Python virtual environment ($ENV_NAME) already exists, reusing"
fi

[[ -f "$VENV_PATH/bin/activate" ]] || die "Venv activation script not found: $VENV_PATH/bin/activate"

echo ">>> Activating environment"
# shellcheck disable=SC1090
source "$VENV_PATH/bin/activate"

REQ_FILE="$SCRIPT_DIR/env/requirements.txt"
[[ -f "$REQ_FILE" ]] || die "requirements.txt not found at $REQ_FILE"

PYTHON="$VENV_PATH/bin/python"
echo ">>> Using: $PYTHON"
"$PYTHON" -V

echo ">>> Installing Python dependencies from $REQ_FILE"
echo ">>> Logging pip output to: $PIP_LOG"
"$PYTHON" -m pip install --upgrade pip setuptools wheel 2>&1 | tee "$PIP_LOG"
"$PYTHON" -m pip install --no-cache-dir -r "$REQ_FILE" 2>&1 | tee -a "$PIP_LOG"

# ------------------------------------------------------------------
# 1b) scDRS (repo-local, editable install)
# ------------------------------------------------------------------
SCDRS_DIR="$SCRIPT_DIR/scDRS"
SCDRS_REPO="https://github.com/martinjzhang/scDRS.git"

echo
echo ">>> Setting up scDRS (repo-local, editable install)"

if [[ ! -d "$SCDRS_DIR/.git" ]]; then
  echo ">>> Cloning scDRS into: $SCDRS_DIR"
  git clone "$SCDRS_REPO" "$SCDRS_DIR"
else
  echo ">>> scDRS already present, updating"
  git -C "$SCDRS_DIR" fetch --all --tags
  git -C "$SCDRS_DIR" pull --ff-only
fi

if [[ -n "$SCDRS_BRANCH" ]]; then
  echo ">>> Checking out scDRS ref: $SCDRS_BRANCH"
  git -C "$SCDRS_DIR" checkout "$SCDRS_BRANCH"
fi

echo ">>> Installing scDRS in editable mode (pip install -e ./scDRS)"
"$PYTHON" -m pip install -e "$SCDRS_DIR" 2>&1 | tee -a "$PIP_LOG"

echo ">>> Verifying scDRS import source"
"$PYTHON" - <<'PYEOF' 2>&1 | tee -a "$PIP_LOG"
import os
import scdrs
print("OK: scDRS imported")
print("scDRS location:", scdrs.__file__)

repo_scdrs = os.path.realpath("./scDRS")
loaded = os.path.realpath(scdrs.__file__)

if not loaded.startswith(repo_scdrs):
    raise SystemExit(
        "ERROR: scDRS is NOT imported from repo-local ./scDRS.\n"
        f"Expected prefix: {repo_scdrs}\n"
        f"Loaded from:     {loaded}\n"
        "Fix: remove any conflicting scdrs installs and rerun setup_dependencies.sh"
    )
PYEOF

echo ">>> scDRS ready (repo-local)"
echo

# ------------------------------------------------------------------
# 2) HTSlib + BCFtools (build early so we can validate VCF downloads)
# ------------------------------------------------------------------
HTSLIB_DIR="$SCRIPT_DIR/htslib"
BCFTOOLS_DIR="$SCRIPT_DIR/bcftools"

echo ">>> Setting up htslib + bcftools (repo-local builds)"

if [[ ! -d "$HTSLIB_DIR/.git" ]]; then
  echo ">>> Cloning htslib (with submodules) into $HTSLIB_DIR"
  git clone --recurse-submodules https://github.com/samtools/htslib.git "$HTSLIB_DIR"
else
  echo ">>> htslib already exists, updating"
  git -C "$HTSLIB_DIR" fetch --all --tags
  git -C "$HTSLIB_DIR" pull --rebase
  git -C "$HTSLIB_DIR" submodule update --init --recursive
fi

if [[ -n "$HTSLIB_REF" ]]; then
  echo ">>> Checking out htslib ref: $HTSLIB_REF"
  git -C "$HTSLIB_DIR" checkout "$HTSLIB_REF"
  git -C "$HTSLIB_DIR" submodule update --init --recursive
fi

echo ">>> Building htslib (provides bgzip/tabix)"
if ! make -C "$HTSLIB_DIR"; then
  echo "htslib build failed."
  echo "On Ubuntu/Debian you may need:"
  echo "  sudo apt install -y libcurl4-openssl-dev libbz2-dev liblzma-dev"
  exit 1
fi

if [[ ! -d "$BCFTOOLS_DIR/.git" ]]; then
  echo ">>> Cloning bcftools (with submodules) into $BCFTOOLS_DIR"
  git clone --recurse-submodules https://github.com/samtools/bcftools.git "$BCFTOOLS_DIR"
else
  echo ">>> bcftools already exists, updating"
  git -C "$BCFTOOLS_DIR" fetch --all --tags
  git -C "$BCFTOOLS_DIR" pull --rebase
  git -C "$BCFTOOLS_DIR" submodule update --init --recursive
fi

if [[ -n "$BCFTOOLS_REF" ]]; then
  echo ">>> Checking out bcftools ref: $BCFTOOLS_REF"
  git -C "$BCFTOOLS_DIR" checkout "$BCFTOOLS_REF"
  git -C "$BCFTOOLS_DIR" submodule update --init --recursive
fi

echo ">>> Building bcftools (make)"
make -C "$BCFTOOLS_DIR" clean || true
make -C "$BCFTOOLS_DIR"

# Prefer repo-local tools in this session
export PATH="$HTSLIB_DIR:$BCFTOOLS_DIR:$PATH"

echo
echo ">>> Tool availability check"
need_cmd bgzip
need_cmd tabix
need_cmd bcftools
echo "bgzip:    $(command -v bgzip)"
echo "tabix:    $(command -v tabix)"
echo "bcftools: $(command -v bcftools)"
echo

# ------------------------------------------------------------------
# 3) Download dbSNP GRCh38 master catalog (robust + verified)
# ------------------------------------------------------------------
DBSNP_DIR="$SCRIPT_DIR/vcf"
mkdir -p "$DBSNP_DIR"

DBSNP_VCF="$DBSNP_DIR/00-All.vcf.gz"
DBSNP_TBI="$DBSNP_DIR/00-All.vcf.gz.tbi"

DBSNP_URL_VCF="https://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606_b151_GRCh38p7/VCF/00-All.vcf.gz"
DBSNP_URL_TBI="https://ftp.ncbi.nlm.nih.gov/snp/organisms/human_9606_b151_GRCh38p7/VCF/00-All.vcf.gz.tbi"

echo ">>> Downloading dbSNP master rsID catalogue (GRCh38)"
download_atomic "$DBSNP_URL_VCF" "$DBSNP_VCF"

# Always regenerate the index from the downloaded VCF to avoid stale mismatches
# (The remote .tbi can be kept, but local reindex is more robust across updates/copies.)
if [[ "$FORCE_REDOWNLOAD" -eq 1 ]]; then
  rm -f "$DBSNP_TBI"
fi

echo ">>> Verifying dbSNP VCF integrity (bgzip -t)"
bgzip -t "$DBSNP_VCF" || die "dbSNP VCF is corrupted/truncated (BGZF test failed): $DBSNP_VCF"

echo ">>> Verifying dbSNP VCF is readable (bcftools header)"
bcftools view -h "$DBSNP_VCF" >/dev/null || die "bcftools cannot read dbSNP VCF: $DBSNP_VCF"

echo ">>> Ensuring a fresh tabix index for dbSNP VCF"
rm -f "$DBSNP_TBI"
tabix -p vcf "$DBSNP_VCF" || die "Failed to create tabix index: $DBSNP_TBI"

echo ">>> dbSNP ready:"
ls -lh "$DBSNP_VCF" "$DBSNP_TBI"
echo

# (Optional) Also download the official .tbi (not required, but sometimes wanted)
# If you want it, uncomment the next 2 lines (we still prefer our rebuilt index):
# download_atomic "$DBSNP_URL_TBI" "$DBSNP_DIR/00-All.vcf.gz.tbi.ncbi"
# echo ">>> (Optional) NCBI index saved as: $DBSNP_DIR/00-All.vcf.gz.tbi.ncbi"

# ------------------------------------------------------------------
# 4) MAGMA (binary + reference data) with integrity checks
# ------------------------------------------------------------------
MAGMA_DIR="$SCRIPT_DIR/magma"
mkdir -p "$MAGMA_DIR"

echo ">>> Setting up MAGMA in: $MAGMA_DIR"
echo ">>> (cwd) $MAGMA_DIR"

# 4a) 1000G EUR reference panel (LD reference for MAGMA)
if [[ ! -f "$MAGMA_DIR/g1000_eur.bed" || ! -f "$MAGMA_DIR/g1000_eur.bim" || ! -f "$MAGMA_DIR/g1000_eur.fam" ]]; then
  echo ">>> Downloading 1000G EUR reference panel"
  download_zip_and_unzip \
    "https://vu.data.surf.nl/index.php/s/VZNByNwpD8qqINe/download?path=%2F&files=g1000_eur.zip" \
    "$MAGMA_DIR/g1000_eur.zip" \
    "$MAGMA_DIR"
else
  echo ">>> 1000G EUR reference already present"
fi

# 4b) Gene locations (GRCh38 / hg38)
if [[ ! -f "$MAGMA_DIR/NCBI38.gene.loc" ]]; then
  echo ">>> Downloading NCBI38 gene locations"
  download_zip_and_unzip \
    "https://vu.data.surf.nl/index.php/s/yj952iHqy5anYhH/download?path=%2F&files=NCBI38.zip" \
    "$MAGMA_DIR/NCBI38.zip" \
    "$MAGMA_DIR"
else
  echo ">>> NCBI38.gene.loc already present"
fi

# 4c) MAGMA binary (repo-local)
if [[ -d "$MAGMA_DIR/magma" ]]; then
  echo ">>> WARNING: $MAGMA_DIR/magma is a directory (should be a binary). Removing it."
  rm -rf "$MAGMA_DIR/magma"
fi

if [[ ! -f "$MAGMA_DIR/magma" ]]; then
  echo ">>> Downloading MAGMA binary"
  download_zip_and_unzip \
    "https://vu.data.surf.nl/index.php/s/zkKbNeNOZAhFXZB/download" \
    "$MAGMA_DIR/magma_v1.10.zip" \
    "$MAGMA_DIR"
fi

chmod +x "$MAGMA_DIR/magma" 2>/dev/null || true
[[ -f "$MAGMA_DIR/magma" ]] || die "MAGMA binary not found at $MAGMA_DIR/magma"

# Prefer repo-local MAGMA in this session
export PATH="$MAGMA_DIR:$PATH"
hash -r

need_cmd magma
echo ">>> Using MAGMA: $(command -v magma)"
echo ">>> MAGMA version: $(magma --version 2>/dev/null | head -n 1 || true)"

# Sanity checks for required MAGMA resources
[[ -f "$MAGMA_DIR/NCBI38.gene.loc" ]] || die "Missing $MAGMA_DIR/NCBI38.gene.loc"
[[ -f "$MAGMA_DIR/g1000_eur.bed" && -f "$MAGMA_DIR/g1000_eur.bim" && -f "$MAGMA_DIR/g1000_eur.fam" ]] || \
  die "Missing one of g1000_eur.{bed,bim,fam} in $MAGMA_DIR"

echo ">>> MAGMA ready"
echo ">>> LD reference prefix: $MAGMA_DIR/g1000_eur"
echo ">>> Gene location file:  $MAGMA_DIR/NCBI38.gene.loc"
echo

# ------------------------------------------------------------------
# 5) Final summary / guidance
# ------------------------------------------------------------------
echo "==========================================="
echo "   ONE-TIME SETUP COMPLETED (ROBUST)"
echo "==========================================="
echo
echo "Next steps:"
echo "  1) Run pipeline: bash ./PSC_scDRS_run.sh"
echo
echo "Notes:"
echo "  - dbSNP VCF is verified with bgzip -t + bcftools header parse"
echo "  - dbSNP index is always rebuilt locally to prevent stale .tbi issues"
echo "  - Downloads are atomic (no partial files left behind on failures)"
echo
echo "For new terminals, you may add to ~/.bashrc:"
echo "  export PATH=\"$HTSLIB_DIR:$BCFTOOLS_DIR:$MAGMA_DIR:\$PATH\""
echo
echo "Logs:"
echo "  Setup: $SETUP_LOG"
echo "  Pip:   $PIP_LOG"
