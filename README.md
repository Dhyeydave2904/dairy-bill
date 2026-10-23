# Dairy Bill — Flutter Android App

A Flutter app for keeping customer-wise milk delivery records and generating monthly bills.

## Included features
- Save each customer once (name and optional phone number)
- Select saved customers from a dropdown for daily entries
- Product rates: Amul Taaza ₹29, Amul Gold ₹35, Chaas ₹20 per packet
- Select entry date and enter packet quantities
- Automatic entry totals and monthly customer-wise totals
- Product-wise monthly quantity and amount breakdown
- Monthly bill PDF preview/print/share through the platform print/share sheet
- View all entries, add/edit/delete customers, delete incorrect entries
- Data persists locally on the device using SharedPreferences

## Run the app
1. Install Flutter SDK and Android Studio, or use a cloud Flutter build service.
2. In a terminal, run `flutter create dairy_bill`.
3. Replace the generated `pubspec.yaml` and `lib/main.dart` with the files in this package.
4. From the project folder run:
   ```bash
   flutter pub get
   flutter run
   ```
5. To build an Android APK:
   ```bash
   flutter build apk --release
   ```
   APK output: `build/app/outputs/flutter-apk/dairy-bill.apk`

## Important notes
- This source package contains the complete Flutter app code, but does not include generated Android/iOS platform folders or a prebuilt APK. Run `flutter create` as described above to generate platform files before building.
- Data is stored on the device. It is not automatically synced to another phone or backed up online.
- Monthly totals are calculated from entries whose dates fall in the selected calendar month.

## Build an APK on GitHub without Android Studio
This package includes `.github/workflows/build-apk.yml` and `codemagic.yaml`.
1. Upload the contents of this folder to your GitHub repository's `main` branch.
2. Open the repository's **Actions** tab and choose **Build Android APK**.
3. Click **Run workflow** if it has not started automatically.
4. When the workflow succeeds, open that workflow run and download the `dairy-bill-release-apk` artifact.
5. Extract the downloaded artifact ZIP to get `dairy-bill.apk`.
