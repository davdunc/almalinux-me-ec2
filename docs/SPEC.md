# Specification — AlmaLinux M&E on EC2

Version 1.0 · 2026-07-17 · Status: implemented and live-verified

## 1. Goal

Provision, from nothing, a cloud workstation consistent with the
AlmaLinux OS 10 Media & Entertainment edition — KDE Plasma plus the
open-source creative application suite — on Amazon EC2, with a usable
remote desktop, using only two operator actions (one launch script, one
on-instance script).

### Non-goals

- Building or distributing a custom AMI or ISO (future work: Packer).
- Installing proprietary software (DaVinci Resolve is documented as a
  manual step; its EULA requires interactive download).
- Production multi-user or hardened deployments — this is a workshop
  and evaluation stack.

## 2. Requirements

### Functional

| ID | Requirement |
|----|-------------|
| F1 | Launch resolves the latest official AlmaLinux OS 10 x86_64 AMI dynamically (owner `764336703387`); no hardcoded AMI IDs |
| F2 | Launch works with or without a default VPC; VPC/subnet auto-discovered, overridable (`-V`/`-n`) |
| F3 | Region, instance type, profile, and volume size are flags with defaults (`us-west-2`, `t3.xlarge`, `default`, 60 GB gp3) |
| F4 | Security group opens 22 (SSH) and `dcv_port` (8443) and is reused across runs |
| F5 | A DCV-license IAM instance profile is created idempotently and attached; launch degrades with a warning if IAM is unavailable |
| F6 | One on-instance script (`bootstrap.sh`) converges the machine: Ansible install → collections → `site.yml` |
| F7 | Configuration matches M&E composition: KDE Plasma desktop, creative suite, multimedia codecs |
| F8 | A remote desktop reachable in a stock browser at `https://<host>:8443` after `sudo passwd ec2-user` |
| F9 | Package lists and all tunables are variables in `ansible/group_vars/all.yml` |
| F10 | Individual creative-app install failures are non-fatal and reported at end of run |

### Quality

| ID | Requirement |
|----|-------------|
| Q1 | Every step idempotent; `bootstrap.sh` safe to re-run at any point |
| Q2 | Network fetches (RPM Fusion, DCV bundle) retry 3× / 10 s |
| Q3 | No credentials, account IDs, or key material committed to the repo |
| Q4 | Fresh-account to working desktop in ≤ 30 minutes on `t3.xlarge` |

## 3. Architecture

```
Operator laptop                        EC2 instance (AlmaLinux 10)
───────────────                        ───────────────────────────
scripts/launch-instance.sh   ──run──▶  official AlmaLinux 10 AMI
  · AMI lookup by owner                bootstrap.sh
  · VPC/subnet discovery                 · dnf: ansible-core git
  · SG (22, 8443)                        · galaxy: community.general<12,
  · IAM dcv-license profile                       ansible.posix
  · 60 GB gp3 root                       · ansible-playbook site.yml
                                            ├─ base:    update, CRB, EPEL,
Browser ◀──── https://host:8443 ────┐       │           core pkgs, firewalld
                                    │       ├─ desktop: KDE Plasma (Wayland,
                              Amazon DCV     │           console), SDDM,
                              virtual        │           graphical.target
                              session        ├─ media:  RPM Fusion, EPEL RPMs,
                              (Xdcv + IceWM) │           Flathub apps, ffmpeg
                                    └────────┴─ dcv:    server (el9 bundle),
                                                        firewalld port, virtual
                                                        session systemd unit
```

Role dependency: `desktop` and `media` declare `dependencies: [base]`
(`meta/main.yml`) so tagged runs still get repos.

## 4. Package composition (verified against live repos, 2026-07-16)

| Tier | Source | Contents |
|------|--------|----------|
| Desktop | EPEL 10 | `@KDE Plasma Workspaces`, SDDM |
| Native RPMs | EPEL 10 | Krita, Kdenlive, mpv |
| Codecs | RPM Fusion el10 | ffmpeg (nonfree-enabled build), gstreamer plugins |
| Flatpaks | Flathub | GIMP, Inkscape, Blender, FreeCAD, Audacity, Ardour, OBS Studio, HandBrake |
| Remote shell | AlmaLinux 10 | IceWM, xterm (virtual sessions only) |

