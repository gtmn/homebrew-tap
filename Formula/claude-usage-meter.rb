class ClaudeUsageMeter < Formula
  desc "Menu bar meter for Claude Code session, weekly and Enterprise budget limits"
  homepage "https://github.com/gtmn/claude-usage-meter"
  url "https://github.com/gtmn/claude-usage-meter/archive/refs/tags/v0.1.7.tar.gz"
  sha256 "bf0eb70a1576a14aed35248d06d9cefb758e878976d9f9e84dad160dd5e0a2e0"
  license "MIT"
  head "https://github.com/gtmn/claude-usage-meter.git", branch: "main"

  # Built from source on this Mac, ad-hoc signed: nothing is downloaded as a binary,
  # so Gatekeeper has nothing to quarantine and no Developer ID is needed.
  depends_on macos: :sonoma

  def install
    # The app reports this version (build.sh 0.1.3 and later; earlier ones ignore it).
    ENV["USAGE_METER_VERSION"] = version.to_s unless build.head?
    system "MenuBar/build.sh"
    prefix.install "MenuBar/build/UsageMeter.app"

    system "swiftc", "-O", "-target", "#{Hardware::CPU.arch}-apple-macos14.0",
           "-o", "claude-usage", "UsageReader.swift", "main.swift"
    bin.install "claude-usage"

    pkgshare.install "statusline-snapshot.sh"
  end

  service do
    run opt_prefix/"UsageMeter.app/Contents/MacOS/UsageMeter"
    run_at_load true
    keep_alive false
  end

  def caveats
    <<~EOS
      To open Usage Meter once without the background service:
        open #{opt_prefix}/UsageMeter.app

      To open it at every login, use brew services (the app's own
      "Open at login" switch is hidden in Homebrew copies).

      Optional status-line script (see the README):
        #{opt_pkgshare}/statusline-snapshot.sh
    EOS
  end

  test do
    app = prefix/"UsageMeter.app"
    assert_predicate app/"Contents/MacOS/UsageMeter", :executable?
    system "codesign", "--verify", app
    # No status-line file in the test's empty home folder.
    assert_match "error", shell_output("#{bin}/claude-usage snapshot 2>&1", 1)
  end
end
