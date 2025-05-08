#!/bin/bash

set -euo pipefail
trap 'echo "⚠️  Script interrupted or failed"; exit 1' ERR INT

# --- System Requirements Check for vmt ---
echo "🔧 vmt doctor - checking host system compatibility"

check_host_requirements() {
  if [[ -f /etc/redhat-release ]]; then
    echo "🧪 Detected RHEL-based system"
    required_packages=(
      qemu-kvm
      qemu-img
      libvirt
      virt-install
      libvirt-client
			genisoimage
			dnsmasq
    )
    check_cmd="rpm -q"
  elif [[ -f /etc/debian_version ]]; then
    echo "🧪 Detected Debian/Ubuntu-based system"
    required_packages=(
      libvirt-daemon
      libvirt-clients
      bridge-utils
      qemu-system-x86
      virtinst
      cpu-checker
      libvirt-daemon-system
      dnsmasq
      genisoimage
      cloud-image-utils
    )
    check_cmd="dpkg -s"
  else
    echo "❌ Unsupported distribution. Only RHEL and Debian/Ubuntu are supported."
    exit 1
  fi

  missing=()
  for pkg in "${required_packages[@]}"; do
    if ! $check_cmd "$pkg" &>/dev/null && ! command -v "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "❌ Missing required packages:"
    for p in "${missing[@]}"; do echo "   - $p"; done
    echo "👉 Please install them using your system package manager."
    exit 1
  else
    echo "✅ All required packages found"
  fi

  for group in libvirt kvm; do
    if id -nG "$USER" | grep -qw "$group"; then
      echo "✅ User '$USER' is in the '$group' group"
    else
      echo "⚠️  User '$USER' is NOT in the '$group' group."
      echo "Add yourself with: sudo usermod -aG $group $USER && newgrp $group"
    fi
  done
}

check_host_requirements
