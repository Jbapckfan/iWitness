# App Store Screenshot Plan -- OnTheRecord

This document specifies the screenshot concepts, captions, and requirements for the App Store listing.

---

## Device Size Requirements

Apple requires screenshots for the following display sizes. The two mandatory sizes for all iPhone apps are:

| Display Size | Devices                                      | Resolution (Portrait) | Required |
|--------------|----------------------------------------------|-----------------------|----------|
| 6.7-inch     | iPhone 16 Plus, 15 Plus, 15 Pro Max, 14 Pro Max | 1290 x 2796 px       | Yes      |
| 6.5-inch     | iPhone 14 Plus, 13 Pro Max, 12 Pro Max, 11 Pro Max, XS Max | 1242 x 2688 px | Yes |

You may upload up to 10 screenshots per size. A minimum of 3 is required; 6 or more is recommended.

---

## Screenshot Concepts (6 Screenshots)

The same 6 concepts are used for both the 6.7-inch and 6.5-inch sizes. Each screenshot is captured at the native resolution for its respective device. The visual content and captions are identical across sizes; only the resolution differs.

---

### Screenshot 1: Hero / One-Tap Recording

**What to show:**
The main recording screen with the large record button prominently displayed. The screen should show the app in its ready state -- camera preview visible (dual-camera layout if possible, showing front and rear feeds), the one-tap record button centered at the bottom, and a clean, confident UI. The status bar should show the time, signal, and battery.

**Caption text:**
**One tap. Full protection.**

**Notes:**
- This is the first screenshot users see -- it must immediately communicate what the app does.
- Show the dual-camera preview with a realistic scene (e.g., a well-lit room or outdoor setting).
- The record button should be visually prominent (red circle or similar).

---

### Screenshot 2: Real-Time Encrypted Backup

**What to show:**
The recording-in-progress screen. The UI should display:
- Active recording indicator (red dot / timer)
- Dual-camera feeds (front and rear, picture-in-picture or split)
- A visible upload/sync indicator showing chunks being encrypted and uploaded in real time
- An encryption status badge or lock icon indicating active protection

**Caption text:**
**Encrypted and backed up in real time.**

**Notes:**
- Show upload progress or a stream of successfully uploaded chunks.
- The visual emphasis is on the "already safe" concept -- the footage is being protected as it's captured.
- If the UI shows a chunk counter or upload status, make sure it displays a realistic number (e.g., "47 chunks uploaded, 0 pending").

---

### Screenshot 3: Dual-Camera View

**What to show:**
A clear demonstration of the dual-camera simultaneous recording feature. The screen should show both the front-facing and rear-facing camera feeds recording at the same time, in whatever layout the app uses (split-screen, picture-in-picture, or side-by-side).

**Caption text:**
**Both sides of every story.**

**Notes:**
- This is a key differentiator. The screenshot must make it immediately obvious that two cameras are recording simultaneously.
- Show realistic camera content -- e.g., the rear camera showing a street or room, the front camera showing the user's perspective.
- If the app labels the feeds (e.g., "Front" / "Rear"), make sure those labels are visible.

---

### Screenshot 4: Apple Watch + Activation Methods

**What to show:**
A composite or contextual view showing the multiple ways to activate recording:
- The Apple Watch companion app with its record button
- A Siri activation prompt ("Hey Siri, put this on the record")
- Optionally, the iPhone widget or lock screen quick action

If the app has a dedicated "activation methods" settings screen or onboarding screen showing all options, that could work as well.

**Caption text:**
**Start from your Watch, Siri, or one tap.**

**Notes:**
- If showing an Apple Watch, use a realistic Watch frame overlay or show the Watch app screen alongside the iPhone.
- The Siri activation can be shown as a Siri dialog bubble on screen.
- The goal is to communicate that recording can start without fumbling for the app.

---

### Screenshot 5: Evidence Export / Chain of Custody

