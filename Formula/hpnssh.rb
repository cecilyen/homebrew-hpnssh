class Hpnssh < Formula
  desc "High Performance Networking fork of OpenSSH"
  homepage "https://github.com/rapier1/hpn-ssh"
  url "https://github.com/rapier1/hpn-ssh.git",
      tag:      "hpn-18.9.0",
      revision: "e2dfa0cea55d93747f4c68b4a2b134d6fbe0db06"
  version "18.9.0"
  license "SSH-OpenSSH"

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "pkgconf" => :build
  depends_on "libedit"
  depends_on "openssl@3"
  depends_on "zlib"

  def install
    openssl = Formula["openssl@3"].opt_prefix
    zlib = Formula["zlib"].opt_prefix
    libedit = Formula["libedit"].opt_prefix
    sdkroot = MacOS.sdk_path

    set_default_port_22
    set_apple_silicon_flags(openssl, zlib, libedit, sdkroot)

    system "autoreconf", "-fi"
    system "./configure",
      "--prefix=#{prefix}",
      "--exec-prefix=#{prefix}",
      "--sysconfdir=#{etc}/hpnssh",
      "--libexecdir=#{libexec}",
      "--localstatedir=#{var}/hpnssh",
      "--with-privsep-path=#{var}/hpnssh/empty",
      "--with-pid-dir=#{var}/hpnssh/run",
      "--with-ssl-dir=#{openssl}",
      "--with-zlib=#{zlib}",
      "--with-pam",
      "--with-audit=bsm",
      "--with-libedit=#{libedit}"

    system "make", "-j#{ENV.make_jobs}"
    system "make", "install"
    strip_hpn_macho_binaries(prefix)
  end

  test do
    assert_match "OpenSSH_10.3p1_hpn18.9.0", shell_output("#{bin}/hpnssh -V 2>&1")
    assert_match "OpenSSL", shell_output("#{bin}/hpnssh -V 2>&1")
    assert_match "port 22", shell_output("#{bin}/hpnssh -G localhost 2>/dev/null")
  end

  private

  def set_default_port_22
    inreplace "ssh.h", /^#define[ \t]+HPNSSH_DEFAULT_PORT[ \t]+[0-9]+/,
      "#define HPNSSH_DEFAULT_PORT    22"
    inreplace "sshd_config", /^Port 2222$/, "Port 22" if File.exist?("sshd_config")
  end

  def set_apple_silicon_flags(openssl, zlib, libedit, sdkroot)
    opt_flags = "-arch arm64 -O3 -flto -g0 -mcpu=apple-m2"
    ENV.append "CFLAGS", opt_flags
    ENV.append "CXXFLAGS", opt_flags
    ENV.append "CPPFLAGS", "-isysroot #{sdkroot} -I#{openssl}/include -I#{zlib}/include -I#{libedit}/include"
    ENV.append "LDFLAGS",
      "-arch arm64 -flto -isysroot #{sdkroot} -Wl,-search_paths_first " \
      "-L#{openssl}/lib -L#{zlib}/lib -L#{libedit}/lib " \
      "-Wl,-rpath,#{openssl}/lib -Wl,-rpath,#{zlib}/lib -Wl,-rpath,#{libedit}/lib"
    ENV.prepend_path "PKG_CONFIG_PATH", "#{openssl}/lib/pkgconfig"
    ENV.prepend_path "PKG_CONFIG_PATH", "#{zlib}/lib/pkgconfig"
    ENV.prepend_path "PKG_CONFIG_PATH", "#{libedit}/lib/pkgconfig"
  end

  def strip_hpn_macho_binaries(root)
    strip_cmd = Utils.safe_popen_read("xcrun", "-find", "strip").strip
    Dir["#{root}/bin/hpn*", "#{root}/libexec/hpn*"].each do |path|
      next unless File.file?(path) && File.executable?(path)
      next unless Utils.safe_popen_read("file", path).include?("Mach-O")

      system strip_cmd, "-S", path
    end
  end
end
