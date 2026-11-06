#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "time"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby package-existing-bottle.rb --formula NAME --build-dir DIR --work-dir DIR [--dry-run]"
  parser.on("--formula NAME") { |value| options[:formula] = value }
  parser.on("--build-dir DIR") { |value| options[:build] = File.realpath(value) }
  parser.on("--work-dir DIR") { |value| options[:work] = File.expand_path(value) }
  parser.on("--dry-run") { options[:dry_run] = true }
end.parse!
abort "Missing --formula, --build-dir or --work-dir" unless %i[formula build work].all? { |key| options[key] }

def capture!(*command)
  output, status = Open3.capture2e(*command)
  raise "#{command.first} failed: #{output}" unless status.success?

  output.strip
end

def sha256(path)
  Digest::SHA256.file(path).hexdigest
end

# Read the executable code directly; packaging must never change instructions.
def code_hash(data)
  raise "Expected a thin ARM64 Mach-O executable" unless data.unpack("L<L<") == [0xfeedfacf, 0x100000c]

  offset = 32
  data.byteslice(16, 4).unpack1("L<").times do
    command, size = data.byteslice(offset, 8).unpack("L<L<")
    if command == 0x19
      sections = data.byteslice(offset + 64, 4).unpack1("L<")
      sections.times do |index|
        section = offset + 72 + index * 80
        next unless data.byteslice(section, 16).delete("\0") == "__text"
        next unless data.byteslice(section + 16, 16).delete("\0") == "__TEXT"

        length = data.byteslice(section + 40, 8).unpack1("Q<")
        start = data.byteslice(section + 48, 4).unpack1("L<")
        return Digest::SHA256.hexdigest(data.byteslice(start, length))
      end
    end
    offset += size
  end
  raise "Missing __TEXT,__text section"
end

def write_json(path, object)
  File.write(path, JSON.pretty_generate(object) + "\n")
end

