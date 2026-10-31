/// Alias for the history record kind. The app target has its own `CaptureKind` (what to
/// capture), and `ScreenCapKit.CaptureKind` resolves to the constants enum, so the app spells
/// the history type through this alias.
public typealias HistoryKind = CaptureKind
