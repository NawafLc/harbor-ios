# Harbor for iPhone

A native iPhone client for your Harbor / Stremio setup, built with
[xtool](https://github.com/xtool-org/xtool) (no Mac needed).

**What carries over from Harbor on your PC:** you sign in with the same Stremio
account, so your addons (Torrentio, Comet, AIOStreams, TorBox, …), your Library
and Continue Watching all come over and stay in sync both ways. What you watch on
the iPhone shows up in Harbor on your PC, and vice versa.

**Features**
- Home rails from every addon catalog, plus Continue Watching with progress bars
- Search across all your addons
- Title pages with seasons/episodes, resume and "next episode"
- Stream list grouped by addon with the **EN DUB / EN DUB?** badges from your PC
  patch (same detection rules), quality and size pills, and an *EN DUB only* filter
- mpv player (same engine as Harbor on PC): MKV, HEVC, styled anime subs, audio
  and subtitle track picker, audio/subtitle sync (±0.1s), double-tap to skip 10s,
  English audio preferred automatically, extra subtitles from your subtitle addons
- Optional: torrent streams through a Stremio streaming server on your PC

---

## 1. One-time setup on your Windows PC (about 30–60 min, mostly downloads)

You need ~30 GB free disk space, your iPhone, and its USB cable.

### a) Install WSL (Ubuntu)
Open **PowerShell as Administrator**:
```powershell
wsl --install -d Ubuntu-24.04
```
Restart when asked, open **Ubuntu** from the Start menu, and pick a username/password.

### b) Install Swift 6.3 (inside Ubuntu)
```bash
sudo apt-get update
sudo apt-get install -y curl unzip usbmuxd libimobiledevice-utils
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
tar zxf swiftly-$(uname -m).tar.gz
./swiftly init --quiet-shell-followup
. "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
hash -r
swiftly install --use 6.3   # xtool's docs target Swift 6.3
hash -r
swift --version             # should say Swift version 6.3
```
If `swiftly init` prints a list of extra `apt-get install` packages, run that command too.

### c) Install xtool
```bash
curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o xtool
chmod +x xtool
sudo mv xtool /usr/local/bin/
xtool --help
```
(If it complains about FUSE: `sudo apt-get install -y libfuse2`.)

### d) Download Xcode (just the file, you won't run it)
In your browser, sign in at <https://developer.apple.com/download/all/?q=Xcode>
with any Apple ID and download **Xcode 26** (`Xcode_26.xip`, ~3 GB) to your
Windows **Downloads** folder.

### e) Log in and build the iOS SDK
```bash
xtool setup
```
- Login mode: choose **1 (Password)** unless you pay for the Apple Developer Program.
  Tip: a spare Apple ID is safest, since this uses Apple's private sign-in API.
- When asked for `Path to Xcode.xip`, enter (change the file name if yours differs):
  `/mnt/c/Users/moath/Downloads/Xcode_26.xip`

### f) Connect your iPhone to WSL
In **PowerShell as Administrator**:
```powershell
winget install usbipd
usbipd list                          # find your iPhone's BUSID, e.g. 2-3
usbipd bind --busid 2-3
usbipd attach --wsl --busid 2-3
```
Unlock the iPhone and tap **Trust**. Back in Ubuntu, `xtool devices` should list it.
(You need to run `usbipd attach --wsl --busid …` again after replugging/rebooting.)

### g) Turn on Developer Mode on the iPhone
Settings → Privacy & Security → **Developer Mode** → On (the phone restarts).

---

## 2. Build and install Harbor

Copy the project into Ubuntu (building from `/mnt/c` is very slow):
```bash
cp -r /mnt/c/Users/moath/Downloads/HarborMobile ~/HarborMobile
cd ~/HarborMobile
xtool dev
```
`xtool dev` builds, signs and installs the app on your phone. The first build
downloads the mpv libraries (~400 MB) and takes a while; later builds are quick.

If iOS says "Untrusted Developer": Settings → General → VPN & Device Management →
your Apple ID → **Trust**.

**Just want the .ipa file?**
```bash
xtool dev build --ipa
```
It writes `xtool/Harbor.ipa`. You can install that unsigned IPA with
Sideloadly or AltStore on Windows instead of using USB passthrough.

---

## 3. Good to know

- **7-day limit (free Apple ID):** the app stops opening after 7 days. Plug in and
  run `xtool dev` again; your login and settings are kept.
- **Torrent-only streams** need a streaming server. Debrid/direct links play
  directly. To play plain torrents, run Stremio's streaming server on your PC
  (port 11470), and in the app's Settings enter `http://<your-PC-IP>:11470`.
- **Addons** are managed from your Stremio account. Add or remove them in Harbor on
  your PC, then pull to refresh (or Settings → Sync now) on the phone.
- **Accounts:** email/password Stremio accounts only (Facebook/Apple sign-in
  accounts need a password set on stremio.com first).

## Project layout
```
Package.swift            SwiftPM manifest (depends on MPVKit for libmpv)
xtool.yml                bundle id, Info.plist and icon for xtool
Info.plist               display name, orientations, network permissions
Resources/AppIcon.png
Sources/Harbor/
  HarborApp.swift        app entry, tabs, theme, orientation lock
  Core/                  Stremio API, addon protocol, library sync, EN DUB detector
  Player/                mpv wrapper + player UI
  Views/                 Home, Search, Library, Settings, title page, streams
```

To change the bundle id (e.g. if xtool says it's taken), edit `bundleID` in `xtool.yml`.