Migration rule: when an app lands in EPEL 10, move it from
`media_flatpak_packages` to `media_dnf_packages`.

## 5. Remote display — decision record

**Decision: Amazon DCV virtual sessions (bundled Xdcv X server) with an
IceWM shell; KDE Plasma remains the console desktop.**

Constraints that force this (all verified):

1. Amazon DCV (through 2025.0) does not support the Wayland protocol;
   console sessions require an X server.
2. AlmaLinux 10 does not ship an Xorg server (removed in RHEL 10).
3. EPEL 10's KDE Plasma is Wayland-only; `plasma-workspace-x11`,
   XFCE, MATE, LXQt, openbox, and krdp are not packaged for EL10.
4. IceWM is the only window manager available in the EL10 repo
   universe; Xdcv (bundled with DCV) provides the X server without
   system Xorg.

Consequences: browser sessions show IceWM, not Plasma. Reversal path:
`dcv_session_type: console` once DCV Wayland support ships. The DCV
server itself is the **el9** 2025.0 bundle (no el10 build exists);
installs cleanly on EL10 via ABI compatibility.

## 6. Security posture

- Repo contains no secrets, no account IDs; AMI owner ID is the public
  AlmaLinux Foundation publishing account.
- IAM role is single-statement, read-only: `s3:GetObject` on
  `arn:aws:s3:::dcv-license*/*` (DCV licensing requirement on EC2).
- Security group is world-open on 22/8443 by design for workshops;
  documented as needing tightening for anything long-lived.
- DCV uses its self-signed certificate; session auth is PAM
  (`ec2-user` password, set manually by the operator — never
  provisioned).

## 7. Acceptance criteria (all verified live, 2026-07-16)

1. `launch-instance.sh` on an account **without** a default VPC reaches
   "Instance ready" and prints a public address.
2. `bootstrap.sh` on a fresh instance exits 0 with `PLAY RECAP
   failed=0` and reports zero unavailable packages.
3. Re-running `bootstrap.sh` converges with no failures and minimal
   changes (observed: `ok=35 changed=3`).
4. After reboot: `graphical.target` default, SDDM and dcvserver active.
5. DCV log shows `Retrieved license object from AWS S3 bucket` (no
   demo-license warnings).
6. A boot-persistent virtual session exists (`dcv list-sessions` shows
   `workshop`, type virtual) with `Xdcv` and `icewm` running as the
   session owner.
7. `https://<host>:8443` answers HTTP 200 with `Server: dcv`, and a
   browser login as `ec2-user` reaches a usable desktop with the
   creative apps launchable. *(Confirmed interactively.)*

## 8. Configuration reference

All in `ansible/group_vars/all.yml`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `base_full_update` | `true` | Full `dnf` update in base role |
| `base_packages` | git, vim, tmux, htop, … | Core tooling |
| `desktop_environment_group` | `@KDE Plasma Workspaces` | Console desktop |
| `desktop_display_manager` | `sddm` | Display manager |
| `rpmfusion_free_url` / `rpmfusion_nonfree_url` | el10 release RPMs | Codec repos |
| `media_dnf_packages` | krita, kdenlive, mpv | EL10-native creative RPMs |
| `media_flatpak_packages` | 8 apps | Flathub tier |
| `codec_packages` | ffmpeg, gstreamer | Multimedia |
| `install_dcv` | `true` | Toggle the dcv role |
| `dcv_bundle_url` | el9 2025.0 tarball | DCV server bundle |
| `dcv_session_type` | `virtual` | `console` once DCV supports Wayland |
| `dcv_session_name` / `dcv_session_owner` | `workshop` / `ec2-user` | Session identity |
| `dcv_port` | `8443` | Server port (matches SG + firewalld) |
| `dcv_virtual_packages` | icewm, xterm | X11 shell for virtual sessions |
