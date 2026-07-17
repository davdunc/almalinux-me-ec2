# AlmaLinux M&E on EC2

Build an [AlmaLinux Media & Entertainment edition](https://almalinux.org/almalinux-day-los-angeles-2026/)–style
workstation in the cloud: launch the official **AlmaLinux OS 10** AMI on
Amazon EC2, then configure it with **Ansible** to match the M&E edition's
composition — KDE Plasma plus the open-source creative tool suite (GIMP,
Krita, Inkscape, Blender, FreeCAD, Kdenlive, OBS Studio, Ardour,
Audacity, and friends), with **Amazon DCV** for a real remote desktop.

Built for the *AlmaLinux M&E For You* hands-on workshop at
**AlmaLinux Day: Los Angeles 2026** (July 18, 2026).

## Prerequisites

- An AWS account with an EC2 key pair in your target region
- AWS CLI v2 configured (`aws configure`)
- Bash (the launch script) — Ansible is installed *on the instance* for
  you, so nothing else is needed locally

## Quick start

**1. Launch the instance** (from your laptop):

```bash
./scripts/launch-instance.sh -k <your-key-pair-name> [-r us-west-2] [-t t3.xlarge] [-p aws-profile]
```

The script finds the latest official AlmaLinux OS 10 x86_64 AMI
(published by the AlmaLinux OS Foundation), creates a security group
opening SSH (22) and DCV (8443), attaches a 60 GB gp3 root volume
(a desktop plus creative apps does not fit in the default 10 GB), tags
the instance, and prints its public address.

**2. Configure it as an M&E workstation** (on the instance):

```bash
ssh -i <your-key.pem> ec2-user@<public-dns>
sudo dnf -y install git
git clone https://github.com/davdunc/almalinux-me-ec2.git
cd almalinux-me-ec2
./bootstrap.sh
```

`bootstrap.sh` installs Ansible, then runs `ansible/site.yml` against
localhost. Expect **15–30 minutes** — it is a full desktop environment
plus a large application suite. It is safe to re-run if interrupted.

**3. Reboot and connect:**

```bash
sudo reboot
```

Then open `https://<public-dns>:8443` in a browser (self-signed
certificate warning is expected). Set a password for `ec2-user` first
(`sudo passwd ec2-user`) so you can log in to the session.

> **Why the remote desktop is IceWM, not KDE:** AlmaLinux 10 removed
> the Xorg server and EPEL 10's KDE Plasma is Wayland-only — but
> Amazon DCV does not support Wayland yet (that support is what AWS
> demos as the "DCV beta"). So remote DCV sessions run as *virtual*
> sessions inside DCV's bundled X server with IceWM as a lightweight
> shell — right-click the desktop for the menu; every creative app
> (Blender, GIMP, Kdenlive, …) runs there. KDE Plasma remains the
> console desktop, ready for when DCV Wayland support lands — then set
> `dcv_session_type: console` in `ansible/group_vars/all.yml`.

## Workshop demo walkthrough

Timings below are from a real end-to-end run on a `t3.xlarge`
(2026-07-16). Total cost of a full demo run is well under $1.

**Before the session (10 minutes, do this in advance):**

1. Have an AWS account, an EC2 key pair in your region, and AWS CLI v2
   configured. Clone this repo.
2. Launch the instance — **~2 minutes** to running:
   ```bash
   ./scripts/launch-instance.sh -k <key-pair> [-p profile] [-r region]
   ```
3. Start the build immediately — it needs **~20–25 minutes**, so kick
   it off before you start talking:
   ```bash
   ssh -i <key.pem> ec2-user@<address>
   sudo dnf -y install git
   git clone https://github.com/davdunc/almalinux-me-ec2.git
   cd almalinux-me-ec2 && ./bootstrap.sh
   ```
   It is safe to re-run if the network hiccups — every step is
   idempotent.

**Live demo (10–15 minutes):**

4. Show the playbook output finishing: the PLAY RECAP and the
   "creative packages" report (which apps came from EPEL 10 RPMs vs
   Flathub — a great EL10-ecosystem talking point).
5. Set a session password: `sudo passwd ec2-user`
6. Open `https://<address>:8443` in a browser, accept the self-signed
   certificate, log in as `ec2-user`. You land in the DCV virtual
   session — right-click the desktop for the application menu.
7. Launch something visual: Blender or Krita for instant effect;
   Kdenlive for the video-editing crowd. Mention every app streams
   from a $0.17/hr cloud instance.
8. Show the customization point of the workshop: open
   `ansible/group_vars/all.yml` and demonstrate tailoring
   `media_dnf_packages` / `media_flatpak_packages` into a
   studio-specific image, then re-run `./bootstrap.sh` to converge.

**Talking points:**

- Why the remote desktop is IceWM, not Plasma (EL10 Wayland vs DCV —
  see the note above) and what the Amazon DCV Wayland beta changes.
- DaVinci Resolve stays a manual install (proprietary EULA).
- GPU instances (`-t g5.xlarge` + NVIDIA driver) as the follow-on for
  real GPU workloads.

**Teardown (30 seconds):**

```bash
aws ec2 terminate-instances --instance-ids <instance-id> [--profile ... --region ...]
```

The security group, key pair, and DCV-license IAM profile are free and
reusable — leave them for the next run.

## What gets installed

| Role | Contents |
|---|---|
| `base` | System update, core tools, CRB + EPEL repositories |
| `desktop` | KDE Plasma Workspaces (EPEL), SDDM, graphical boot target |
| `media` | RPM Fusion free/nonfree, creative apps (RPM + Flathub), ffmpeg |
| `dcv` | Amazon DCV server with an automatic console session (optional) |

Enterprise Linux 10 is young, so the creative suite is installed in two
tiers (verified July 2026):

- **Native RPMs** (EPEL 10): Krita, Kdenlive, mpv — plus ffmpeg and
  codecs from RPM Fusion el10
- **Flatpaks** (Flathub): GIMP, Inkscape, Blender, FreeCAD, Audacity,
  Ardour, OBS Studio, HandBrake — none of these have EL10 builds in
  EPEL/RPM Fusion yet

Package lists and toggles live in `ansible/group_vars/all.yml` — edit
`media_dnf_packages` / `media_flatpak_packages` to tailor your own
studio image (and migrate apps to the RPM list as they land in EPEL 10),
or set `install_dcv: false` to skip remote desktop.

Every app install is **skipped-not-fatal** and reported at the end of
the playbook run.

### DaVinci Resolve

DaVinci Resolve is proprietary and requires accepting Blackmagic's EULA
at download time, so it is **not** installed automatically. Download it
from [blackmagicdesign.com](https://www.blackmagicdesign.com/products/davinciresolve)
and install it on the instance manually.

## Notes

- **Amazon DCV licensing**: DCV is free to use on EC2, but the server
  must be able to read the regional `dcv-license.<region>` S3 bucket —
  otherwise it runs on a time-limited demo license. The launch script
  creates and attaches a minimal read-only IAM instance profile
  (`almalinux-me-workshop-dcv-license`) automatically; details in the
  [DCV licensing docs](https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-license.html).
- **DCV on EL10**: as of July 2026 there is no el10 DCV build, so this
  repo installs the **el9** 2025.0 bundle, which generally works via
  ABI compatibility. If dependency resolution fails on your instance,
  set `install_dcv: false` in `group_vars/all.yml` and check for a
  newer bundle at the [DCV download page](https://www.amazondcv.com/).
- **GPU instances**: for actual GPU-accelerated work (Blender Cycles,
  Resolve), launch on `g4dn`/`g5`/`g6` (`-t g5.xlarge`) and add the
  NVIDIA driver — a good workshop follow-on exercise.
- **Security group** opens 22 and 8443 to the world for workshop
  convenience. Tighten the CIDRs for anything longer-lived.
- **Golden AMI**: the natural next step is baking this configuration
  into a reusable AMI with Packer + this same playbook, so studio
  instances boot ready-to-work. Contributions welcome.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
