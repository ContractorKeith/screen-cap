# Homebrew cask for the ContractorKeith/homebrew-tap repo (copy to Casks/screen-cap.rb there).
# Per release: set version, and sha256 from the release's ScreenCap-<version>.dmg.sha256 asset.
cask "screen-cap" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # TODO: release DMG sha256

  url "https://github.com/ContractorKeith/screen-cap/releases/download/v#{version}/ScreenCap-#{version}.dmg"
  name "ScreenCap"
  desc "Open-source menu bar screenshot, annotation and OCR tool"
  homepage "https://github.com/ContractorKeith/screen-cap"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Add `auto_updates true` once SUPublicEDKey is set and Sparkle updates in-app.
  depends_on macos: ">= :sonoma"

  app "ScreenCap.app"

  zap trash: [
    "~/Library/Application Support/ScreenCap",
    "~/Library/Caches/com.contractorkeith.screencap",
    "~/Library/HTTPStorages/com.contractorkeith.screencap",
    "~/Library/Preferences/com.contractorkeith.screencap.plist",
  ]
end
