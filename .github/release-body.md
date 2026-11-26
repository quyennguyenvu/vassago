<!-- markdownlint-disable-file MD041 -->
<!-- Prepended to every release's auto-generated notes by release.yml. Keep it short and self-contained: this is the only guidance a downloader sees before hitting the first-launch warning. Keep it in sync with the README's Install section. -->

## Before you open it

Vassago isn't signed with a paid Apple certificate, so macOS blocks the **first** launch. Allow it once and the warning is gone for good. Full walkthrough: [README → Install][install].

[install]: https://github.com/quyennguyenvu/vassago#install

1. Open the `.dmg` and drag **Vassago** onto **Applications**. The one file runs on both Apple Silicon and Intel Macs.
2. Open Vassago. macOS says **"Apple could not verify 'Vassago' is free of malware"** — click **Done**, _not_ **Move to Trash** (the highlighted button, which deletes the app).
3. Allow it once, either way:
   - **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway**; or
   - run this in Terminal:

     ```sh
     xattr -dr com.apple.quarantine /Applications/Vassago.app
     ```

4. Turn Vassago on under **System Settings → Privacy & Security → Accessibility**. It presses Command+V for you when you pick a clip; without it, a pick only copies. If macOS also asks about the clipboard, or the menu bar shows `⚠`, choose **Always Allow** for Vassago under **Paste from Other Apps**.

## Updating from an earlier version

Replace the app in Applications. Every release is signed with the same certificate, so the Accessibility permission carries over. If picking a clip stops pasting after an update, open the panel, press **Reset Permission**, and switch Vassago on in the Settings page that opens.

## Verifying this file

`SHA256SUMS.txt` below covers the installer, and it carries a build provenance attestation:

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
gh attestation verify <file> --repo quyennguyenvu/vassago
```
