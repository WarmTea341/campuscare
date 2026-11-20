# CampusCare

Campus facility issue reporting mobile application built with **Flutter** and **Supabase** (PostgREST + Auth + Storage).

---

## 1. Local Setup

### Prerequisites
- Flutter SDK installed and on your `PATH`
- Private project credentials (`env.json` values and demo student/admin accounts) shared privately by the backend lead

### Configure Environment Keys
1. Copy `env.example.json` to `env.json` in the project root:
   ```bash
   cp env.example.json env.json
   ```
2. Fill in the real `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` values in `env.json`.
3. **Never commit `env.json`** (it is listed in `.gitignore`).

### Install Dependencies & Run
```bash
flutter pub get
flutter run --dart-define-from-file=env.json
```

> **Note:** Until the real login and home screens are built, you can verify your local setup against the throwaway backend check harness:
> ```bash
> flutter run -t lib/main_backend_check.dart --dart-define-from-file=env.json
> ```
> Delete `lib/main_backend_check.dart` once the real `LoginPage` is wired up.

---

## 2. Project Structure & Ownership

```text
lib/
├── app_services.dart          # Service locator container & bootstrapServices()
├── main_backend_check.dart    # Throwaway backend test UI (delete once LoginPage exists)
├── core/
│   ├── constants/             # ApiConstants, ReportStatus, ReportPriority, ReportCategory
│   ├── errors/                # ApiException (maps DB/HTTP errors to safe UI messages)
│   └── utils/                 # Client-side form validators mirroring DB constraints
├── dtos/                      # Request payloads (Create, UpdatePending, AdminUpdate)
├── models/                    # ReportModel, ReportStatusHistoryModel, ProfileModel, BuildingModel, RoomModel
└── services/                  # ReportApiService, ReportPhotoWorkflow, PhotoPickerService, AuthService
```

### Collaboration Rule
- **Do not edit `lib/services/`, `lib/dtos/`, `lib/models/`, or `lib/core/`** without coordinating first—these layers enforce database security contracts and are covered by 53 unit tests.
- Run `flutter analyze` and `flutter test` before every push.

---

## 3. App Initialization

Call `bootstrapServices()` once in `main()` before `runApp(...)` and register the returned `AppServices` instance (e.g., via GetX `Get.put(services)`):

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await bootstrapServices();
  Get.put<AppServices>(services);
  runApp(const MyApp());
}
```

`AppServices` exposes four services:
- `services.auth` (`AuthService`)
- `services.api` (`ReportApiService`)
- `services.photos` (`ReportPhotoWorkflow`)
- `services.picker` (`PhotoPickerService`)

---

## 4. Screen-to-Method Map

| Screen / User Action | Service Call | Notes / Return Value |
| :--- | :--- | :--- |
| **App Start / Splash** | `auth.restoreSession()` | Returns `ProfileModel?`. `null` → route to Login. `profile.isAdmin` → route to Admin vs. Student home. Rethrows `ApiException` if offline (do not log out). |
| **Login** | `auth.signIn(email, password)` | Returns `ProfileModel`. Throws `AuthFailure` or `ApiException`. |
| **Logout** | `auth.signOut()` | Clears the active Supabase session. |
| **Report List (Student & Admin)** | `api.listReports(status:, limit:, offset:)` | Returns `List<ReportModel>`. RLS automatically filters to own reports for students and all reports for admins. |
| **Create Report (Dropdowns)** | `api.listBuildings()` → `api.listRooms(buildingId)` | Populate building and room selectors. Use `ReportCategory.all` and `ReportCategory.quickTags` for category/tag chips. |
| **Create Report (Pick Photo)** | `picker.pick(ImageSource.camera / .gallery)` | Returns `Uint8List?` (`null` if cancelled). Resizes and validates JPEG/PNG ≤ 5 MB. Throws `PhotoException`. |
| **Create Report (Submit)** | `photos.submitReport(CreateReportRequest(...), photo:)` | Returns `SubmitResult` containing `report` and optional `photoError`. |
| **Report Detail** | `api.getReport(id)`<br>`api.listHistory(id)`<br>`photos.photoUrl(report)` | Fetches report details, chronological status timeline (`List<ReportStatusHistoryModel>`), and a temporary signed URL (`String?`) for private photo evidence. |
| **Student Edit Report** | `api.updatePendingReport(id, UpdatePendingReportRequest(...))`<br>`photos.replacePhoto(report, bytes)`<br>`photos.removePhoto(report)` | Only allowed while `report.isPending` is `true`. Use `replacePhoto` / `removePhoto` separately from text edits. |
| **Student Delete Report** | `photos.deleteReport(report)` | Deletes the database row first and cleans up the Storage photo. Only allowed while `report.isPending` is `true`. |
| **Admin Triage Update** | `api.adminUpdateReport(AdminUpdateReportRequest(...))` | Advances status, sets priority, and saves `adminNotes`. |

---

## 5. Mandatory UI & Error-Handling Rules

1. **Never display raw exception strings.** Always catch typed exceptions and render their user-safe messages:
   - `ApiException` → `e.userMessage`
   - `AuthFailure` → `e.message`
   - `PhotoException` → `e.message`
2. **Handle non-atomic photo uploads on submit.** `photos.submitReport()` saves the report first and attaches the photo second. If `result.photoError != null`, the report **was saved**—navigate back or to detail and show a snackbar/banner (*"Report submitted, but photo upload failed. You can retry attaching it in edit."*).
3. **Validate forms before calling the API.** Call `request.validate()` on `CreateReportRequest`, `UpdatePendingReportRequest`, and `AdminUpdateReportRequest`—it returns a `String?` error message mirroring the database constraints (or `null` when valid).
4. **Gate student edit/delete controls with `report.isPending`.** Hide Edit, Delete, Replace Photo, and Remove Photo buttons once a report moves past `Pending` (the database also blocks these via RLS).
5. **Restrict admin status transitions.** Populate the admin status dropdown strictly from `ReportStatus.next(report.status)` (`Pending` → `Verified` → `In Progress` → `Resolved`). When transitioning to `Verified`, require selecting a priority from `ReportPriority.all`.
6. **Reporter name limitation.** `ReportModel` currently exposes `reporterId` (UUID) rather than the reporter's full name. If the admin screen needs to display the student's name, flag the backend lead to add a profile join.

---

## 6. Verification

Run static analysis and the unit test suite before pushing changes:

```bash
flutter analyze
flutter test
```     