**What to show:**
The evidence export screen or a preview of the chain-of-custody output. This could include:
- A list of recorded sessions with metadata (date, duration, chunk count, verification status)
- A preview of the chain-of-custody PDF showing digital signature verification, hash chain integrity, and timestamps
- A share/export dialog showing export options

**Caption text:**
**Court-ready evidence, verified and signed.**

**Notes:**
- This screenshot targets the "trust and credibility" factor -- users need to know their recordings hold up.
- Show verification checkmarks or "integrity verified" badges next to recordings.
- If the PDF preview is readable at screenshot resolution, show it. Otherwise, show the export preparation screen with metadata visible.

---

### Screenshot 6: Privacy and Security Overview

**What to show:**
A settings or information screen that communicates the app's security and privacy posture. This could be:
- The security settings screen showing encryption status, key information, and backup configuration
- An "about your security" informational screen
- The Recovery Kit setup screen

Ideally, the screen should visually communicate: open source, end-to-end encryption, zero-knowledge design, and user-controlled keys.

**Caption text:**
**Open source. Zero-knowledge. Your keys, your data.**

**Notes:**
- This is the trust-building screenshot. It should make privacy-conscious users feel confident.
- Show concrete details: "AES-256 Encryption: Active," "Keys stored on device," "Open source -- inspect our code."
- Avoid vague security language -- show specifics that technically literate users will recognize.

---

## Caption Style Guide

- **Font:** Use a clean, bold sans-serif font (San Francisco / SF Pro Display Bold recommended for consistency with iOS).
- **Placement:** Caption text above or below the device frame, or overlaid on a colored background area outside the screenshot content.
- **Color palette:** Use the app's brand colors. Suggested: dark background (#1A1A2E or similar deep navy/charcoal) with white or light-colored text.
- **Keep it short:** Each caption is one sentence or phrase, no more than 8 words.

---

## Production Notes

### Taking Screenshots

1. **Screenshots must be taken on physical devices or the Xcode Simulator at the exact resolutions listed above.** App Store Connect rejects screenshots that are scaled or do not match the required pixel dimensions.

2. **For the 6.7-inch screenshots:** Use an iPhone 16 Pro Max, iPhone 15 Pro Max, iPhone 15 Plus, or iPhone 14 Pro Max (or their corresponding Simulator profiles).

3. **For the 6.5-inch screenshots:** Use an iPhone 14 Plus, iPhone 13 Pro Max, iPhone 12 Pro Max, iPhone 11 Pro Max, or iPhone XS Max (or their corresponding Simulator profiles).

4. **Use realistic content.** Populate the app with sample recordings, realistic timestamps, and plausible metadata before capturing screenshots. Do not show empty states or placeholder text.

5. **Status bar:** Consider using a clean status bar (full signal, full Wi-Fi, full battery, a standard time like 9:41 AM -- Apple's traditional demo time).

### Adding Frames and Captions

After capturing raw screenshots from the device/simulator, add device frames and captions using a tool such as:

- **Fastlane Frameit** (free, open source, command-line)
- **Screenshots Pro** (Mac app)
- **Figma / Sketch** (manual layout with device frame templates)
- **RocketSim** (Xcode-integrated screenshot tool)

### Localization

If the app is localized in the future, screenshot captions should be translated for each supported locale. App Store Connect supports separate screenshot sets per language.

---

## Summary Table

| #  | Concept                          | Caption                                          |
|----|----------------------------------|--------------------------------------------------|
| 1  | Hero / One-Tap Recording         | One tap. Full protection.                        |
| 2  | Real-Time Encrypted Backup       | Encrypted and backed up in real time.            |
| 3  | Dual-Camera View                 | Both sides of every story.                       |
| 4  | Apple Watch + Activation Methods | Start from your Watch, Siri, or one tap.         |
| 5  | Evidence Export / Chain of Custody| Court-ready evidence, verified and signed.       |
| 6  | Privacy and Security Overview    | Open source. Zero-knowledge. Your keys, your data.|

These 6 concepts apply to both the 6.7-inch and 6.5-inch screenshot sets. Upload each set at the correct resolution in App Store Connect under the appropriate device size tab.
