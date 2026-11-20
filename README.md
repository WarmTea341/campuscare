# CampusCare

Campus facility issue reporting mobile application built with **Flutter** and **Supabase** (PostgREST + Auth + Storage).

---

## 1. Local Setup

### Target Platform & Prerequisites
- **Primary demo target:** Android device or emulator (`flutter run --dart-define-from-file=env.json`).
- Flutter SDK installed and on your `PATH`.
- Private project credentials (`env.json` values and demo student/admin accounts) shared privately by the backend lead.

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

> **Note:** Until the real login and home screens are built, verify your Android setup against the throwaway backend check harness:
> ```bash
> flutter run -t lib/main_backend_check.dart --dart-define-from-file=env.json
> ```
> Delete `lib/main_backend_check.dart` once the real `LoginPage` is wired up.

---

## 2. Project Structure, Ownership & Git Workflow

```text
lib/
├── app_services.dart          # [Backend Lead] Service locator container & bootstrapServices()
├── main.dart                  # [Backend Lead] App entry point, GetX bindings, and route table
├── main_backend_check.dart    # [Backend Lead] Throwaway test harness (delete once LoginPage exists)
├── controllers/               # [Backend Lead] GetX controllers (Rx state, validation, API calls)
├── views/                     # [Frontend Dev] Flutter screens and reusable UI widgets
├── core/                      # [Backend Lead] Constants, ApiException, and validators
├── dtos/                      # [Backend Lead] Request payloads (Create, UpdatePending, AdminUpdate)
├── models/                    # [Backend Lead] ReportModel, ReportStatusHistoryModel, ProfileModel, BuildingModel, RoomModel
└── services/                  # [Backend Lead] ReportApiService, ReportPhotoWorkflow, PhotoPickerService, AuthService
```

### Strict Architectural & Git Rules
1. **Strict MVC boundary:** Widgets in `lib/views/` **never** import or call `lib/services/*` directly—all data, loading flags, and error messages flow exclusively through GetX controllers in `lib/controllers/`.
2. **File ownership:**
   - **Backend Lead:** `lib/controllers/`, `lib/main.dart`, route table, `lib/services/`, `lib/dtos/`, `lib/models/`, `lib/core/`.
   - **Frontend Teammate:** `lib/views/` (and UI-only widgets).
   - **Never edit `lib/services/`, `lib/dtos/`, `lib/models/`, or `lib/core/`** without coordinating first—these layers enforce database RLS contracts and are covered by 53 unit tests.
3. **Branching:** Base all feature branches off tag `backend-v1` on `main` (`feat/controllers` for controllers/routes, `feat/ui` for views). Run `flutter analyze` and `flutter test` before every push.

---

## 3. App Initialization

`bootstrapServices()` runs once in `main()` before `runApp(...)` and registers `AppServices` with GetX (`Get.put(services)`):

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await bootstrapServices();
  Get.put<AppServices>(services);
  runApp(const MyApp());
}
```

`AppServices` exposes four services (consumed by controllers only):
- `services.auth` (`AuthService`)
- `services.api` (`ReportApiService`)
- `services.photos` (`ReportPhotoWorkflow`)
- `services.picker` (`PhotoPickerService`)

---

## 4. Screen-to-Method Contract

| Screen / User Action | Underlying Service Call (via Controller) | Notes / Return Value |
| :--- | :--- | :--- |
| **App Start / Splash** | `auth.restoreSession()` | Returns `ProfileModel?`. `null` → Login. `profile.isAdmin` → Admin vs. Student home. Rethrows `ApiException` if offline (do not log out). |
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

1. **Never display raw exception strings.** Controllers catch typed exceptions and expose safe messages:
   - `ApiException` → `e.userMessage`
   - `AuthFailure` → `e.message`
   - `PhotoException` → `e.message`
2. **Handle non-atomic photo uploads on submit.** `photos.submitReport()` saves the report first and attaches the photo second. If `result.photoError != null`, the report **was saved**—navigate back or to detail and show a snackbar/banner (*"Report submitted, but photo upload failed. You can retry attaching it in edit."*).
3. **Validate forms before calling the API.** Call `request.validate()` on `CreateReportRequest`, `UpdatePendingReportRequest`, and `AdminUpdateReportRequest`—it returns a `String?` error message mirroring the database constraints (or `null` when valid).
4. **Gate student edit/delete controls with `report.isPending`.** Hide Edit, Delete, Replace Photo, and Remove Photo buttons once a report moves past `Pending` (the database also blocks these via RLS).
5. **Restrict admin status transitions.** Populate the admin status dropdown strictly from `ReportStatus.next(report.status)` (`Pending` → `Verified` → `In Progress` → `Resolved`). When transitioning to `Verified`, require selecting a priority from `ReportPriority.all`.
6. **Reporter details on triage.** `ReportModel.reporterName` and `ReportModel.reporterStudentNumber` are populated on reports from `listReports`, `getReport`, and `createReport`. Because `adminUpdateReport` returns a bare row without embeds, re-fetch with `api.getReport(id)` after triage before refreshing the detail screen.

---

## 6. Verification

Run static analysis and the unit test suite before pushing changes:

```bash
flutter analyze
flutter test
```