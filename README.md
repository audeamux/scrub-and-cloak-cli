# fawkes + exiftool pipeline (bash)

A small Bash-based workflow to **cloak** photos with **Fawkes** and then **strip metadata** from the cloaked outputs, while leaving your original images untouched.

The script is intentionally simple and interactive: you drop images into a folder, choose a cloak strength, and it produces “sanitized” copies in a separate output directory.

---

## Purpose

This project helps you create **shareable copies** of photos that:

- have been processed by **Fawkes** (to apply a “cloaking” perturbation), and
- have **all metadata removed** (EXIF/IPTC/XMP), which can include camera details, timestamps, GPS, and more.

It keeps the originals intact and only operates on the cloaked copies.

---

## Credit

**Fawkes** is developed by researchers at the **University of Chicago**.  
This repo does **not** reimplement Fawkes. It automates running their published binary and post-processing the outputs.

The script downloads the official v1.0 Linux binary from:

```text
https://mirror.cs.uchicago.edu/fawkes/files/1.0/fawkes_binary_linux-v1.0.zip
```

---

## Why run Fawkes in a Docker container?

Fawkes (especially older releases) depends on a Python/ML stack (e.g., TensorFlow-era dependencies) that can be painful to install reliably on modern Linux distros due to version pinning and binary compatibility (numpy / python versions / system libs).

This script runs Fawkes inside a clean **Ubuntu 22.04** container so you get:

- a consistent user environment,
- predictable runtime libraries (the script installs a few system libs inside the container),
- less “dependency fighting” on the host.

In short: Docker is used to make an older, dependency-heavy tool easier to run repeatably.

---

## What the script does

1. Installs prerequisites using `dnf` (Fedora/RHEL-family).
2. Downloads/unzips the Fawkes v1.0 Linux binary to `~/fawkes/` (if missing).
3. Waits until it detects one or more image files in `~/fawkes/imgs` (MIME-detected, not extension-based).
4. Runs Fawkes inside Docker (Ubuntu 22.04) with the selected mode (`low`, `mid`, `high`).
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
- `perl-Image-ExifTool`

If your system has the Docker CLI but not the Docker engine, install/enable Docker for your distro and ensure the service is running.

### Container (Ubuntu 22.04)
Inside the container, the script installs a few runtime libraries commonly needed by ML/vision binaries:

- `libglib2.0-0`
- `libgl1`
- `libstdc++6`
- `libgomp1`

---

## AVX note (VMs / older CPUs)

Fawkes (and/or its bundled ML libraries) may require **AVX/AVX2** CPU features.  
If you're running this inside a **VM**, you may need CPU mode set to **host/passthrough** (so AVX is exposed).  
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

3. Follow prompts:
- Put images in: `~/fawkes/imgs`
- Choose mode: `low` / `mid` / `high`

Outputs:
- **Originals:** `~/fawkes/imgs`
- **Cloaked + metadata stripped:** `~/fawkes/scroaked`

---

## Notes / gotchas

- First run can be slower due to pulling the Ubuntu image and running `apt-get`.
- If the script says **no cloaked files found**, confirm the selected mode matches the outputs you expect (e.g., `*_low_cloaked.*`).
- If you see **Illegal instruction**, it is usually a CPU feature exposure problem (AVX in a VM).

---

## Disclaimer

This repo is for automation/convenience. You are responsible for understanding and complying with any applicable laws, terms, and policies when processing and sharing images.
