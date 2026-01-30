# Export Compliance Documentation -- OnTheRecord

This document provides a complete analysis of the encryption used in OnTheRecord for the purpose of Apple App Store export compliance review, U.S. Bureau of Industry and Security (BIS) classification, and the ITSAppUsesNonExemptEncryption Info.plist key.

---

## 1. Encryption Inventory

### 1.1 Algorithms Used

| Algorithm         | Type                  | Purpose                                          | Key Size     |
|-------------------|-----------------------|--------------------------------------------------|--------------|
| AES-256-GCM       | Symmetric encryption  | Encrypting video/audio recording chunks          | 256-bit      |
| RSA-4096 OAEP     | Asymmetric encryption | Wrapping (encrypting) per-session AES keys       | 4096-bit     |
| HKDF-SHA256       | Key derivation        | Deriving per-chunk keys from session key material| N/A          |
| P256 ECDSA        | Digital signature     | Signing each recording chunk for tamper evidence | 256-bit      |
| PBKDF2-SHA256     | Key derivation        | Deriving encryption key from recovery code       | N/A          |
| SHA-256           | Hashing               | Hash-chaining timestamps for integrity proof     | N/A          |
| Secure Enclave    | Hardware key storage  | Storing ECDSA signing key (when available)       | 256-bit      |

### 1.2 How Encryption Is Used

OnTheRecord encrypts personal safety recordings (video, audio) made by the user on their own device. The encryption protects the user's personal data at rest and during transfer to the user's own storage (NAS, iCloud, or other cloud service chosen by the user).

**Specifically:**
- Each recording session generates a random AES-256 session key.
- HKDF-SHA256 derives per-chunk encryption keys from the session key.
- Each 0.5-second recording chunk is encrypted with AES-256-GCM before being written to disk or uploaded.
- The session key is wrapped (encrypted) with the user's RSA-4096 public key so that only the user's private key can unwrap it.
- Each chunk is signed with P256 ECDSA to prove authenticity and prevent tampering.
- SHA-256 hash chains link chunks together to provide tamper-evident ordering.
- PBKDF2-SHA256 derives a key from the user's recovery code to encrypt a backup copy of their key material.
- The Secure Enclave stores the ECDSA signing private key when hardware support is available.

**The encryption is NOT used for:**
- User authentication or login
- Communication protocols (no messaging, no VoIP, no network encryption beyond HTTPS/TLS provided by the OS)
- Digital rights management (DRM)
- Payment processing
- Protecting intellectual property

---

## 2. Exemption Analysis (ERN / ECCN Classification)

### 2.1 Relevant U.S. Export Control Framework

Encryption software is controlled under the Export Administration Regulations (EAR), specifically:

- **ECCN 5D002** -- "Information Security" software that uses or performs cryptographic functions.
- **License Exception ENC** (Section 740.17 of the EAR) -- Allows export of mass-market and certain other encryption software without an individual license.

### 2.2 Does OnTheRecord Qualify for an Exemption?

**Short answer: No full exemption. A BIS classification (self-classification or CCATS) is required, but License Exception ENC likely applies, meaning no individual export license is needed.**

#### Analysis:

**Exemption Category: Note 4 to Category 5, Part 2 (the "ancillary encryption" or "personal use" exemption)**

This exemption covers encryption that is:
> "limited to protecting personal data" and where "the cryptographic functionality cannot easily be changed by the user"

