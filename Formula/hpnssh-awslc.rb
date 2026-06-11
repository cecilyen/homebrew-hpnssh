class HpnsshAwslc < Formula
  desc "High Performance Networking fork of OpenSSH built with AWS-LC"
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
  depends_on "aws-lc"
  depends_on "libedit"
  depends_on "zlib"

  def install
    awslc = Formula["aws-lc"].opt_prefix
    zlib = Formula["zlib"].opt_prefix
    libedit = Formula["libedit"].opt_prefix
    sdkroot = MacOS.sdk_path
    install_root = libexec/"hpnssh-awslc"

    set_default_port_22
    apply_awslc_patches
    set_apple_silicon_flags(awslc, zlib, libedit, sdkroot)

    system "autoreconf", "-fi"
    system "./configure",
      "--prefix=#{install_root}",
      "--exec-prefix=#{install_root}",
      "--sysconfdir=#{etc}/hpnssh-awslc",
      "--libexecdir=#{install_root}/libexec",
      "--localstatedir=#{var}/hpnssh-awslc",
      "--with-privsep-path=#{var}/hpnssh-awslc/empty",
      "--with-pid-dir=#{var}/hpnssh-awslc/run",
      "--with-ssl-dir=#{awslc}",
      "--with-zlib=#{zlib}",
      "--with-pam",
      "--with-audit=bsm",
      "--with-libedit=#{libedit}"

    system "make", "-j#{ENV.make_jobs}"
    system "make", "install"
    strip_hpn_macho_binaries(install_root)
    link_suffixed_commands(install_root)
  end

  test do
    assert_match "OpenSSH_10.3p1_hpn18.9.0", shell_output("#{bin}/hpnssh-awslc -V 2>&1")
    assert_match "AWS-LC", shell_output("#{bin}/hpnssh-awslc -V 2>&1")
    assert_match "port 22", shell_output("#{bin}/hpnssh-awslc -G localhost 2>/dev/null")
    assert_match "chacha20-poly1305@openssh.com", shell_output("#{bin}/hpnssh-awslc -Q cipher")
    refute_match "chacha20-poly1305-mt@hpnssh.org", shell_output("#{bin}/hpnssh-awslc -Q cipher")
  end

  private

  def set_default_port_22
    inreplace "ssh.h", /^#define[ \t]+HPNSSH_DEFAULT_PORT[ \t]+[0-9]+/,
      "#define HPNSSH_DEFAULT_PORT    22"
    inreplace "sshd_config", /^Port 2222$/, "Port 22" if File.exist?("sshd_config")
  end

  def apply_awslc_patches
    inreplace "cipher-ctr-mt.c",
      "#if defined(WITH_OPENSSL) && !defined(WITH_OPENSSL3)",
      "#if defined(WITH_OPENSSL) && !defined(WITH_OPENSSL3) && !defined(HPNSSH_AWSLC)"

    inreplace "cipher.c",
      "if (strstr(cc->cipher->name, \"ctr\") && enable_threads) {\n#ifdef WITH_OPENSSL3",
      "if (strstr(cc->cipher->name, \"ctr\") && enable_threads) {\n" \
      "#if defined(HPNSSH_AWSLC)\n" \
      "\t\t\tdebug(\"AWS-LC lacks EVP_CIPHER_meth_*; using AWS-LC native AES-CTR\");\n" \
      "#elif defined(WITH_OPENSSL3)"

    inreplace "cipher.c",
      "#if !defined(WITH_OPENSSL3)\n\tif (cc->meth_ptr != NULL) {",
      "#if !defined(WITH_OPENSSL3) && !defined(HPNSSH_AWSLC)\n\tif (cc->meth_ptr != NULL) {"

    inreplace "cipher.c", <<~CIPHER_ORIG, <<~CIPHER_AWSLC
      #ifdef WITH_OPENSSL
      \t{ "chacha20-poly1305-mt@hpnssh.org",
      \t\t\t\t8, 64, 0, 16, CFLAG_CHACHAPOLY|CFLAG_MT, NULL },
      #endif
    CIPHER_ORIG
      #ifndef HPNSSH_AWSLC
      #ifdef WITH_OPENSSL
      \t{ "chacha20-poly1305-mt@hpnssh.org",
      \t\t\t\t8, 64, 0, 16, CFLAG_CHACHAPOLY|CFLAG_MT, NULL },
      #endif
      #endif
    CIPHER_AWSLC

    inreplace "cipher-chachapoly-libcrypto-mt.c",
      "#if defined(HAVE_EVP_CHACHA20) && !defined(HAVE_BROKEN_CHACHA20)",
      awslc_chachapoly_stubs
  end

  def awslc_chachapoly_stubs
    <<~C
      #if defined(HPNSSH_AWSLC)

      #include "cipher-chachapoly-libcrypto-mt.h"
      #include "ssherr.h"

      struct chachapoly_ctx_mt {
      \tint disabled;
      };

      struct chachapoly_ctx_mt *
      chachapoly_new_mt(u_int startseqnr, const u_char *key, u_int keylen)
      {
      \t(void)startseqnr;
      \t(void)key;
      \t(void)keylen;
      \treturn NULL;
      }

      void
      chachapoly_free_mt(struct chachapoly_ctx_mt *ctx_mt)
      {
      \t(void)ctx_mt;
      }

      int
      chachapoly_crypt_mt(struct chachapoly_ctx_mt *ctx_mt, u_int seqnr,
          u_char *dest, const u_char *src, u_int len, u_int aadlen,
          u_int authlen, int do_encrypt)
      {
      \t(void)ctx_mt;
      \t(void)seqnr;
      \t(void)dest;
      \t(void)src;
      \t(void)len;
      \t(void)aadlen;
      \t(void)authlen;
      \t(void)do_encrypt;
      \treturn SSH_ERR_INVALID_ARGUMENT;
      }

      int
      chachapoly_get_length_mt(struct chachapoly_ctx_mt *ctx_mt,
          u_int *plenp, u_int seqnr, const u_char *cp, u_int len)
      {
      \t(void)ctx_mt;
      \t(void)plenp;
      \t(void)seqnr;
      \t(void)cp;
      \t(void)len;
      \treturn SSH_ERR_INVALID_ARGUMENT;
      }

      #elif defined(HAVE_EVP_CHACHA20) && !defined(HAVE_BROKEN_CHACHA20)
    C
  end

  def set_apple_silicon_flags(awslc, zlib, libedit, sdkroot)
    opt_flags = "-arch arm64 -O3 -flto -g0 -mcpu=apple-m2"
    ENV.append "CFLAGS", opt_flags
    ENV.append "CXXFLAGS", opt_flags
    ENV.append "CPPFLAGS",
      "-isysroot #{sdkroot} -I#{awslc}/include -I#{zlib}/include -I#{libedit}/include -DHPNSSH_AWSLC"
    ENV.append "LDFLAGS",
      "-arch arm64 -flto -isysroot #{sdkroot} -Wl,-search_paths_first " \
      "-L#{awslc}/lib -L#{zlib}/lib -L#{libedit}/lib " \
      "-Wl,-rpath,#{awslc}/lib -Wl,-rpath,#{zlib}/lib -Wl,-rpath,#{libedit}/lib"
    ENV.prepend_path "PKG_CONFIG_PATH", "#{awslc}/lib/pkgconfig"
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

  def link_suffixed_commands(install_root)
    (install_root/"bin").children.each do |path|
      next unless path.basename.to_s.start_with?("hpn")

      bin.install_symlink path => "#{path.basename}-awslc"
    end
  end
end
