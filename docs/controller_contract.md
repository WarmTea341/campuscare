# Controller <-> View contract

Controllers + routes + main.dart: controllers owner. `lib/views/`: UI owner.
Widgets NEVER call `services.*`; they read controller state and call controller methods.

## Rules
1. **Every state field is Rx.** Read it inside `Obx(() => ...)`. Never read a plain field inside `Obx`.
2. **Widgets don't mutate state.** They call methods (`selectRoom`, `toggleTag`, ...).
3. **Only `AuthController` navigates** (login, logout, session restore). Every other action
   returns `Future<bool>`; on `true` the widget navigates (`Get.back()`).
4. **Controllers never throw into the UI.** Failures land in `errorMessage` (user-safe text).
   Show it with a snackbar/banner. Never show `e.toString()`.
5. **`load()` is called by the controller itself** (`onInit`). Widgets use `reload()` (pull-to-refresh).
6. `submit()` returning `true` means the report SAVED. If `warningMessage` is not empty,
   also show it (photo failed, report is safe).

## View classes the UI owner creates in lib/views/ (no constructor arguments)
`SplashView`, `LoginView`, `StudentHomeView`, `AdminHomeView`, `ReportFormView`, `ReportDetailView`.
Route arguments are read with `Get.arguments` (see lib/routes/app_routes.dart).

## What each screen reads / calls
| Controller | State (Rx) | Actions |
|---|---|---|
| AuthController | user, isRestoring, isLoading, errorMessage | signIn(email, password) -> bool, signOut() |
| ReportListController | reports, statusFilter, isLoading, isLoadingMore, hasMore, errorMessage | reload(), loadMore(), setFilter(status) |
| ReportFormController | buildings, rooms, selectedBuilding, selectedRoom, category, selectedTags, description, newPhoto, removeExistingPhoto, isLoading, isSubmitting, formError, errorMessage, warningMessage; getter quickTagOptions | selectBuilding, selectRoom, setCategory, toggleTag, setDescription, pickPhoto(source), clearPickedPhoto(), submit() -> bool |
| ReportDetailController | report, history, photoUrl, isLoading, isBusy, errorMessage; getters canEditOrDelete, nextStatus | deleteReport() -> bool, triage(priority:, notes:) -> bool |

## Splash (AuthController.restore)
- `restore()` runs once after the first frame; the splash does NOT call it on open.
- `SplashView`: `Obx` -> if `isRestoring` show a spinner; else if `errorMessage` is not empty show the
  message and a retry button that calls `Get.find<AuthController>().restore()`.
- If the user is signed out the controller navigates to Login by itself.

## Sign out
- `signOut()` navigates to Login on success. If it fails (offline) it sets `errorMessage` and stays put:
  show the message in a snackbar.

## Report list (both home screens)
- `ReportListController` loads the first page itself; widgets never call `load()`.
- Pull-to-refresh -> `reload()`. Near the end of the list -> `loadMore()`.
- Filter chips -> `setFilter(status)` with a value from `ReportStatus.all`, or `null` for "All".
- After returning from the form or detail screen with `true` -> `reload()`.
- Empty state: show it when `isEmptyState` is true. Error banner: when `errorMessage` is not empty
  (the rows already on screen stay visible).
