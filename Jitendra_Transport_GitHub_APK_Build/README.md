# Jitendra Transport Company — Android V1

Offline single-user transport management app, built in Flutter with a local SQLite database.

## Features
- Dashboard: total vehicles, trips in transit, billed revenue, dated expenses, estimated operating P/L, outstanding bills.
- Vehicles: add/edit registrations, container types, driver details.
- Trips: create trips, mark delivered, add diesel/toll/driver/repair expenses.
- Customers: add contact details, address and GSTIN.
- Bills and goods transport memos: create numbered records, generate branded PDFs, share through Android share sheet (select WhatsApp).
- Business settings: address, phone, GSTIN, bank and invoice terms.

## Build on a computer with Flutter and Android SDK

1. Install Flutter SDK and Android Studio / Android SDK. Run `flutter doctor` and resolve Android issues.
2. Extract this ZIP and open a terminal in `jitendra_transport`.
3. Run `flutter create --platforms android .` to generate standard Android project files.
4. Run `flutter pub get`.
5. Connect an Android phone with USB debugging enabled and run `flutter run` to test.
6. For an APK, run `flutter build apk --release`. Find it at `build/app/outputs/flutter-apk/app-release.apk`.

This package contains the application source and assets, not a compiled APK. Flutter is not installed in the creation environment, so a full Flutter build and on-device test have not been performed.

## Notes and V1 limitations
- **Local only:** App data is in a private SQLite database. Clearing app data or uninstalling the app deletes records. No export/backup in this first version. Back up data before replacing devices.
- **No real GPS tracking:** In Transit is based on manual trip status.
- **Revenue accounting:** Dashboard revenue counts issued bills in the selected current month, not the trips' freight, to avoid double counting. Expenses are grouped by their entry date. P/L is an operating snapshot and excludes tax calculations, depreciation, financing, etc.
- **PDF tax handling:** PDFs show the provided GSTIN but do not automatically calculate GST or validate invoice compliance. Confirm invoice layout, GST/consignment-note obligations and numbering with the business accountant before issuing legal invoices.
- **Sharing:** Uses the Android share sheet; select WhatsApp manually. WhatsApp must be installed to share directly there.
- **Document numbers:** A prefix, current year and running count. Existing records cannot be deleted in V1, preserving sequence.
- **Branding:** Cropped logo from the approved concept composite; can be replaced by swapping `assets/logo.png`.
- **Testing:** Review on an Android phone before using for live business transactions.
