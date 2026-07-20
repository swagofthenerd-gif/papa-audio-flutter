/// The running app's build number. Bump this on every release and tag the
/// matching GitHub release `v<number>` (e.g. v3). The in-app updater compares
/// the latest GitHub release's number against this to decide if an update is
/// available. Must stay in sync with pubspec.yaml's `version: x.y.z+<number>`.
const int kAppBuildNumber = 5;

/// Human-facing version shown in Settings / the update dialog.
const String kAppVersionName = '1.0.0';
