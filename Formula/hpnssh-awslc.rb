class HpnsshAwslc < Formula
  desc "High Performance Networking fork of OpenSSH built with AWS-LC"
  homepage "https://github.com/rapier1/hpn-ssh"
  url "https://github.com/rapier1/hpn-ssh/archive/refs/tags/hpn-18.11.1.tar.gz"
  sha256 "225238697414a73049770d87fab2453ab5871c1ae55c8853e4530ca5f2591239"
  license "SSH-OpenSSH"

  bottle do
    root_url "https://github.com/cecilyen/homebrew-hpnssh/releases/download/hpnssh-awslc-18.11.1-macos26-arm64"
    sha256 arm64_tahoe: "46f63781d3eb61fae765b4eef2c36132aa116995fe1e3ba54511c98c3c03ce83"
  end

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "llvm" => :build
  depends_on "pkgconf" => :build
  depends_on arch: :arm64
  depends_on "aws-lc"
  depends_on macos: :tahoe

  uses_from_macos "krb5"
  uses_from_macos "libedit"
  uses_from_macos "zlib"

  patch :DATA

  def install
    awslc = formula_opt_prefix("aws-lc")
    llvm = formula_opt_prefix("llvm")
    sdkroot = MacOS.sdk_path

    ENV["CC"] = (llvm/"bin/clang").to_s
    ENV["CXX"] = (llvm/"bin/clang++").to_s
    ENV["AR"] = (llvm/"bin/llvm-ar").to_s
    ENV["RANLIB"] = (llvm/"bin/llvm-ranlib").to_s
    ENV["CFLAGS"] = "-O3 -arch arm64 -flto=thin -pipe"
    ENV["CXXFLAGS"] = "-O3 -arch arm64 -flto=thin -pipe"
    ENV["CPPFLAGS"] = "-isysroot #{sdkroot} -I#{awslc}/include -DHPNSSH_AWSLC"
    ENV["LDFLAGS"] = "-arch arm64 -flto=thin -Wl,-dead_strip " \
                     "-isysroot #{sdkroot} -Wl,-search_paths_first " \
                     "-L#{awslc}/lib -Wl,-rpath,#{awslc}/lib -framework Kerberos"
    ENV.prepend_path "PKG_CONFIG_PATH", awslc/"lib/pkgconfig"
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
      "--with-ssl-dir=#{awslc}",
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
    assert_match "AWS-LC", version_output

    config = shell_output("#{bin}/hpnssh -F /dev/null -G localhost 2>/dev/null")
    assert_match(/^port 22$/, config)
    assert_match "chacha20-poly1305@openssh.com", shell_output("#{bin}/hpnssh -Q cipher")
    refute_match "chacha20-poly1305-mt@hpnssh.org", shell_output("#{bin}/hpnssh -Q cipher")

    linkage = shell_output("otool -L #{bin}/hpnssh")
    assert_match %r{/opt/aws-lc/lib/libcrypto\.dylib}, linkage
    assert_match "/usr/lib/libz.1.dylib", linkage
    assert_match "Kerberos.framework", linkage
    refute_match "libbsm", linkage

    sftp_linkage = shell_output("otool -L #{bin}/hpnsftp")
    assert_match "/usr/lib/libedit.3.dylib", sftp_linkage
    assert_path_exists etc/"hpnssh/ssh_known_hosts"
    assert_path_exists etc/"hpnssh/ssh_known_hosts2"
    refute_path_exists etc/"hpnssh/ssh_host_ed25519_key"
    system "/usr/bin/codesign", "--verify", bin/"hpnssh"
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
    [bin, libexec].each do |dir|
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
--- a/myproposal.h
+++ b/myproposal.h
@@ -62,7 +62,7 @@
 
 /*if we aren't using OpenSSL we need to remove
  * the parallel ChaCha20 cipher from the list */
-#ifdef WITH_OPENSSL
+#if defined(WITH_OPENSSL) && !defined(HPNSSH_AWSLC)
 #define	KEX_SERVER_ENCRYPT \
 	"chacha20-poly1305-mt@hpnssh.org,"  \
 	"chacha20-poly1305@openssh.com,"    \
--- a/kex.c
+++ b/kex.c
@@ -1088,7 +1088,7 @@
 			peer[nenc] = NULL;
 			goto out;
 		}
