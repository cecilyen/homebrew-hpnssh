class HpnsshOpenssl < Formula
  desc "High Performance Networking fork of OpenSSH built with OpenSSL 3"
  homepage "https://github.com/rapier1/hpn-ssh"
  url "https://github.com/rapier1/hpn-ssh/archive/refs/tags/hpn-18.11.1.tar.gz"
  sha256 "225238697414a73049770d87fab2453ab5871c1ae55c8853e4530ca5f2591239"
  license "SSH-OpenSSH"

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "llvm" => :build
  depends_on "pkgconf" => :build
  depends_on arch: :arm64
  depends_on macos: :tahoe
  depends_on "openssl@3"

  uses_from_macos "krb5"
  uses_from_macos "libedit"
  uses_from_macos "zlib"

  patch :DATA

  def install
    llvm = formula_opt_prefix("llvm")
    openssl = formula_opt_prefix("openssl@3")
    sdkroot = MacOS.sdk_path

    ENV["CC"] = (llvm/"bin/clang").to_s
    ENV["CXX"] = (llvm/"bin/clang++").to_s
    ENV["AR"] = (llvm/"bin/llvm-ar").to_s
    ENV["RANLIB"] = (llvm/"bin/llvm-ranlib").to_s
    ENV["CFLAGS"] = "-O3 -arch arm64 -flto=thin -pipe"
    ENV["CXXFLAGS"] = "-O3 -arch arm64 -flto=thin -pipe"
    ENV["CPPFLAGS"] = "-isysroot #{sdkroot} -I#{openssl}/include"
    ENV["LDFLAGS"] = "-arch arm64 -flto=thin -Wl,-dead_strip " \
                     "-isysroot #{sdkroot} -Wl,-search_paths_first " \
                     "-L#{openssl}/lib -Wl,-rpath,#{openssl}/lib -framework Kerberos"
    ENV.prepend_path "PKG_CONFIG_PATH", openssl/"lib/pkgconfig"
    ENV["KRB5CONF"] = "/usr/bin/krb5-config"

    system "autoreconf", "-fi"
    system "./configure",
      "--prefix=#{prefix}",
      "--exec-prefix=#{prefix}",
      "--sysconfdir=#{etc}",
      "--libexecdir=#{libexec}",
      "--localstatedir=#{var}/hpnssh",
      "--with-privsep-path=#{var}/hpnssh/empty",
      "--with-pid-dir=#{var}/hpnssh/run",
      "--with-ssl-dir=#{openssl}",
      "--with-zlib=/usr",
      "--with-pam",
      "--with-kerberos5=/usr",
      "--with-libedit=/usr"

    system "make", "-j#{ENV.make_jobs}"
    system "make", "install-nokeys"
    create_global_known_hosts_files
    strip_and_sign_executables
  end

  test do
    version_output = shell_output("#{bin}/hpnssh -V 2>&1")
    assert_match "OpenSSH_10.5p1_hpn18.11.1", version_output
    assert_match "OpenSSL 3.", version_output
    refute_match "AWS-LC", version_output

    config = shell_output("#{bin}/hpnssh -F /dev/null -G localhost 2>/dev/null")
    assert_match(/^port 22$/, config)

    ciphers = shell_output("#{bin}/hpnssh -Q cipher")
    assert_match "aes128-gcm@openssh.com", ciphers
    assert_match "chacha20-poly1305-mt@hpnssh.org", ciphers

    linkage = shell_output("otool -L #{bin}/hpnssh")
    assert_match %r{/opt/openssl@3/lib/libcrypto\.3\.dylib}, linkage
    assert_match "/usr/lib/libz.1.dylib", linkage
    assert_match "Kerberos.framework", linkage
    refute_match "libbsm", linkage

    sftp_linkage = shell_output("otool -L #{bin}/hpnsftp")
    assert_match "/usr/lib/libedit.3.dylib", sftp_linkage
    helper_strings = shell_output("strings #{libexec}/hpnssh-pkcs11-helper")
    assert_match "/usr/X11R6/bin/ssh-askpass", helper_strings
    assert_path_exists etc/"hpnssh/ssh_known_hosts"
    assert_path_exists etc/"hpnssh/ssh_known_hosts2"
    refute_path_exists etc/"hpnssh/ssh_host_ed25519_key"
    system "/usr/bin/codesign", "--verify", bin/"hpnssh"
    system "/usr/bin/codesign", "--verify", sbin/"hpnsshd"
  end

  private

  def create_global_known_hosts_files
    (etc/"hpnssh").mkpath
    %w[ssh_known_hosts ssh_known_hosts2].each do |name|
      path = etc/"hpnssh"/name
      path.write "" unless path.exist?
      path.chmod 0644
    end
  end

  def strip_and_sign_executables
    strip = Utils.safe_popen_read("xcrun", "-find", "strip").strip
    [bin, sbin, libexec].each do |dir|
      next unless dir.exist?

      dir.children.each do |path|
        next unless path.file?
        next unless path.executable?
        next unless Utils.safe_popen_read("file", path).include?("Mach-O")

        system strip, "-S", path
        system "/usr/bin/codesign", "--force", "--sign", "-", path
      end
    end
  end
