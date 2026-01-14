#!/usr/bin/env bash
set -euo pipefail

#---------------- Helpers

NC="\033[0m"
print_color() {
  local color="${1:-}"
  local msg="${2:-}"
  local COLOR

  case "$color" in
    green)  COLOR="\033[0;32m" ;;
    red)    COLOR="\033[0;31m" ;;
    yellow) COLOR="\033[0;33m" ;;
    *)      COLOR="$NC" ;;
  esac

  echo -e "${COLOR}${msg}${NC}"
}

#---------------- Vars

FAWKES_DIR="$HOME/fawkes"
IMG_DIR="$FAWKES_DIR/imgs"
CLOAKED_DIR="$FAWKES_DIR/scroaked"

ZIP_URL="https://mirror.cs.uchicago.edu/fawkes/files/1.0/fawkes_binary_linux-v1.0.zip"
ZIP_FILE="$FAWKES_DIR/fawkes_binary_linux-v1.0.zip"

RUNTIME_DIR="$FAWKES_DIR/runtime"
DOCKERFILE="$RUNTIME_DIR/Dockerfile"
IMAGE_TAG="fawkes-runtime:22.04"

#---------------- Prereqs

print_color green "Updating DNF and installing prerequisites"
sudo dnf update -y
sudo dnf install -y wget curl unzip podman perl-Image-ExifTool file

command -v podman >/dev/null 2>&1 || {
  print_color red "podman is required but not installed. Please check the podman service status"
  exit 1
}

# Heads-up: Fawkes binary will likely require AVX
# If running on a virtual machine, set your CPU mode to 'AVX' or 'host'
if ! grep -qm1 -oE 'avx2|avx' /proc/cpuinfo; then
  print_color yellow "WARNING: No AVX/AVX2 detected in /proc/cpuinfo."
  print_color yellow "Some ML/vision binaries may fail with 'Illegal instruction' in this environment."
  print_color yellow "If running on a virtual machine, set your CPU mode to 'AVX' or 'host'"
fi

#---------------- Get Fawkes binary

mkdir -p "$IMG_DIR"

if [[ ! -x "$FAWKES_DIR/protection" ]]; then
  print_color green "Downloading Fawkes zip -> $ZIP_FILE"
  curl -fL -o "$ZIP_FILE" "$ZIP_URL"

  print_color green "Unzipping into $FAWKES_DIR"
  unzip -o "$ZIP_FILE" -d "$FAWKES_DIR" >/dev/null
  rm -f "$ZIP_FILE"

  chmod +x "$FAWKES_DIR/protection" || true
else
  print_color green "Fawkes binary already present: $FAWKES_DIR/protection"
fi

#---------------- Docker file of a one-time container build
# First run takes a bit longer, as container needs to be built with dependancies installed
# Subsequent jobs will be significantly faster

mkdir -p "$RUNTIME_DIR"

if [[ ! -f "$DOCKERFILE" ]]; then
  print_color green "Creating runtime Dockerfile: $DOCKERFILE"
  cat > "$DOCKERFILE" <<'EOF'
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libgl1 \
    libstdc++6 \
    libgomp1 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app/fawkes
EOF
fi

if ! podman image exists "$IMAGE_TAG"; then
  print_color green "Building local runtime image: $IMAGE_TAG"
  podman build -t "$IMAGE_TAG" -f "$DOCKERFILE" "$RUNTIME_DIR"
else
  print_color green "Runtime image already present: $IMAGE_TAG"
fi

#----------------- Interactive message

print_color green "Place your pictures into: $IMG_DIR"

count_images() {
  find "$IMG_DIR" -maxdepth 1 -type f \
    -exec file -b --mime-type -- {} + 2>/dev/null \
    | grep -c '^image/' || true
}

while true; do
  img_count="$(count_images)"

  if (( img_count > 0 )); then
    print_color green "Detected $img_count image file(s) in $IMG_DIR"
    break
  fi

  print_color red "No images detected yet in $IMG_DIR"
  echo
  echo "Options:"
  echo "  1) Re-scan (...after you've copied files into the folder)"
  echo "  2) Continue anyway (not recommended)"
  echo "  3) Cancel"
  read -r -p "> " ans

  case "$ans" in
    1) print_color yellow "Re-scanning..." ;;
    2) print_color yellow "Continuing anyway..."; break ;;
    3) print_color yellow "Canceled."; exit 0 ;;
    *) print_color red "Invalid option." ;;
  esac
done

if (( img_count == 0 )); then
  print_color red "No images to process. Exiting."
  exit 1
fi

#---------------- Choose mode

echo
echo "Select Fawkes mode:"
echo "  1) low"
echo "  2) mid"
echo "  3) high"
echo "  4) cancel"
read -r -p "> " choice

case "$choice" in
  1) MODE="low" ;;
  2) MODE="mid" ;;
  3) MODE="high" ;;
  4) print_color yellow "Canceled."; exit 0 ;;
  *) print_color red "Invalid choice."; exit 1 ;;
esac

read -r -p "Run Fawkes now in mode '$MODE'? (y/n): " yn
case "$yn" in
  y|Y) : ;;
  *) print_color yellow "Canceled."; exit 0 ;;
esac

#---------------- Run Fawkes using the pre-built image from earlier

podman run --rm -it \
  -v "$FAWKES_DIR:/app/fawkes:Z" \
  -w /app/fawkes \
  "$IMAGE_TAG" \
  bash -lc '
    set -e
    echo "Running Fawkes..."
    chmod +x ./protection
    ./protection -d ./imgs --mode '"$MODE"'
  '

print_color green "Fawkes run completed."

#---------------- Move cloaked images to separate folder

pattern="*_${MODE}_cloaked.*"

print_color green "Moving cloaked outputs ($pattern) to '$CLOAKED_DIR'..."
mkdir -p "$CLOAKED_DIR"

# If no matches, just move on (no hard fail)
if ! find "$IMG_DIR" -maxdepth 1 -type f -name "$pattern" -print -quit | grep -q .; then
  print_color yellow "No cloaked files found ($pattern). Skipping move."
else
  find "$IMG_DIR" -maxdepth 1 -type f -name "$pattern" -exec mv -f -t "$CLOAKED_DIR" -- {} +
  print_color green "Moved cloaked files."
fi


#---------------- Exif on cloaked files only

print_color green "Stripping metadata from cloaked files only: $CLOAKED_DIR"

stripped=0
while IFS= read -r -d '' f; do
  exiftool -overwrite_original -all= "$f" >/dev/null
  ((stripped+=1))
done < <(find "$CLOAKED_DIR" -maxdepth 1 -type f -print0)

print_color green "EXIF stripping complete. Files processed: $stripped"
print_color green "Done."
