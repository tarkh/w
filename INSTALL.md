# Installing W

**English** · [Русский](docs/ru/INSTALL.md)

The short version: download the image, boot it, answer the wizard, reboot. This
page has the details — and how to build the image yourself.

## Requirements

- x86_64 machine with **UEFI** firmware
- A disk W may erase — or **40 GiB of free space** on a disk next to another
  system, such as Windows
- A working internet connection during installation

## Installing

1. **Get an ISO** — [**download the install image**](https://github.com/tarkh/w/releases/tag/edge).

   There is one image, and it is rebuilt every night from this repository. W is a
   rolling distribution, so freezing a download per version would only hand you
   older packages to update on first boot. The file names itself
   `w-<release>-<build date>-x86_64.iso`, and the installed system records the
   same two facts in `/etc/os-release` as `IMAGE_VERSION` and `W_BUILD_DATE`:
   which version of W's own configuration it is, and which day its packages came
   from Arch.

   The release page carries the image's SHA-256; the file is replaced by every
   nightly build, so check it against the download you actually have:

   ```sh
   sha256sum w-*-x86_64.iso
   ```

   Or [build your own](#building-your-own-iso) — the same build that produces
   the published image, and the way to get an image for hardware the default one
   does not cover.

2. **Write it to a USB stick** of 2 GB or more — everything on the stick is
   erased. Write the image byte for byte onto the whole device: with Secure Boot
   on, the stick boots only as an exact copy of the image. Ventoy, or copying the
   image's files onto a formatted stick, does not give one.

   - **Linux** — find the stick in `lsblk`: the whole disk, such as `/dev/sdb`,
     not a partition. `dd` overwrites whatever device it is given, without asking.

     ```sh
     sudo dd if=w-*-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
     ```

   - **Windows** — [Rufus](https://rufus.ie): choose the stick and the ISO, then
     **START**. Rufus says it writes this image in DD mode — that is the right
     mode. If Windows then offers to format the disk, press **Cancel**.

   - **macOS** — find the stick in `diskutil list` as `/dev/diskN`, then:

     ```sh
     diskutil unmountDisk /dev/diskN
     sudo dd if=w-*-x86_64.iso of=/dev/rdiskN bs=4m
     diskutil eject /dev/diskN
     ```

     If macOS says the disk is not readable, choose **Ignore**. Without a
     terminal, [balenaEtcher](https://etcher.balena.io) writes the image the
     same way: the ISO, the stick, **Flash**.

3. **Boot it.** The installer starts by itself on the first console. If you leave
   it, bring it back with `bash /root/w/scripts/install.sh`.

   Secure Boot can stay on. The first time a machine sees this image, a blue
   key-management screen asks you to trust it once — the steps, and the hash to
   compare, are in
   [Installing with Secure Boot on](rootfs/usr/share/doc/w/guide/security.md#installing-with-secure-boot-on).

4. **Answer the wizard.** For the disk you choose between erasing it whole and
   installing **into its free space**, which leaves every existing partition
   untouched — shrink Windows from Windows first
   ([how](rootfs/usr/share/doc/w/faq.md)). Disk encryption is the default and the
   recommended choice. The wizard confirms once before touching the disk, and
   everything after that point is destructive — read that screen.

5. **Reboot.** The first boot finishes setup (packages, AUR builds, user
   environment) and logs the whole thing to `/var/log/w/`. With Secure Boot on,
   it starts with one more confirmation in the same blue screen — the installer's
   last screen shows the code it asks for. Some firmware refuses that request;
   the last screen then shows the steps to add the key from disk instead, no
   code ([details](rootfs/usr/share/doc/w/guide/security.md#installing-with-secure-boot-on)).

## Building your own ISO

The published image is not special — it is what this repository builds, and you
can build the same thing:

```sh
git clone https://github.com/tarkh/w
cd w
./scripts/build-iso.sh           # writes to archiso/out/
```

Run it as your normal user, **not** with `sudo`: it elevates only for `mkarchiso`
itself, and the AUR packages it bakes in must not be built as root. It needs
`archiso` and `base-devel` installed. On a machine that is not Arch — or if you
would rather not install those — `ci/iso-build-container.sh` runs the identical
build inside a container; that script is literally what produces the nightly
image, so its output is the published one.

The build takes roughly 10–20 minutes and writes `w-<release>-<date>-x86_64.iso`.

### Broadcom Wi-Fi: vintage MacBook Pro and friends

A handful of older Broadcom chips — BCM43142 `[14e4:4365]`, BCM4360 `[14e4:43a0]`,
the ones in machines like the 2013–2015 MacBook Pro — are in no in-kernel driver's
table. Linux shows them with no driver bound at all, and they need Broadcom's own
`wl` module.

The **installed** system handles this by itself: the installer detects such a chip
and installs the driver for it. What it cannot help with is the **live session**,
and that matters on a laptop with no Ethernet port: if the installer cannot bring
the network up, it cannot install anything. Until September 2026 the image covered
this because Arch shipped a prebuilt driver package; that package is gone from the
official repositories, and upstream archiso dropped it rather than replacing it.
Only a source (DKMS) package remains, so covering the live session again means
carrying a compiler and the kernel headers in the image — **about 570 MB before
compression, a measured 139 MB on the finished ISO** (1583 → 1722 MB), to build a
2 MB driver.

That is a bad trade for everyone who does not have such a chip, so it is off by
default. If you do have one, build yourself an image with it:

```sh
./scripts/build-iso.sh --broadcom-wl
```

Or, equivalently, set `BROADCOM_WL=on` near the top of `scripts/build-iso.sh` —
the option is a single line there, with the reasoning next to it.

You do not have to pick a driver version. The Broadcom source needs a fresh patch
for each new kernel series, and Arch lands the kernel before the rebuilt driver
leaves the testing repository — so during that window the ordinary package does
not compile against the kernel the ISO ships. The build resolves the newest
driver across all repositories and, if that one is still in testing, pulls in that
**single** package while everything else in the image continues to come from the
normal repositories.

The honest limit: if Arch ships a kernel series before the driver has a patch for
it at all, no version compiles and the build stops with a compiler error. There is
nothing to do about that but wait for the patch — or build with the option off.