OnTheRecord's encryption:
- Protects personal data (the user's own recordings) -- YES
- Cannot easily be changed by the user (the algorithms are hardcoded) -- YES
- Is not the primary function of the app (the primary function is recording) -- ARGUABLE but encryption is deeply integral

However, this Note 4 exemption has limitations. Because OnTheRecord uses:
- AES-256 (symmetric key length > 64 bits)
- RSA-4096 (asymmetric key length > 768 bits for RSA)

These exceed the thresholds for the simplest exemptions. The encryption is non-trivial and purpose-built into the app's core functionality.

**Exemption Category: Mass Market (ECCN 5D992 / License Exception ENC paragraph (b))**

OnTheRecord is:
- Available to the general public (open source, App Store distribution) -- YES
- Designed for individual consumer use -- YES
- Encryption protects the user's own personal data -- YES
- Not customizable cryptography (users cannot change algorithms) -- YES

**This is the most likely applicable classification path.** Mass-market encryption software distributed via the App Store qualifies for License Exception ENC under 740.17(b), provided a self-classification report is filed with BIS.

### 2.3 Classification Summary

| Item                                | Assessment                                                |
|-------------------------------------|-----------------------------------------------------------|
| ECCN                                | 5D002 (encryption software)                               |
| Applicable License Exception        | ENC (Section 740.17(b)) -- mass market                    |
| Individual export license required? | No                                                        |
| BIS notification required?          | Yes -- self-classification report (see Section 4)         |
| CCATS filing required?              | No -- self-classification is sufficient for mass market    |
| ERN (Encryption Registration Number)| Not applicable (ERN was eliminated; replaced by self-classification reporting) |

---

## 3. How to Answer Apple's Export Compliance Questions

When submitting the app in App Store Connect, Apple asks a series of export compliance questions. Here is how to answer them for OnTheRecord:

### Question 1: "Does your app use encryption?"

**Answer: YES**

The app uses AES-256-GCM, RSA-4096, HKDF-SHA256, P256 ECDSA, PBKDF2-SHA256, and SHA-256.

### Question 2: "Does your app qualify for any encryption exemptions?"

**Answer: NO** (select that you do NOT qualify for an exemption)

OnTheRecord uses non-exempt encryption. The symmetric key length (256-bit) and asymmetric key length (4096-bit) exceed exemption thresholds. The encryption is a core feature of the app, not merely ancillary.

### Question 3: "Does your app implement any encryption algorithms not provided by the OS?"

**Answer: YES**

While the app uses Apple's CryptoKit and Security framework (which are OS-provided implementations), the app directs and orchestrates the encryption -- it generates keys, performs encryption/decryption of user data, wraps keys, and signs data. The cryptographic functionality is a deliberate, designed feature of the app.

Note: If Apple's question specifically asks whether you use your *own* implementation vs. the OS APIs, then the answer is that you use OS-provided implementations (CryptoKit, Security.framework, CommonCrypto). This distinction matters -- using OS-provided crypto libraries is viewed more favorably.

### Question 4: "Is your app available outside the U.S. or Canada?"

**Answer: YES** (assuming worldwide App Store distribution)

### Question 5: "Does your app use encryption for authentication only?"

**Answer: NO**

The encryption is used for protecting personal data (recordings), not for authentication.

### Question 6: "Does your app use encryption that is built into the operating system?"

**Answer: YES** (partially)

The app uses Apple's CryptoKit and Security.framework APIs, which are built into iOS. However, the app directs these APIs to perform encryption of user content as a primary feature.

### Recommended Flow Through Apple's Questions:

1. "Does your app use encryption?" -- **Yes**
2. "Does your app qualify for any of the exemptions provided in Category 5, Part 2 of the U.S. Export Administration Regulations?" -- **No**
3. "Does your app implement one or more encryption algorithms that are proprietary or not accepted as international standards?" -- **No** (all algorithms are international standards: AES, RSA, ECDSA, SHA-256, HKDF, PBKDF2)
4. "Is your app a mass-market encryption product?" -- **Yes**
5. Apple will then accept your submission with the understanding that you have filed (or will file) the required self-classification report with BIS.

---

## 4. BIS Self-Classification Report

### 4.1 Is a CCATS Filing Needed?

**No.** A Classification Automated Tracking System (CCATS) filing is used when you want BIS to classify your product for you. For mass-market encryption software, self-classification is sufficient.

### 4.2 Self-Classification Report Requirements

Under EAR Section 740.17(b)(1), you must submit a self-classification report to BIS **annually** by February 1st. The report is submitted to both:

- **BIS:** crypt@bis.gov
- **ENC Encryption Request Coordinator (NSA):** enc@nsa.gov

The report must include:

| Field                     | Value for OnTheRecord                                      |
|---------------------------|------------------------------------------------------------|
| Product name              | OnTheRecord                                                |
| Model/version number      | (current version, e.g., 1.0)                               |
| ECCN                      | 5D002                                                      |
| Authorization description | License Exception ENC 740.17(b)(1)                         |
| Item type                 | Mobility / mobile application software                     |
| Encryption description    | AES-256-GCM for data encryption, RSA-4096 OAEP for key wrapping, P256 ECDSA for digital signatures, HKDF-SHA256 and PBKDF2-SHA256 for key derivation, SHA-256 for integrity hashing |
| Key lengths               | 256-bit (symmetric), 4096-bit (RSA), 256-bit (ECDSA)      |
| Manufacturer              | (Your legal entity name)                                   |
| Manufacturer address      | (Your address)                                             |

### 4.3 Filing Template

A CSV format is preferred by BIS. The template and instructions are available at:
https://www.bis.gov/ear/title-vii/ecr

File the initial report before the app's first public release or within 30 days of it, and then annually by February 1st thereafter.

---

## 5. ITSEncryptionExportComplianceCode

### 5.1 Current Info.plist Setting

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
```

This is **correct**. The app does use non-exempt encryption.

### 5.2 Recommendation for ITSEncryptionExportComplianceCode

Once you have submitted your self-classification report to BIS and received confirmation (or once you have your internal tracking reference), you can add the `ITSEncryptionExportComplianceCode` key to your Info.plist:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
<key>ITSEncryptionExportComplianceCode</key>
<string>YOUR_CODE_HERE</string>
```

**How to obtain this code:**

1. In App Store Connect, go to your app's page.
2. Navigate to "App Information" in the sidebar.
3. Under "Export Compliance Information," complete the questionnaire (using the answers in Section 3 above).
4. Once you save, Apple may provide an `ITSEncryptionExportComplianceCode` string.
5. Add this string to your Info.plist to skip the export compliance questionnaire on future submissions.

**If Apple does not provide a code** (which is common for apps that answer the full questionnaire), the `ITSAppUsesNonExemptEncryption = true` key alone is sufficient. The `ITSEncryptionExportComplianceCode` key is optional and only serves to skip the questionnaire on subsequent builds.

### 5.3 Recommended Action Items

- [ ] File BIS self-classification report (EAR 740.17(b)(1)) before first public release
- [ ] Complete Apple's export compliance questionnaire in App Store Connect
- [ ] If Apple provides an ITSEncryptionExportComplianceCode, add it to Info.plist
- [ ] Set a calendar reminder to file the annual BIS self-classification report by February 1st each year
- [ ] Keep a copy of the self-classification report and any BIS correspondence in your records

---

## 6. Summary

| Question                                                    | Answer          |
|-------------------------------------------------------------|-----------------|
| Does the app use encryption?                                | Yes             |
| Is the encryption exempt from export controls?              | No              |
| What ECCN applies?                                          | 5D002           |
| What license exception applies?                             | ENC 740.17(b)   |
| Is an individual export license required?                   | No              |
| Is a CCATS filing required?                                 | No              |
| Is a BIS self-classification report required?               | Yes (annual)    |
| Is ITSAppUsesNonExemptEncryption correct at true?           | Yes             |
| Is ITSEncryptionExportComplianceCode needed in Info.plist?  | Optional        |
| Can the app be distributed worldwide on the App Store?      | Yes             |
