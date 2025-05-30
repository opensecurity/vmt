#!/bin/bash

set -euo pipefail
trap 'echo "⚠️  Script interrupted or failed"; exit 1' ERR INT
[[ "${VMT_DEBUG:-0}" == "1" ]] && set -x

echo "🕒 $(date '+%Y-%m-%d %H:%M:%S') - Running: $0 $*"

VERSION="vmt 1.0.0"

WORKDIR="$HOME/vms"
IMAGE_CACHE="$WORKDIR/.images"
SSH_KEY_DIR="$WORKDIR/.ssh"
SSH_KEY_PATH="$SSH_KEY_DIR/id_ed25519"
LOGS_FOLDER="$WORKDIR/.logs"
mkdir -p "$WORKDIR" "$IMAGE_CACHE" "$SSH_KEY_DIR" "$LOGS_FOLDER"
chmod 700 "$SSH_KEY_DIR"
chmod 700 "$WORKDIR"
chmod 700 "$IMAGE_CACHE"

ACTION=${1:-}
RAW_NAME=${2:-}
DISTRO=${3:-ubuntu}
RAM=${4:-2048}
CPUS=${5:-2}
DISK_SIZE=${6:-20}
DISK_BYTES=$((DISK_SIZE * 1024 * 1024 * 1024))

NAME=$(echo "$RAW_NAME" | tr -cd 'a-zA-Z0-9' | cut -c1-12)
if [[ "$NAME" != "$RAW_NAME" ]]; then
  echo "⚠️  VM name sanitized to '$NAME' from '$RAW_NAME'"
fi

VMPATH="$WORKDIR/$NAME"
POOL_NAME="vmt_${NAME}"

LOG_FILE="$LOGS_FOLDER/$NAME.log"
if [[ "${VMT_LOG:-1}" != "0" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

require_commands() {
  for cmd in terraform virsh cloud-localds ssh-keygen curl; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "❌ Required command '$cmd' not found in PATH"
      exit 1
    fi
  done
}

if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 {bootstrap|create|apply|destroy|ssh|delete|ls|start|stop} VM_NAME DISTRO [RAM_MB] [CPUs] [Disk_GB]"
  exit 1
fi

require_commands

# Define base image URLs per distro
case "$DISTRO" in
  ubuntu)
    BASE_IMAGE_URL="https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
    IMAGE_FILE="ubuntu-cloud.qcow2"
    ;;
  almalinux)
    BASE_IMAGE_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-9.5-20241120.x86_64.qcow2"
    IMAGE_FILE="alma-cloud.qcow2"
    ;;
  rockylinux)
    BASE_IMAGE_URL="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
    IMAGE_FILE="rocky-cloud.qcow2"
    ;;
  *)
    echo "❌ Unsupported distro: $DISTRO"
    exit 1
    ;;
esac

CACHED_IMAGE="$IMAGE_CACHE/$IMAGE_FILE"
DEST_IMAGE="$VMPATH/qemu/images/$IMAGE_FILE"

check_vm_dir() {
  if [[ ! -d "$VMPATH" ]]; then
    echo "❌ VM '$NAME' not found in $WORKDIR"
    exit 1
  fi
}

bootstrap_pool() {
  if [[ ! -f "$SSH_KEY_PATH" || ! -f "$SSH_KEY_PATH.pub" ]]; then
    echo "🔑 Generating SSH key for VM access..."
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N ""
    chmod 600 "$SSH_KEY_PATH"
    echo "✅ SSH key generated at $SSH_KEY_PATH"
  else
    echo "✅ SSH key already exists: $SSH_KEY_PATH"
  fi
}