end

__END__
--- a/configure.ac
+++ b/configure.ac
@@ -859,6 +859,7 @@
 	AC_CHECK_LIB([sandbox], [sandbox_apply], [
 	    SSHDLIBS="$SSHDLIBS -lsandbox"
 	])
+	AC_CHECK_DECLS(kSBXProfilePureComputation, [], [], [#include <sandbox.h>])
 	# proc_pidinfo()-based closefrom() replacement.
 	AC_CHECK_HEADERS([libproc.h])
 	AC_CHECK_FUNCS([proc_pidinfo])
@@ -3960,10 +3961,12 @@
 
 if test "x$sandbox_arg" = "xdarwin" || \
      ( test -z "$sandbox_arg" && test "x$ac_cv_func_sandbox_init" = "xyes" && \
-       test "x$ac_cv_header_sandbox_h" = "xyes") ; then
+       test "x$ac_cv_header_sandbox_h" = "xyes" && \
+       test "x$ac_cv_have_decl_kSBXProfilePureComputation" = "xyes") ; then
 	test "x$ac_cv_func_sandbox_init" != "xyes" -o \
-	     "x$ac_cv_header_sandbox_h" != "xyes" && \
-		AC_MSG_ERROR([Darwin seatbelt sandbox requires sandbox.h and sandbox_init function])
+	     "x$ac_cv_header_sandbox_h" != "xyes" -o \
+	     "x$ac_cv_have_decl_kSBXProfilePureComputation" != "xyes" && \
+		AC_MSG_ERROR([Darwin seatbelt sandbox requires sandbox.h, sandbox_init() and kSBXProfilePureComputation])
 	SANDBOX_STYLE="darwin"
 	AC_DEFINE([SANDBOX_DARWIN], [1], [Sandbox using Darwin sandbox_init(3)])
 elif test "x$sandbox_arg" = "xseccomp_filter" || \
--- a/ssh.h
+++ b/ssh.h
@@ -14,7 +14,7 @@
 
 /* Default port number. */
 #define SSH_DEFAULT_PORT	22
-#define HPNSSH_DEFAULT_PORT    2222
+#define HPNSSH_DEFAULT_PORT    22
 
 /*
 * Maximum number of certificate files that can be specified
--- a/Makefile.in
+++ b/Makefile.in
@@ -21,6 +21,6 @@
 VPATH=@srcdir@
 SSH_PROGRAM=@bindir@/hpnssh
-ASKPASS_PROGRAM=$(libexecdir)/hpnssh-askpass
+ASKPASS_PROGRAM=/usr/X11R6/bin/ssh-askpass
 SFTP_SERVER=$(libexecdir)/hpnsftp-server
 SSH_KEYSIGN=$(libexecdir)/hpnssh-keysign
 SSHD_SESSION=$(libexecdir)/hpnsshd-session
--- a/sshd_config
+++ b/sshd_config
@@ -10,7 +10,7 @@
 # possible, but leave them commented.  Uncommented options override the
 # default value.
 
-Port 2222
+Port 22
 #AddressFamily any
 #ListenAddress 0.0.0.0
 #ListenAddress ::
