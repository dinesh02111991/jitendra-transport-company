# Build a test APK on GitHub (no local Flutter required)

1. Create a **private, empty** GitHub repository (do not initialize README/license).
2. Extract this ZIP. Open the `jitendra_transport` folder. Upload **its contents**, not the outer folder, into the repository. Include the hidden `.github/workflows/android-apk.yml` file. GitHub web uploader may need you to upload the workflow separately using **Add file → Create new file** and enter `.github/workflows/android-apk.yml` as the filename, pasting the workflow contents.
3. Commit to branch `main`.
4. Go to **Actions → Build Android Test APK → Run workflow → Run workflow** (or wait for the push-triggered run).
5. Open the completed run. Under **Artifacts**, download `Jitendra-Transport-Test-APK`.
6. Unzip the artifact, copy `app-debug.apk` to your Android phone, and install it (allow installing apps from that source if prompted).
7. Test adding a customer and vehicle, creating a trip, saving a bill/memo, creating a PDF, and sharing with WhatsApp. Verify data persists after closing and reopening the app.

## Troubleshooting
- **Workflow not visible:** Confirm file exists at `.github/workflows/android-apk.yml` on the repository's default branch.
- **Build failed:** Open Actions → failed run → `build` → expand the red step; copy the first meaningful error text.
- **Upload error:** Ensure `pubspec.yaml`, `lib/main.dart`, `assets/logo.png`, and `.github/workflows/android-apk.yml` are at the repository root.
- **Debug APK warning:** Debug builds are for personal testing, not Play Store distribution. A release build requires managing a persistent signing key securely.
- **Important:** The current app source still has the previous quotation-style memo generation. The separately approved memo PDF header/wording has **not** yet been integrated into the Dart source. Do not use the generated memo for live business until that integration is done.
- **Data:** Uninstalling the app or clearing its data removes local records. No backup/export yet.
