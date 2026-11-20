cask "awake-mac" do
  version "VERSION"
  sha256 "SHA256"

  url "https://github.com/dikeckaan/AwakeMAC/releases/download/v#{version}/AwakeMac-#{version}.zip"
  name "Awake Mac"
  desc "Menu bar app that keeps the Mac awake, even with the lid closed"
  homepage "https://github.com/dikeckaan/AwakeMAC"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Awake Mac.app"

  uninstall quit: "app.awakemac.AwakeMac"

  zap trash: [
    "~/Library/Preferences/app.awakemac.AwakeMac.plist",
  ]

  caveats <<~EOS
    Lid-closed mode installs a narrow sudoers rule on first use (you approve it in macOS' admin prompt).
    To remove it: sudo rm /etc/sudoers.d/awakemac
  EOS
end