name = options.fetch(:formula)
crypto = { "hpnssh-awslc" => "aws-lc", "hpnssh-openssl" => "openssl@4" }.fetch(name)
tap = File.expand_path("..", __dir__)
formula_path = File.join(tap, "Formula", "#{name}.rb")
formula = File.read(formula_path)
version = formula.match(%r{refs/tags/hpn-([\d.]+)\.tar\.gz"})[1]
source = options.fetch(:build)
makefile = File.read(File.join(source, "Makefile"))
old_prefix = makefile.match(/^prefix=(\/[^\n]+)$/)[1]
version_output = capture!(File.join(source, "hpnssh"), "-V")
raise "Build and formula versions differ" unless version_output.include?("_hpn#{version},")
raise "Wrong crypto build" unless version_output.include?(crypto == "aws-lc" ? "AWS-LC" : "OpenSSL 4.")

groups = {
  "bin" => %w[hpnssh hpnscp hpnsftp hpnssh-add hpnssh-agent hpnssh-keygen hpnssh-keyscan],
  "sbin" => %w[hpnsshd],
  "libexec" => %w[hpnsshd-session hpnsshd-auth hpnssh-keysign hpnssh-pkcs11-helper hpnssh-sk-helper hpnsftp-server],
}
originals = {}
groups.each do |directory, names|
  names.each do |binary|
    path = File.join(source, binary)
    raise "Missing executable: #{path}" unless File.executable?(path)

    capture!("/usr/bin/codesign", "--verify", "--strict", path)
    originals[File.join(directory, binary)] = { "sha256" => sha256(path), "code_sha256" => code_hash(File.binread(path)) }
  end
end
manpages = Dir.glob(File.join(source, "*.{1,5,8}.out")).sort
raise "Expected 15 generated manual pages" unless manpages.length == 15
config_names = %w[ssh_config sshd_config moduli]
config_names.each { |file| raise "Missing #{file}.out" unless File.file?(File.join(source, "#{file}.out")) }

tag = "#{name}-#{version}-macos26-arm64"
output = File.join(tap, "dist", tag)
puts "#{name}: #{version_output}"
puts "Copy #{originals.length} executables, #{manpages.length} manual pages, and default configuration."
puts "Relocate #{old_prefix} to /opt/homebrew; helper alias: /opt/homebrew/share/hpnssh."
puts "Output: #{output}"
exit if options[:dry_run]
raise "Output already exists: #{output}" if File.exist?(output)

cellar = File.join(options.fetch(:work), "#{name}-cellar")
keg = File.join(cellar, name, version)
raise "Staging keg already exists: #{keg}" if File.exist?(keg)

FileUtils.mkdir_p([keg, output])
replacements = {
  "#{old_prefix}/libexec" => "/opt/homebrew/share/hpnssh",
  "#{old_prefix}/var" => "/opt/homebrew/var/hpnssh",
  old_prefix => "/opt/homebrew",
}
replacements.each { |old, replacement| raise "Replacement is too long" if replacement.bytesize > old.bytesize }

packaged = {}
originals.each do |relative, original|
  destination = File.join(keg, relative)
  FileUtils.mkdir_p(File.dirname(destination))
  FileUtils.cp(File.join(source, File.basename(relative)), destination, preserve: true)
  data = File.binread(destination)
  replacements.each do |old, replacement|
    # Slash padding preserves both binary size and offsets of shared suffixes.
    data = data.gsub(old.b, (replacement + "/" * (old.bytesize - replacement.bytesize)).b)
  end
  raise "Original prefix remains in #{relative}" if data.include?(old_prefix.b)

  File.binwrite(destination, data)
  capture!("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", destination)
  capture!("/usr/bin/codesign", "--verify", "--strict", destination)
  raise "Machine code changed in #{relative}" unless code_hash(File.binread(destination)) == original.fetch("code_sha256")

  packaged[relative] = original.merge("packaged_sha256" => sha256(destination))
end

config_dir = File.join(keg, ".bottle", "etc", "hpnssh")
FileUtils.mkdir_p(config_dir)
config_names.each do |file|
  text = File.read(File.join(source, "#{file}.out"))
  replacements.each { |old, replacement| text = text.gsub(old, replacement) }
  File.write(File.join(config_dir, file), text)
end
%w[ssh_known_hosts ssh_known_hosts2].each { |file| File.write(File.join(config_dir, file), "") }
FileUtils.mkdir_p(File.join(keg, ".bottle", "var", "hpnssh", "empty"))
FileUtils.mkdir_p(File.join(keg, ".bottle", "var", "hpnssh", "run"))

manpages.each do |path|
  basename = File.basename(path, ".out")
  destination = File.join(keg, "share", "man", "man#{File.extname(basename)[1..]}", basename)
  FileUtils.mkdir_p(File.dirname(destination))
  text = File.read(path)
  replacements.each { |old, replacement| text = text.gsub(old, replacement) }
  File.write(destination, text)
end
FileUtils.mkdir_p(File.join(keg, "share"))
File.symlink("../libexec", File.join(keg, "share", "hpnssh"))
FileUtils.cp(File.join(source, "LICENCE"), keg)
FileUtils.mkdir_p(File.join(keg, ".brew"))
source_formula = formula.sub(/^  bottle do\n.*?^  end\n\n/m, "")
File.write(File.join(keg, ".brew", "#{name}.rb"), source_formula)

dependency_receipt = JSON.parse(File.read(File.join(File.realpath("/opt/homebrew/opt/#{crypto}"), "INSTALL_RECEIPT.json")))
crypto_version = dependency_receipt.fetch("source").fetch("versions").fetch("stable")
dependencies = dependency_receipt.fetch("runtime_dependencies").map { |dep| dep.merge("declared_directly" => false) }
dependencies << {
  "full_name" => crypto, "version" => crypto_version, "revision" => 0,
  "pkg_version" => crypto_version, "declared_directly" => true,
}
receipt = {
  "homebrew_version" => capture!("/opt/homebrew/bin/brew", "--version").sub(/^Homebrew /, ""),
  "used_options" => [], "unused_options" => [], "built_as_bottle" => false,
  "built_prefix" => "/opt/homebrew", "poured_from_bottle" => false,
  "loaded_from_api" => false, "installed_on_request" => true,
  "changed_files" => [], "linkage_files" => originals.keys,
  "binary_relocation_files" => originals.keys,
  "source_modified_time" => File.mtime(File.join(source, "version.h")).to_i,
  "compiler" => "clang", "runtime_dependencies" => dependencies, "arch" => "arm64",
  "source" => {
    "spec" => "stable", "versions" => { "stable" => version, "head" => nil, "version_scheme" => 0 },
    "path" => "/opt/homebrew/Cellar/#{name}/#{version}/.brew/#{name}.rb",
    "tap" => "cecilyen/hpnssh", "tap_git_head" => nil,
  },
  "built_on" => {
    "os" => "Macintosh", "os_version" => "macOS #{capture!('/usr/bin/sw_vers', '-productVersion')}",
    "cpu_family" => capture!("/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"),
  },
}
# The binaries predate this packaging run; do not claim a Homebrew source build.
write_json(File.join(keg, "INSTALL_RECEIPT.json"), receipt)

provenance = {
  "version" => version_output, "packaged_at" => Time.now.utc.iso8601,
  "recompiled" => false, "original_prefix" => old_prefix,
  "target_prefix" => "/opt/homebrew", "helper_directory" => "/opt/homebrew/share/hpnssh",
  "cflags" => makefile.match(/^CFLAGS=(.*)$/)[1].strip,
  "ldflags" => makefile.match(/^LDFLAGS=(.*)$/)[1].strip,
  "crypto_dependency" => { "formula" => crypto, "version" => crypto_version },
  "sandbox" => File.read(File.join(source, "config.h")).include?("#define SANDBOX_DARWIN 1") ? "darwin" : "none",
  "binaries" => packaged,
}
write_json(File.join(output, "BUILD_PROVENANCE.json"), provenance)

archive_name = "#{name}-#{version}.arm64_tahoe.bottle.tar.gz"
archive = File.join(output, archive_name)
tar_path = File.join(options.fetch(:work), "#{name}.tar")
capture!("/usr/bin/tar", "--no-xattrs", "--no-acls", "--no-fflags", "--uid", "0", "--gid", "0",
         "--uname", "root", "--gname", "wheel", "--format", "pax", "-cf", tar_path,
         "-C", cellar, "#{name}/#{version}")
File.open(archive, "wb") do |file|
  raise "pigz failed" unless system("pigz", "-n", "-9", "-c", tar_path, out: file)
end
digest = sha256(archive)
root_url = "https://github.com/cecilyen/homebrew-hpnssh/releases/download/#{tag}"
metadata = {
  "cecilyen/hpnssh/#{name}" => {
    "formula" => {
      "name" => name, "pkg_version" => version,
      "path" => "Library/Taps/cecilyen/homebrew-hpnssh/Formula/#{name}.rb",
      "tap_git_path" => "Formula/#{name}.rb", "tap_git_revision" => nil,
      "tap_git_remote" => "https://github.com/cecilyen/homebrew-hpnssh.git",
      "desc" => formula.match(/^  desc "([^"]+)"/)[1],
      "license" => "SSH-OpenSSH", "homepage" => "https://github.com/rapier1/hpn-ssh",
    },
    "bottle" => {
      "root_url" => root_url, "cellar" => "/opt/homebrew/Cellar", "rebuild" => 0,
      "date" => Time.now.utc.iso8601,
      "tags" => { "arm64_tahoe" => {
        "filename" => archive_name, "local_filename" => archive_name, "sha256" => digest, "tab" => receipt,
      } },
    },
  },
}
write_json(File.join(output, "#{name}--#{version}.arm64_tahoe.bottle.json"), metadata)
snapshot = formula.sub(/^  bottle do\n.*?^  end\n/m, <<~BOTTLE.lines.map { |line| "  #{line}" }.join)
  bottle do
    root_url "#{root_url}"
    sha256 arm64_tahoe: "#{digest}"
  end
BOTTLE
File.write(File.join(output, "#{name}.rb"), snapshot)
FileUtils.cp(File.join(tap, "README.md"), File.join(output, "homebrew-tap-README.md"))
FileUtils.cp(File.join(tap, "RELEASE.md"), output)
FileUtils.cp(__FILE__, output)
notes = <<~NOTES
  # HPN-SSH #{version} #{crypto == 'aws-lc' ? 'AWS-LC' : 'OpenSSL'} bottle

  - #{version_output}
  - macOS 26 or newer; ARM64 Homebrew at /opt/homebrew
  - Runtime dependency: #{crypto} #{crypto_version}; macOS zlib and libedit
  - M1 instruction baseline, M2 tuning, -O3, ThinLTO
  - Packaged from existing stripped executables; no recompilation
  - Relocated installation paths and ad-hoc signed copies; unchanged machine code
  - Default port 22; no private host keys or daemon startup
  - Conflicts with the other HPN variant and Homebrew openssh
  - Existing build sandbox setting: #{provenance.fetch('sandbox')}

  Review the existing lack of a Darwin privilege-separation sandbox before
  deploying hpnsshd. Packaging does not change that build configuration.

  Install:

  ```sh
  brew tap cecilyen/hpnssh
  brew install #{name}
  hpnssh -V
  ```

  BUILD_PROVENANCE.json records original and packaged executable checksums,
  identical machine-code checksums, compiler flags, and dependency versions.
NOTES
File.write(File.join(output, "RELEASE_NOTES.md"), notes)
sums = Dir.children(output).sort.map { |file| "#{sha256(File.join(output, file))}  #{file}\n" }.join
File.write(File.join(output, "SHA256SUMS"), sums)
originals.each do |relative, original|
  raise "Original executable changed: #{relative}" unless sha256(File.join(source, File.basename(relative))) == original.fetch("sha256")
end
puts "Bottle SHA256: #{digest}"
puts "Verified #{originals.length} signatures, unchanged machine-code sections, and unchanged original executables."