create_network() {
  local NETWORK_NAME="net_${POOL_NAME}"
  local BRIDGE_NAME="vmt_${NAME:0:10}"
  local NET_XML="$VMPATH/qemu/network.xml"
  local SUBNET_BASE="192.168.$((RANDOM % 100 + 100)).0"
  local GATEWAY_IP="${SUBNET_BASE%.*}.1"

  cat > "$NET_XML" <<EOF
<network>
  <name>$NETWORK_NAME</name>
  <bridge name='$BRIDGE_NAME' stp='on' delay='0'/>
  <forward mode='nat'/>
  <ip address='$GATEWAY_IP' netmask='255.255.255.0'>
    <dhcp>
      <range start='${SUBNET_BASE%.*}.100' end='${SUBNET_BASE%.*}.254'/>
    </dhcp>
  </ip>
</network>
EOF

  if ! virsh net-info "$NETWORK_NAME" &>/dev/null; then
    virsh net-define "$NET_XML"
    virsh net-start "$NETWORK_NAME"
    virsh net-autostart "$NETWORK_NAME"
    echo "✅ Created and started libvirt network: $NETWORK_NAME"
  else
    echo "✅ Network $NETWORK_NAME already exists"
  fi
}

create_pool() {
  if ! virsh pool-info "$POOL_NAME" &>/dev/null; then
    virsh pool-define-as "$POOL_NAME" dir --target "$VMPATH/qemu"
    virsh pool-build "$POOL_NAME"
    virsh pool-start "$POOL_NAME"
    virsh pool-autostart "$POOL_NAME"
  fi
}

get_vm_ip() {
  local name=$1

  local state
  state=$(virsh domstate "$name" 2>/dev/null || true)
  if [[ "$state" != "running" ]]; then
    echo "<no ip>"
    return
  fi

  local ip
  ip=$(virsh domifaddr "$name" --source agent 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | grep -Ev '^127\.' | head -n1)
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return
  fi

  local mac
  mac=$(virsh domiflist "$name" 2>/dev/null | awk '/network/ {print $5}' | head -n1)
  if [[ -z "$mac" ]]; then
    echo "<no ip>"
    return
  fi

  if command -v ip &>/dev/null; then
    ip=$(ip neigh | grep -i "$mac" | awk '{print $1}' | head -n1)
  elif command -v arp &>/dev/null; then
    ip=$(arp -an | grep -i "$mac" | awk '{print $2}' | tr -d '()' | head -n1)
  else
    echo "⚠️ Neither 'ip' nor 'arp' found; can't resolve IP"
    ip="<no ip>"
  fi

  echo "${ip:-<no ip>}"
}

get_vm_os() {
  local name=$1
  local image_dir="$WORKDIR/$name/qemu/images"

  if [[ -f "$image_dir/ubuntu-cloud.qcow2" ]]; then
    echo "Ubuntu"
  elif [[ -f "$image_dir/alma-cloud.qcow2" ]]; then
    echo "AlmaLinux"
  elif [[ -f "$image_dir/rocky-cloud.qcow2" ]]; then
    echo "RockyLinux"
  else
    echo "<unknown>"
  fi
}


destroy_vm() {
  check_vm_dir
  cd "$VMPATH/terraform"
  terraform destroy -auto-approve
  rm -f "$WORKDIR/qemu/seed/${NAME}-seed.img"
}

