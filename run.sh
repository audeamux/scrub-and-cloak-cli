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

check_service_status() {
  local svc="$1"
  local status

  status="$(systemctl is-active "$svc" 2>/dev/null || true)"
  if [[ "$status" == "active" ]]; then
    print_color green "$svc service is active"
  else
    print_color red "$svc service is not active (status: $status)"
    systemctl --no-pager -l status "$svc" || true
    exit 1
  fi
}

#---------------- Vars

FAWKES_DIR="$HOME/fawkes"
IMG_DIR="$FAWKES_DIR/imgs"
CLOAKED_DIR="$FAWKES_DIR/scroaked"

ZIP_URL="https://mirror.cs.uchicago.edu/fawkes/files/1.0/fawkes_binary_linux-v1.0.zip"
ZIP_FILE="$FAWKES_DIR/fawkes_binary_linux-v1.0.zip"

#---------------- Prereqs

print_color green "Updating DNF and installing prerequisites"
sudo dnf update -y
sudo dnf install -y wget curl unzip docker-cli perl-Image-ExifTool file

# Heads-up: Fawkes binary will likely require AVX
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

#---------------- Message (interactive: waits for images)

print_color green "Place your pictures into: $IMG_DIR"
# Quick first scan, so we know if there are any images already
# Mime inspect file content to determine file type...png, jpg, etc

img_count=0
shopt -s nullglob
for f in "$IMG_DIR"/*; do
  [[ -f "$f" ]] || continue
  mime="$(file -b --mime-type "$f" 2>/dev/null || true)"
  if [[ "$mime" == image/* ]]; then
    ((img_count+=1))
  fi
done
shopt -u nullglob

while true; do
  img_count=0
  shopt -s nullglob
  for f in "$IMG_DIR"/*; do
    [[ -f "$f" ]] || continue
    mime="$(file -b --mime-type "$f" 2>/dev/null || true)"
    if [[ "$mime" == image/* ]]; then
      ((img_count+=1))
    fi
  done
  shopt -u nullglob

  if [[ "$img_count" -gt 0 ]]; then
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
    1)
      print_color yellow "Re-scaning..."
      ;;
    2)
      print_color yellow "Continuing anyway..."
      break
      ;;
    3)
      print_color yellow "Canceled."
      exit 0
      ;;
    *)
      print_color red "Invalid option."
      ;;
  esac
done

if [[ "$img_count" -eq 0 ]]; then
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

#---------------- Docker

sudo systemctl start docker || true
check_service_status docker

sudo docker run --rm -it \
  -v "$FAWKES_DIR:/app/fawkes:Z" \
  -w /app/fawkes \
  ubuntu:22.04 \
  bash -lc '
    set -e
    echo "Updating apt..."
    apt-get update > /dev/null
    echo "Installing deps..."
    apt-get install -y --no-install-recommends \
      libglib2.0-0 \
      libgl1 \
      libstdc++6 \
      libgomp1 \
    > /dev/null

    echo "Running Fawkes..."
    chmod +x ./protection
    ./protection -d ./imgs --mode '$MODE'
  '

print_color green "Fawkes run completed."

#---------------- Move cloaked outputs (only) to separate folder

print_color green "Moving cloaked files to $CLOAKED_DIR"
mkdir -p "$CLOAKED_DIR"

moved=0
while IFS= read -r -d '' f; do
  mv -f "$f" "$CLOAKED_DIR/"
  ((moved+=1))    # <-- FIXED (was moved++)
done < <(find "$IMG_DIR" -maxdepth 1 -type f -name "*_${MODE}_cloaked.*" -print0)

if [[ "$moved" -eq 0 ]]; then
  print_color red "No cloaked files found matching: *_${MODE}_cloaked.*"
  print_color red "Nothing moved; skipping EXIF stripping."
  exit 1
fi

print_color green "Moved $moved cloaked file(s)."

#---------------- Exif (ONLY on cloaked files)

print_color green "Stripping metadata from cloaked files only: $CLOAKED_DIR"

stripped=0
while IFS= read -r -d '' f; do
  exiftool -overwrite_original -all= "$f" >/dev/null
  ((stripped+=1))   # <-- FIXED (was stripped++)
done < <(find "$CLOAKED_DIR" -maxdepth 1 -type f -print0)

print_color green "EXIF stripping complete. Files processed: $stripped"
print_color green "Done."
