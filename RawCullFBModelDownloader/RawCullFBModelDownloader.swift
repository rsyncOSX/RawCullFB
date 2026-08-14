import BackgroundAssets
import ExtensionFoundation

/// Self-hosted Managed Background Assets entry point. The system framework
/// schedules, downloads, verifies, and installs the model asset packs.
@main
struct RawCullFBModelDownloader: ManagedDownloaderExtension {}
