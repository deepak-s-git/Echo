<p align="center">
  <img src="Echo/Assets.xcassets/AppIcon.appiconset/appicon_128x128.png" width="128" height="128" alt="Echo Icon" />
</p>

<h1 align="center">ECHO</h1>

<p align="center">
  <b>Recall and continue your working context instantly.</b>
</p>

<p align="center">
  <a href="https://github.com/deepak-s-git/Echo/actions"><img src="https://img.shields.io/badge/Build-passing-success?style=flat-square&logo=github" alt="Build Status" /></a>
  <a href="https://echo-macos.vercel.app/appcast.xml"><img src="https://img.shields.io/badge/Sparkle_Feed-active-orange?style=flat-square&logo=rss" alt="Sparkle Feed" /></a>
  <a href="https://github.com/deepak-s-git/Echo/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License" /></a>
  <img src="https://img.shields.io/badge/Platform-macOS_14.0+-black?style=flat-square&logo=apple" alt="Platform Support" />
</p>

---

Say hello to **Echo**, a lightweight and privacy-first workflow memory assistant for macOS. Echo automatically records the apps, browser tabs, and windows you focus on. When you're ready to switch back to a task, Echo lets you restore your entire workspace state with a single click.

*No cloud syncing, no accounts, and no data tracking. Everything stays local on your Mac.*

---

## Features

- **Workflow Timeline**: Track your active sessions and view a chronological map of what you worked on.
- **Browser Tab Scraper**: Captures active URLs from Google Chrome, Safari, Arc, and more.
- **Smart Timing Rules**: Custom thresholds for app stay duration, tab focus delay, and tab eligibility to prevent noise.
- **Accent Vibes**: Customize the aesthetic with premium visual styles (Cybernetic Copper, Nordic Frost, Sunset Rose, Forest Mint, Neon Noir).
- **Privacy Controls**: Exclude specific apps (like Spotify or System Preferences) and customize automatic data retention limits.
- **Sparkle Auto-Updates**: Seamless, automatic update downloads directly in the background.

---

## Installation & Bypass Gatekeeper

### Option 1: Direct Download (Recommended)

[![Download Echo](https://img.shields.io/badge/Download_app_for-macOS-black?style=for-the-badge&logo=apple)](https://echo-macos.vercel.app/Echo.dmg)

> [!IMPORTANT]
> Because Echo is distributed independently without App Store notarization, macOS will show a warning saying **"Echo cannot be opened because the developer cannot be verified"** on the first launch. 
> You can bypass this in seconds using one of the methods below:

#### Method A: Terminal (Fastest & Easiest)
After downloading and moving Echo to your `/Applications` folder, open Terminal and run:
```bash
xattr -dr com.apple.quarantine /Applications/Echo.app
```
Now, you can open the app normally!

#### Method B: System Settings
1. Try opening **Echo**—you'll see the warning popup. Click **Cancel**.
2. Open **System Settings > Privacy & Security**.
3. Scroll down to the **Security** section.
4. Click **Open Anyway** next to the warning for Echo.
5. Enter your Mac credentials and click **Open**.

---

## Building from Source

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later

### Build Instructions
1. Clone the repository:
   ```bash
   git clone https://github.com/deepak-s-git/Echo.git
   cd Echo
   ```
2. Open the project in Xcode:
   ```bash
   open Echo.xcodeproj
   ```
3. Set your signing team in **Signing & Capabilities** to your own developer account.
4. Press `Cmd + R` to build and run!

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=deepak-s-git/Echo&type=Date)](https://star-history.com/#deepak-s-git/Echo&Date)
