cask "notchpulse" do
  version "4.6.1"
  sha256 :no_check

  url "https://github.com/HieuKunn/NotchPulse-Release-for-everyone/releases/download/v#{version}/NotchPulse.dmg"
  name "NotchPulse"
  desc "Dynamic Island, Face ID authentication system, and productivity center for macOS"
  homepage "https://github.com/HieuKunn/NotchPulse-Release-for-everyone"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "NotchPulse.app"

  zap trash: [
    "~/Library/Application Support/com.hieukunn.NotchPulse",
    "~/Library/Caches/com.hieukunn.NotchPulse",
    "~/Library/Preferences/com.hieukunn.NotchPulse.plist",
  ]
end
