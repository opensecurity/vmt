# vmt

> 🌀 Lightweight Bash CLI for managing KVM virtual machines using `libvirt`, `cloud-init`, and `terraform`.

---

## 🛠 What It Does

`vmt` automates the lifecycle of local KVM virtual machines through a simple command-line interface. It uses:

* **KVM/QEMU** - fast, native Linux virtualization
* **libvirt** - VM orchestration (domains, pools, networks)
* **Terraform** - declarative configuration and lifecycle control
* **cloud-init** - inject SSH keys and configure VMs on first boot
* **pure Bash** - no Python, Go, or compiled binaries

Once the image is cached, everything runs offline and locally - ideal for air-gapped, reproducible, or automated setups.

---

## 🧰 Installation

Install `vmt` using the official installer:

```bash
curl -fsSL https://raw.githubusercontent.com/opensecurity/vmt/main/install.sh | bash
```

This will:

* Download the latest version of the `vmt` script into `~/.vmt`
* Link it as `vmt` into `~/.local/bin/`
* Make it executable and ready to use

---

## 🔧 Dependencies

`vmt` relies on standard tools available on most Linux distributions:

| Tool            | Role                                  |
| --------------- | ------------------------------------- |
| `bash`          | Shell environment                     |
| `virsh`         | libvirt CLI for domains, networks     |
| `qemu-system`   | Hypervisor engine for VM execution    |
| `terraform`     | Declarative infrastructure management |
| `cloud-localds` | Generate cloud-init seed disks        |
| `ssh` / `scp`   | Key injection and access              |
| `curl`          | Download base OS images               |

A `vmt doctor` command is planned to automatically detect and verify dependencies for RHEL and Debian-based systems.

---

## 📦 Supported Distributions

Out-of-the-box support:

* Ubuntu 24.04 (Minimal Cloud Image)
* AlmaLinux 9 (Generic Cloud)
* RockyLinux 9 (Generic Cloud)

More distributions can be added by editing the `DISTRO` case logic in the script.

---

## 🚀 CLI Usage

```bash
vmt <action> <vm_name> [distro] [ram_mb] [cpus] [disk_gb]
```

### Available Actions

| Command     | Description                           |
| ----------- | ------------------------------------- |
| `bootstrap` | Generate shared SSH key pair          |
| `create`    | Prepare disk, seed image, and config  |
| `apply`     | Launch VM with Terraform              |
| `start`     | Start a defined VM                    |
| `stop`      | Gracefully shutdown a running VM      |
| `ssh`       | Connect via SSH using generated key   |
| `ls`        | List all VMs, IPs, OS, and status     |
| `destroy`   | Run `terraform destroy` only          |
| `delete`    | Fully remove VM, storage, and network |
| `version`   | Show CLI version                      |
| `help`      | Show CLI usage summary                |

---

## 🗂 File Structure

Each VM is created under:

```
~/vms/<vm_name>/
├── qemu/images/      # Disk image
├── qemu/seed/        # cloud-init seed.img
├── cloudinit/        # user-data and meta-data
└── terraform/        # Terraform definition
```

Global:

* `~/vms/.images/`: Cached base OS images
* `~/vms/.ssh/id_ed25519`: Shared SSH key pair
* `~/vms/logs/*.log`: Logs for each VM run

---

## 🔐 SSH Access

All VMs are configured with:

* `devops` user
* Public key injected via `cloud-init`
* `NOPASSWD` sudo access
* QEMU guest agent installed and enabled

Example:

```bash
vmt ssh myvm
```

Or directly:

```bash
ssh -i ~/vms/.ssh/id_ed25519 devops@<ip>
```

---

## 📋 Example Workflow

### Generate SSH key (one-time)

```bash
vmt bootstrap
🕒 2025-05-09 00:32:54 - Running: vmt bootstrap
🔑 Generating SSH key for VM access...
Generating public/private ed25519 key pair.
Your identification has been saved in /home/dev/vms/.ssh/id_ed25519
Your public key has been saved in /home/dev/vms/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:QcA4JTKQWII0OVc***
The key's randomart image is:
****
✅ SSH key generated at /home/dev/vms/.ssh/id_ed25519
```
```bash
vmt create securevm almalinux 4096 2 40
🕒 2025-05-09 00:34:57 - Running: vmt create securevm almalinux 4096 2 40
✅ SSH key already exists: /home/dev/vms/.ssh/id_ed25519
Pool vmt_securevm defined

Pool vmt_securevm built

Pool vmt_securevm started

Pool vmt_securevm marked as autostarted

Network net_vmt_securevm defined from /home/dev/vms/securevm/qemu/network.xml

Network net_vmt_securevm started

Network net_vmt_securevm marked as autostarted

✅ Created and started libvirt network: net_vmt_securevm
📦 Checking for base image in cache...
⬇️  Downloading base image to /home/dev/vms/.images/alma-cloud.qcow2...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  468M  100  468M    0     0  93.5M      0  0:00:05  0:00:05 --:--:-- 94.6M
🔍 Verifying downloaded image...
✅ Image verified: /home/dev/vms/.images/alma-cloud.qcow2
✅ Cached base image at /home/dev/vms/.images/alma-cloud.qcow2
📁 Copying base image to VM directory...
✅ VM config created in /home/dev/vms/securevm
```

