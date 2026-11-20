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
