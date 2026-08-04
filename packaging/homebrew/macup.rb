class Macup < Formula
  desc "Bootstrap and keep a Mac dev environment in sync"
  homepage "https://github.com/dicksonk/macup"
  url "https://github.com/dicksonk/macup/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "151fb9598474ebabb670882dc929420d9ab50648a6772ad6798a28c6140912a0"
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
