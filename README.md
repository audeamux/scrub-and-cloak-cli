# Fawkes + ExifTool pipeline (Bash)

A small Bash workflow that cloaks photos with **Fawkes** and then removes metadata from the cloaked outputs—without modifying your originals.

The script is interactive: you copy images into a folder, choose a cloak strength, and get sanitized copies in a separate output directory.

---

## Purpose

Use this project to create shareable copies of photos that:

- have been processed by **Fawkes** (cloaking), and
- have all metadata removed (**EXIF/IPTC/XMP**), which may include camera details, timestamps, GPS coordinates, and more.

The script keeps originals intact and operates only on the cloaked copies.

---

## Credit

**Fawkes** is developed by researchers at the **University of Chicago**. This repo does not reimplement Fawkes. It automates running the published binary and post-processing the outputs.

The script downloads the official v1.0 Linux binary from:

```text
https://mirror.cs.uchicago.edu/fawkes/files/1.0/fawkes_binary_linux-v1.0.zip
```

---

## Why run Fawkes in a container?

Fawkes (especially older releases) relies on an older Python/ML stack (for example, TensorFlow-era dependencies). On modern Linux distros, that can lead to dependency conflicts and binary compatibility issues (Python, NumPy, TensorFlow, and system libraries).

This script runs Fawkes inside a clean **Ubuntu 22.04** container to provide:

- a consistent environment,
- predictable runtime libraries, and
- fewer host-side dependency issues.

---

## What the script does

1. Installs prerequisites using `dnf` (Fedora/RHEL-family).
2. Downloads and unzips the Fawkes v1.0 Linux binary to `~/fawkes/` (if missing).
3. Waits until it detects one or more image files in `~/fawkes/imgs` (MIME-detected, not extension-based).
4. Runs Fawkes inside the Ubuntu 22.04 container with the selected mode (`low`, `mid`, `high`).
5. Moves Fawkes outputs matching:

```text
*_${MODE}_cloaked.*
```

…into:

```text
~/fawkes/scroaked
```

6. Runs `exiftool -all=` **only** on the moved cloaked files (not the originals).

---

## Requirements

### Host (Fedora/RHEL-family)

The script uses `dnf` and installs these packages:

- `wget`, `curl`, `unzip`, `file`
- `docker-cli`
- `perl-Image-ExifTool` (ExifTool)

If your system has the Docker CLI but not the Docker engine, install and enable Docker for your distro and ensure the service is running.

### Container (Ubuntu 22.04)

Inside the container, the script installs runtime libraries commonly needed by ML/vision binaries:

- `libglib2.0-0`
- `libgl1`
- `libstdc++6`
- `libgomp1`

---

## AVX note (VMs and older CPUs)

Fawkes (and/or bundled ML libraries) may require **AVX/AVX2** CPU features.

If you run this inside a VM, you may need CPU mode set to **host/passthrough** so AVX is exposed to the guest.

The script prints a warning if it does not detect `avx`/`avx2` in `/proc/cpuinfo`.

---

## Usage

1. Make the script executable:

```bash
chmod +x ./run.sh
```

2. Run it:

```bash
./run.sh
```

3. Follow the prompts:

- Put images in: `~/fawkes/imgs`
- Choose a mode: `low`, `mid`, or `high`

Outputs:

- **Originals:** `~/fawkes/imgs`
- **Cloaked + metadata stripped:** `~/fawkes/scroaked`

---

## Notes

- The first run can be slower because it pulls the Ubuntu image and runs `apt-get`.
- If the script reports “no cloaked files found,” confirm that the selected mode matches the outputs you expect (for example, `*_low_cloaked.*`).
- If you see `Illegal instruction`, a missing CPU feature (often AVX in a VM) is a common cause.

---

## Disclaimer

This repo is provided for automation and convenience. You are responsible for complying with applicable laws, terms, and policies when processing and sharing images.
