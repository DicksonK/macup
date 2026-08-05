class Macup < Formula
  desc "Bootstrap and keep a Mac dev environment in sync"
  homepage "https://github.com/dicksonk/macup"
  url "https://github.com/dicksonk/macup/archive/refs/tags/v0.2.2.tar.gz"
  sha256 "6cd06f404b8fb59b8165ef81dd43ce84ce560b052b15517bfcb344d012a2f041"
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
