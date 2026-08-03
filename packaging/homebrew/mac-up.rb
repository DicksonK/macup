class MacUp < Formula
  desc "Bootstrap and keep a Mac dev environment in sync"
  homepage "https://github.com/dicksonk/mac-up"
  url "https://github.com/dicksonk/mac-up/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"

  depends_on "git"
  depends_on "gum"
  depends_on "gh"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/mac-up"
  end

  test do
    system "#{bin}/mac-up", "--help"
  end
end
