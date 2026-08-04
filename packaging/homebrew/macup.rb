class Macup < Formula
  desc "Bootstrap and keep a Mac dev environment in sync"
  homepage "https://github.com/dicksonk/macup"
  url "https://github.com/dicksonk/macup/archive/refs/tags/v0.2.1.tar.gz"
  sha256 "e495597cb81b83d6b31f13f368ccbe78a14acb94f588b76687aa64ee983124f7"
  license "MIT"

  depends_on "git"
  depends_on "gum"
  depends_on "gh"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/macup"
  end

  test do
    system "#{bin}/macup", "--help"
  end
end
