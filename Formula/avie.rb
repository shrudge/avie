class Avie < Formula
  desc "Swift package graph diagnostics tool"
  homepage "https://github.com/yourusername/avie"
  url "https://github.com/yourusername/avie/archive/refs/tags/1.0.0.tar.gz"
  sha256 "..."
  license "MIT"

  depends_on xcode: ["14.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/avie"
  end

  test do
    system "#{bin}/avie", "--version"
  end
end
