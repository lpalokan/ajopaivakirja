# Privacy Policy

**Ajopäiväkirja (Mileage tracker)**
Package: `fi.lpalokan.kilometrikorvaus`
Last updated: 1 July 2026

Ajopäiväkirja ("the App", "we", "our") is a free, open-source Android
application that helps you record work-related mileage (kilometrikorvaus) and
daily allowances (päiväraha). This Privacy Policy explains what information the
App handles, how it is used, and the choices you have.

The App is published under the MIT License. Its source code is available at
<https://github.com/lpalokan/ajopaivakirja>.

**Contact:** Lauri Palokangas — lauri.palokangas@gmail.com

## Summary

- The App stores your data **locally on your device**.
- The App has **no backend server** of its own and does **not** collect
  analytics or advertising identifiers.
- The only external service the App connects to is **Google**, and only when you
  choose to sign in and export your data — and then only to a single spreadsheet
  the App creates in your own Drive.
- Your data is **never sold or shared** with third parties.

## 1. Data stored on your device

The following information is created and stored locally on your device (in an
on-device database) and is not transmitted to us:

- **Trips** – dates, times, start/end odometer readings, start and end
  locations, route, distance, and purpose.
- **Saved routes and location zones** you configure.
- **Expenses** you attach to trips (e.g. parking, tolls, meals).
- **Reimbursement settings** (per-kilometre rate, daily-allowance amounts) and
  driver name.
- An optional **diagnostic log file**, only if you enable it.

This data stays on your device unless you choose to export it (to Google Sheets,
CSV, or PDF). Uninstalling the App removes this local data.

## 2. Location data

If you grant location permission, the App uses your device location (through the
operating system's location services) to record trip start/end points and,
optionally, to detect arrival at saved zones. Location data is processed on your
device and stored locally with your trips. It is not sent to us or to any third
party — except that any start/end locations you choose to export are written
into your own Google Sheet.

## 3. Camera and text recognition

If you use the "photograph the odometer" feature, the App uses your camera and
**on-device** text recognition (Google ML Kit) to read the odometer number.
Images are processed on your device and are not uploaded or stored by the App.

## 4. Google account data (Google Drive & Sheets)

Exporting to Google Sheets is **optional**. If you choose to sign in with Google,
the App requests exactly one OAuth scope and uses it solely as described:

- **`https://www.googleapis.com/auth/drive.file`**
  A **per-file** permission. It lets the App create one spreadsheet in your
  Google Drive and keep that spreadsheet up to date — writing your mileage and
  daily-allowance rows into it, creating the worksheet tab used for the export,
  updating a row when you edit the corresponding trip in the App, and removing a
  row when you delete a trip.

  This scope grants access **only to the file the App itself created**. The App
  cannot see, list, read, modify, or delete any other file in your Google Drive,
  and it has no way to obtain such access.

As part of Google Sign-In, the App also receives basic profile information (your
name, email address, and profile picture), used only to show which account you
are signed in with.

Google account data is used only to provide the export feature you request. A
sign-in token (to keep you signed in) and the ID of the spreadsheet the App
created are stored on your device. This data is not transmitted to us or shared
with any third party.

### Limited Use disclosure

The App's use of information received from Google APIs will adhere to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the **Limited Use** requirements. Specifically, we only use Google user
data to provide and improve the App's user-facing export feature, we do **not**
transfer or sell this data, and we do **not** use it for advertising or any
purpose unrelated to the feature you requested.

## 5. Data sharing

We do not sell, rent, or share your personal data with third parties. Data you
export is written only to your own Google account (the spreadsheet the App
created in your Drive) or to CSV/PDF files you create on your own device.

## 6. Data retention and deletion

- Local data is retained on your device until you delete it in the App or
  uninstall the App.
- You can **sign out** of Google in the App at any time.
- You can **revoke** the App's access to your Google account at any time at
  <https://myaccount.google.com/connections> (Google Account → Data & privacy →
  Third-party apps & services).
- Data already exported into your own Google Sheet or CSV/PDF files remains under
  your control; you can delete it yourself.

## 7. Security

Your data is stored using your device's standard application storage.
Communication with Google is over encrypted (HTTPS) connections. Because the App
has no backend server, there is no central database of user data that could be
breached.

## 8. Children

The App is intended for working adults and is not directed at children under 13
(or the equivalent minimum age in your jurisdiction). We do not knowingly collect
data from children.

## 9. Changes to this policy

We may update this Privacy Policy from time to time. Changes will be published in
the App's source repository, and the "Last updated" date above will be revised.
Material changes will be reflected in a new App release.

## 10. Contact

Questions about this Privacy Policy? Contact Lauri Palokangas at
lauri.palokangas@gmail.com.