case "$ACTION" in
  ls)
    echo "📂 All VMs in $WORKDIR:"
    for vm_dir in "$WORKDIR"/*; do
      [[ -d "$vm_dir" ]] || continue
      vm_name=$(basename "$vm_dir")
      if virsh dominfo "$vm_name" &>/dev/null; then
        state=$(virsh domstate "$vm_name" | head -n1)
      else
        state="not defined"
      fi
      ip=$(get_vm_ip "$vm_name")
      os=$(get_vm_os "$vm_name")
      printf "• %-20s • %-16s • %s • %-12s\n" "$vm_name" "$ip" "$os" "$state"

    done
    ;;
  bootstrap)
    bootstrap_pool
    ;;

  create)
    if [[ -d "$VMPATH" ]]; then
      echo "❌ VM '$NAME' already exists at $VMPATH. Use 'apply' 'destroy' or 'delete' first."
      exit 1
    fi
    bootstrap_pool
    mkdir -p "$VMPATH/qemu/images" "$VMPATH/qemu/seed" "$VMPATH/cloudinit" "$VMPATH/terraform"
    create_pool
    create_network

    echo "📦 Checking for base image in cache..."
    if [[ ! -f "$CACHED_IMAGE" ]]; then
      echo "⬇️  Downloading base image to $CACHED_IMAGE..."
      curl -L "$BASE_IMAGE_URL" -o "$CACHED_IMAGE"
      chmod 644 "$CACHED_IMAGE"

      echo "🔍 Verifying downloaded image..."
      if ! qemu-img info "$CACHED_IMAGE" &>/dev/null; then
        echo "❌ Image file is invalid or corrupted: $CACHED_IMAGE"
        rm -f "$CACHED_IMAGE"
        exit 1
      fi
      echo "✅ Image verified: $CACHED_IMAGE"
      echo "✅ Cached base image at $CACHED_IMAGE"
    else
      echo "✅ Found cached base image: $CACHED_IMAGE"
    fi

    echo "📁 Copying base image to VM directory..."
    cp "$CACHED_IMAGE" "$DEST_IMAGE"

    cat > "$VMPATH/terraform/main.tf" <<EOF
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.6"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///session"
}

resource "libvirt_volume" "base" {
  name   = "${NAME}-base"
  pool   = "$POOL_NAME"
  source = "\${path.module}/../qemu/images/$IMAGE_FILE"
  format = "${IMAGE_FILE##*.}"
}

resource "libvirt_volume" "disk" {
  name           = "$NAME.qcow2"
  pool           = "$POOL_NAME"
  size = $DISK_BYTES
  base_volume_id = libvirt_volume.base.id
}

resource "libvirt_volume" "seed" {
  name   = "${NAME}-seed.img"
  pool   = "$POOL_NAME"
  source = "\${path.module}/../qemu/seed/${NAME}-seed.img"
  format = "raw"
}

resource "libvirt_domain" "$NAME" {
  name   = "$NAME"
  memory = $RAM
  vcpu   = $CPUS
  cpu {
    mode = "host-passthrough"
  }
  disk {
    volume_id = libvirt_volume.disk.id
  }
  disk {
    volume_id = libvirt_volume.seed.id
  }
  network_interface {
    network_name = "net_$POOL_NAME"
  }
  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }
  graphics {
    type = "spice"
    listen_type = "none"
  }
  boot_device {
    dev = ["hd"]
  }
}
EOF

    cat > "$VMPATH/cloudinit/user-data" <<EOF
#cloud-config
hostname: $NAME
users:
  - name: devops
    ssh_authorized_keys:
      - $(cat "$SSH_KEY_PATH.pub")
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
package_update: true
package_upgrade: true
package_reboot_if_required: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF

    cat > "$VMPATH/cloudinit/meta-data" <<EOF
instance-id: $NAME
local-hostname: $NAME
EOF

    cloud-localds "$VMPATH/qemu/seed/${NAME}-seed.img" "$VMPATH/cloudinit/user-data" "$VMPATH/cloudinit/meta-data"

    echo "✅ VM config created in $VMPATH"
    ;;

  apply)
    check_vm_dir
    echo "🧹 Checking for existing domain in libvirt..."
    if virsh dominfo "$NAME" &>/dev/null; then
      virsh destroy "$NAME" 2>/dev/null || true
      virsh undefine "$NAME" --remove-all-storage 2>/dev/null || true
      echo "✅ Removed stale domain definition"
    fi
    cd "$VMPATH/terraform"
    terraform init -input=false
    terraform apply -auto-approve
    echo "🚀 VM '$NAME' is ready."
    echo "🔍 Waiting for IP address..."
    for i in {1..10}; do
      IP=$(get_vm_ip "$NAME")
      if [[ "$IP" != "<no ip>" ]]; then
        echo "🔑 SSH: ssh -i $SSH_KEY_PATH devops@$IP"
        break
      fi
      sleep 2
    done

    if [[ "$IP" == "<no ip>" ]]; then
      echo "⚠️  Failed to retrieve VM IP after 10 attempts"
    fi
    ;;

  destroy)
    destroy_vm
    ;;

  ssh)
    check_vm_dir
    IP=$(get_vm_ip "$NAME")
    if [[ -z "$IP" ]]; then
      echo "❌ Cannot determine IP for $NAME"
      exit 1
    fi
    shift 2
    exec ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KEY_DIR/known_hosts" devops@"$IP" "$@"
    ;;

  start)
    check_vm_dir
    if virsh dominfo "$NAME" &>/dev/null; then
      if [[ "$(virsh domstate "$NAME")" == "running" ]]; then
        echo "✅ VM '$NAME' is already running"
      else
        virsh start "$NAME"
        echo "🚀 VM '$NAME' started"
      fi
    else
      echo "❌ VM '$NAME' is not defined in libvirt"
      exit 1
    fi
    ;;

  stop)
    check_vm_dir
    if virsh dominfo "$NAME" &>/dev/null; then
      if [[ "$(virsh domstate "$NAME")" != "running" ]]; then
        echo "✅ VM '$NAME' is already stopped"
      else
        virsh shutdown "$NAME"
        echo "🛑 Sent shutdown signal to '$NAME'"
      fi
    else
      echo "❌ VM '$NAME' is not defined in libvirt"
      exit 1
    fi
    ;;


  delete)
    check_vm_dir
    echo "⚠️ Deleting VM '$NAME' and all associated resources..."

    # Destroy and undefine domain
    if virsh dominfo "$NAME" &>/dev/null; then
      virsh destroy "$NAME" 2>/dev/null || true
      virsh undefine "$NAME" --remove-all-storage 2>/dev/null || true
      echo "🗑️  Domain '$NAME' destroyed"
    else
      echo "ℹ️  No domain found for '$NAME'"
    fi

    # Destroy and undefine storage pool
    if virsh pool-info "$POOL_NAME" &>/dev/null; then
      virsh pool-destroy "$POOL_NAME" 2>/dev/null || true
      virsh pool-undefine "$POOL_NAME" 2>/dev/null || true
      echo "🗑️  Storage pool '$POOL_NAME' removed"
    else
      echo "ℹ️  No storage pool found for '$POOL_NAME'"
    fi

    # Destroy and undefine network
    NET_NAME="net_${POOL_NAME}"
    if virsh net-info "$NET_NAME" &>/dev/null; then
      virsh net-destroy "$NET_NAME" 2>/dev/null || true
      virsh net-undefine "$NET_NAME" 2>/dev/null || true
      echo "🗑️  Network '$NET_NAME' removed"
    else
      echo "ℹ️  No network found for '$NET_NAME'"
    fi

    # Remove files
    if [[ -d "$VMPATH" ]]; then
      rm -rf "$VMPATH"
      echo "🗑️  Removed VM folder: $VMPATH"
    else
      echo "ℹ️  VM folder already removed: $VMPATH"
    fi

    if [[ -f "$WORKDIR/qemu/seed/${NAME}-seed.img" ]]; then
      rm -f "$WORKDIR/qemu/seed/${NAME}-seed.img"
      echo "🗑️  Removed seed image for '$NAME'"
    fi

    echo "✅ All resources for '$NAME' deleted"
    ;;

  version)
    echo "$VERSION"
    ;;

  help)
    echo "Usage:"
    echo "  $0 {bootstrap|create|apply|destroy|ssh|delete|ls|start|stop|version|help} VM_NAME DISTRO [RAM_MB] [CPUs] [Disk_GB]"
    ;;


  *)
    echo "Usage: $0 {bootstrap|create|apply|destroy|ssh|delete|ls|start|stop} VM_NAME DISTRO [RAM_MB] [CPUs] [Disk_GB]"
    ;;
esac
