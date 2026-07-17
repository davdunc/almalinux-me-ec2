# Handoff — AlmaLinux M&E on EC2

Status as of **2026-07-17**: complete, live-tested end to end, demo-ready
for the *AlmaLinux M&E For You* workshop at AlmaLinux Day: Los Angeles
(2026-07-18). The validation instance has been terminated; everything
needed to reproduce it is in this repository.

## What this project is

A reproducible EC2 build of an [AlmaLinux Media & Entertainment
edition](https://almalinux.org/almalinux-day-los-angeles-2026/)–style
workstation: the official AlmaLinux OS 10 AMI, configured by Ansible
into KDE Plasma + the open-source creative suite, streamed via Amazon
DCV. The M&E SIG has not yet published official kickstarts or repos, so
"M&E-style" here means replicating the edition's published composition
(KDE Plasma + GIMP, Krita, Inkscape, Blender, FreeCAD, Kdenlive, OBS
Studio, Ardour, Audacity, …).

## Operating it

Full steps and timings: README "Quick start" and "Workshop demo
walkthrough". Short version:

```bash
./scripts/launch-instance.sh -k <key-pair> -p <aws-profile>   # ~2 min
# then on the instance:
git clone https://github.com/davdunc/almalinux-me-ec2.git
cd almalinux-me-ec2 && ./bootstrap.sh                          # ~20-25 min
sudo passwd ec2-user
# browser → https://<address>:8443
```

Everything is idempotent — re-run `bootstrap.sh` freely after failures
or after editing `ansible/group_vars/all.yml`.

Persistent (free) AWS resources the launch script creates and reuses
per account: security group `almalinux-me-workshop` (22 + 8443 open to
the world — workshop convenience, tighten for anything long-lived), IAM
role/instance profile `almalinux-me-workshop-dcv-license`, and whatever
EC2 key pair you pass with `-k`.

## Hard-won knowledge (all found by live testing, 2026-07-16)

Nine issues were found and fixed during a full live validation run.
They are institutional knowledge for anyone doing EL10 desktop work:

1. **Not every account has a default VPC** — the launch script
   auto-discovers a VPC/public subnet and takes `-V`/`-n` overrides.
2. **`python3-libdnf5` is Fedora-only** — EL10 ships dnf4; plain
   `ansible-core` works.
3. **community.general ≥ 12 breaks on EL10's ansible-core 2.16** —
   pinned `<12` in `bootstrap.sh`; the `yaml` stdout callback is gone
   too, so `ansible.cfg` sticks to built-ins.
4. **htop/tmux live in EPEL** — repos must be enabled before core
   tooling installs (ordering matters in the base role).
5. **Transient DNS/mirror failures happen** — RPM Fusion and DCV
   downloads retry 3× with 10 s delay; conference wifi will be worse.
6. **firewalld is active by default on EL10** — the dcv role opens
   `dcv_port` explicitly; the security group alone is not enough.
7. **DCV licensing on EC2 needs IAM** — without `s3:GetObject` on
   `arn:aws:s3:::dcv-license*/*` via an instance profile, DCV runs a
   time-limited demo license and drops sessions. The launch script
   creates/attaches the profile automatically (soft-fails to a warning
   if the caller lacks IAM permissions).
8. **The big one — DCV cannot do Wayland, and EL10 cannot do X11
   desktops**: AlmaLinux 10 removed the Xorg server; EPEL 10's KDE
   Plasma is Wayland-only; Amazon DCV (≤ 2025.0) does not support
   Wayland. DCV *console* sessions therefore can never complete a KDE
   login on EL10. The design uses DCV **virtual sessions** inside the
   bundled `Xdcv` X server with **IceWM** — the only window manager
   packaged anywhere in the EL10 repo universe today (no XFCE, MATE,
   LXQt, openbox, or krdp in EPEL 10 yet).
9. **EPEL 10 creative coverage is thin**: only Krita, Kdenlive, and
   mpv exist as EL10 RPMs; GIMP, Inkscape, Blender, FreeCAD, Audacity,
   Ardour, OBS Studio, and HandBrake install from Flathub instead
   (two-tier lists in `group_vars/all.yml`).

## Costs

`t3.xlarge` + 60 GB gp3 ≈ **$0.17/hour (~$4/day)**. The complete live
validation, including five failed bootstrap iterations, cost under $1.
Terminate instances when done; the SG/IAM/key pair cost nothing.

## Future work

- **Switch remote desktop back to KDE** the day Amazon DCV ships
  Wayland support (the "DCV beta" on the AlmaLinux Day agenda): set
  `dcv_session_type: console` in `group_vars/all.yml`. That is the
  entire migration.
- **Migrate Flatpaks to RPMs** as packages land in EPEL 10 — move
  names from `media_flatpak_packages` to `media_dnf_packages`.
- **Packer golden AMI**: bake this playbook into a reusable AMI so
  studio instances boot ready-to-work (the natural next workshop).
- **GPU profile**: `-t g5.xlarge` + NVIDIA driver role for Blender
  Cycles / Resolve workloads.
- **Track the M&E SIG** (`sig-media-entertainment` on AlmaLinux
  Mattermost) — when official kickstarts/package lists publish,
  align `group_vars` with them.