-#ifdef WITH_OPENSSL
+#if defined(WITH_OPENSSL) && !defined(HPNSSH_AWSLC)
 		if ((strcmp(newkeys->enc.name, "chacha20-poly1305@openssh.com")
 		    == 0) && (match_list("chacha20-poly1305-mt@hpnssh.org",
 		    my[nenc], NULL) != NULL)) {
--- a/cipher-ctr-mt.c
+++ b/cipher-ctr-mt.c
@@ -23,7 +23,7 @@
  */
 #include "includes.h"
 
-#if defined(WITH_OPENSSL) && !defined(WITH_OPENSSL3)
+#if defined(WITH_OPENSSL) && !defined(WITH_OPENSSL3) && !defined(HPNSSH_AWSLC)
 #include <sys/types.h>
 
 #include <stdarg.h>
--- a/cipher.c
+++ b/cipher.c
@@ -122,9 +122,11 @@
 #endif
 	{ "chacha20-poly1305@openssh.com",
 				8, 64, 0, 16, CFLAG_CHACHAPOLY, NULL },
+#ifndef HPNSSH_AWSLC
 #ifdef WITH_OPENSSL
 	{ "chacha20-poly1305-mt@hpnssh.org",
 				8, 64, 0, 16, CFLAG_CHACHAPOLY|CFLAG_MT, NULL },
+#endif
 #endif
 	{ "none",               8, 0, 0, 0, CFLAG_NONE, NULL },
 
@@ -382,7 +384,9 @@
 	 * we load our hpnssh provider. If it doesn't (OSSL < 1.1) then we use the
 	 * _meth_new process found in cipher-ctr-mt.c */
 	if (strstr(cc->cipher->name, "ctr") && enable_threads) {
-#ifdef WITH_OPENSSL3
+#if defined(HPNSSH_AWSLC)
+			debug("AWS-LC lacks EVP_CIPHER_meth_*; using AWS-LC native AES-CTR");
+#elif defined(WITH_OPENSSL3)
 		/* this version of openssl uses providers */
 		OSSL_LIB_CTX *aes_lib = NULL; /* probably not needed */
 		OSSL_PROVIDER *aes_mt_provider = NULL;
@@ -590,7 +594,7 @@
 	 * the ctx it is a part of it doesn't get freed. So...
 	 * cjr 2/7/2023
 	 */
-#if !defined(WITH_OPENSSL3)
+#if !defined(WITH_OPENSSL3) && !defined(HPNSSH_AWSLC)
 	if (cc->meth_ptr != NULL) {
 		EVP_CIPHER_meth_free((void *)(EVP_CIPHER *)cc->meth_ptr);
 		cc->meth_ptr = NULL;
--- a/cipher-chachapoly-libcrypto-mt.c
+++ b/cipher-chachapoly-libcrypto-mt.c
@@ -23,8 +23,60 @@
 #include "openbsd-compat/openssl-compat.h"
 #endif
 
-#if defined(HAVE_EVP_CHACHA20) && !defined(HAVE_BROKEN_CHACHA20)
+#if defined(HPNSSH_AWSLC)
+
+#include "cipher-chachapoly-libcrypto-mt.h"
+#include "ssherr.h"
+
+struct chachapoly_ctx_mt {
+	int disabled;
+};
+
+struct chachapoly_ctx_mt *
+chachapoly_new_mt(u_int startseqnr, const u_char *key, u_int keylen)
+{
+	(void)startseqnr;
+	(void)key;
+	(void)keylen;
+	return NULL;
+}
+
+void
+chachapoly_free_mt(struct chachapoly_ctx_mt *ctx_mt)
+{
+	(void)ctx_mt;
+}
+
+int
+chachapoly_crypt_mt(struct chachapoly_ctx_mt *ctx_mt, u_int seqnr,
+    u_char *dest, const u_char *src, u_int len, u_int aadlen,
+    u_int authlen, int do_encrypt)
+{
+	(void)ctx_mt;
+	(void)seqnr;
+	(void)dest;
+	(void)src;
+	(void)len;
+	(void)aadlen;
+	(void)authlen;
+	(void)do_encrypt;
+	return SSH_ERR_INVALID_ARGUMENT;
+}
+
+int
+chachapoly_get_length_mt(struct chachapoly_ctx_mt *ctx_mt,
+    u_int *plenp, u_int seqnr, const u_char *cp, u_int len)
+{
+	(void)ctx_mt;
+	(void)plenp;
+	(void)seqnr;
+	(void)cp;
+	(void)len;
+	return SSH_ERR_INVALID_ARGUMENT;
+}
 
+#elif defined(HAVE_EVP_CHACHA20) && !defined(HAVE_BROKEN_CHACHA20)
+
 #include <sys/types.h>
 #include <unistd.h> /* needed for getpid under C99 */
 #include <stdarg.h> /* needed for log.h */