### Launch the VM with Terraform
```bash
vmt apply securevm
🕒 2025-05-09 00:36:01 - Running: vmt apply securevm
🧹 Checking for existing domain in libvirt...
Initializing the backend...
Initializing provider plugins...
- Finding dmacvicar/libvirt versions matching "~> 0.7.6"...
- Installing dmacvicar/libvirt v0.7.6...
- Installed dmacvicar/libvirt v0.7.6 (self-signed, key ID 0833E38C51E74D26)
Partner and community providers are signed by their developers.
If you'd like to know more about provider signing, you can read about it here:
https://www.terraform.io/docs/cli/plugins/signing.html
Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # libvirt_domain.securevm will be created
  + resource "libvirt_domain" "securevm" {
      + arch        = (known after apply)
      + autostart   = (known after apply)
      + emulator    = (known after apply)
      + fw_cfg_name = "opt/com.coreos/config"
      + id          = (known after apply)
      + machine     = (known after apply)
      + memory      = 4096
      + name        = "securevm"
      + qemu_agent  = false
      + running     = true
      + type        = "kvm"
      + vcpu        = 2

      + boot_device {
          + dev = [
              + "hd",
            ]
        }

      + console {
          + source_host    = "127.0.0.1"
          + source_service = "0"
          + target_port    = "0"
          + target_type    = "serial"
          + type           = "pty"
        }

      + cpu {
          + mode = "host-passthrough"
        }

      + disk {
          + scsi      = false
          + volume_id = (known after apply)
        }
      + disk {
          + scsi      = false
          + volume_id = (known after apply)
        }

      + graphics {
          + autoport       = true
          + listen_address = "127.0.0.1"
          + listen_type    = "none"
          + type           = "spice"
        }

      + network_interface {
          + addresses    = (known after apply)
          + hostname     = (known after apply)
          + mac          = (known after apply)
          + network_id   = (known after apply)
          + network_name = "net_vmt_securevm"
        }
    }

  # libvirt_volume.base will be created
  + resource "libvirt_volume" "base" {
      + format = "qcow2"
      + id     = (known after apply)
      + name   = "securevm-base"
      + pool   = "vmt_securevm"
      + size   = (known after apply)
      + source = "./../qemu/images/alma-cloud.qcow2"
    }

  # libvirt_volume.disk will be created
  + resource "libvirt_volume" "disk" {
      + base_volume_id = (known after apply)
      + format         = (known after apply)
      + id             = (known after apply)
      + name           = "securevm.qcow2"
      + pool           = "vmt_securevm"
      + size           = 42949672960
    }

  # libvirt_volume.seed will be created
  + resource "libvirt_volume" "seed" {
      + format = "raw"
      + id     = (known after apply)
      + name   = "securevm-seed.img"
      + pool   = "vmt_securevm"
      + size   = (known after apply)
      + source = "./../qemu/seed/securevm-seed.img"
    }

Plan: 4 to add, 0 to change, 0 to destroy.
libvirt_volume.base: Creating...
libvirt_volume.seed: Creating...
libvirt_volume.base: Creation complete after 1s [id=/home/dev/vms/securevm/qemu/securevm-base]
libvirt_volume.disk: Creating...
libvirt_volume.seed: Creation complete after 1s [id=/home/dev/vms/securevm/qemu/securevm-seed.img]
libvirt_volume.disk: Creation complete after 0s [id=/home/dev/vms/securevm/qemu/securevm.qcow2]
libvirt_domain.securevm: Creating...
libvirt_domain.securevm: Creation complete after 1s [id=cf38d944-0d11-4743-80be-73db495e190f]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
🚀 VM 'securevm' is ready.
🔍 Waiting for IP address...
🔑 SSH: ssh -i /home/dev/vms/.ssh/id_ed25519 devops@192.168.185.230
```

### List status and IP
```bash
vmt ls
🕒 2025-05-09 00:39:27 - Running: vmt ls
📂 All VMs in /home/o/vms:
• alma                 • 192.168.179.249  • AlmaLinux • running     
• securevm             • 192.168.185.230  • AlmaLinux • running   
```

### Connect via SSH
```bash
vmt ssh securevm
🕒 2025-05-09 00:40:12 - Running: vmt ssh securevm
Warning: Permanently added '192.168.185.230' (ED25519) to the list of known hosts.
[devops@securevm ~]$ 
```

### Clean up
```bash
vmt destroy securevm
vmt delete securevm
```

---

## 🧠 Implementation Notes

* Cloud-init handles provisioning, so no guest image modification is needed
* All disk images use QCOW2 with base + diff layers for efficiency
* `qemu-guest-agent` is installed by default for IP resolution and shutdown
* Logs are captured per-VM in `~/vms/.logs/`
* `trap` and `set -euo pipefail` ensure reliable scripting behavior

---

## 🪪 License

MIT - see [LICENSE](https://github.com/opensecurity/vmt/blob/main/LICENSE)
