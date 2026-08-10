class Macup < Formula
  desc "Bootstrap and keep a Mac dev environment in sync"
  homepage "https://github.com/dicksonk/macup"
  url "https://github.com/dicksonk/macup/archive/refs/tags/v0.5.1.tar.gz"
  sha256 "a897afcf623017e15e8aa3a15d6bb3d2b390c6f30a00a37349a56b614ce67700"
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
