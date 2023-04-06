#!/usr/local/bin/perl

use CPAN::FindDependencies;
use File::Basename;
use Digest::SHA;

my %installed;

my @needed = ( "Term::ReadKey", "XML::SAX", "JSON", "MongoDB", "JSON", "Net::SSLeay", "Term::ReadLine::Gnu" );

print << 'END_BLOCK';
class Polymake < Formula
  desc "Tool for computations in algorithmic discrete geometry"
  homepage "https://polymake.org/"
  url "https://polymake.org/lib/exe/fetch.php/download/polymake-4.9.tar.bz2"
  sha256 "bc7335bfca7a3e687b7961b052418ace0e4295f99a86c6cf4832bc2a51b0deea"

  depends_on "boost"
  depends_on "flint"
  depends_on "gmp"
  depends_on "mpfr"
  depends_on "ninja"
  depends_on "openssl@1.1"
  depends_on "perl" if MacOS.version == :big_sur || MacOS.version == :ventura || MacOS.version == :monterey
  depends_on "ppl"
  depends_on "readline"

END_BLOCK

foreach my $n (@needed) {
  my @dependencies = CPAN::FindDependencies::finddeps($n,perl=>"5.18");

  my $maxdepth = 0;
  foreach my $dep (@dependencies) {
    if ($dep->depth() > $maxdepth) {
      $maxdepth = $dep->depth();
    }
  } 

  for( my $d=$maxdepth; $d >= 0; $d-- ) {
    foreach my $dep (@dependencies) {
      if ($dep->depth() == $d ) {
        next if exists $installed{$dep->name()};
        $installed{$dep->name()} = 1;
        my ($filename,$path,$suffix) = fileparse($dep->distribution());
        next if $filename =~ /^perl-5/;
        print '  resource "'.$dep->name().'" do'."\n";
        my $url = "https://cpan.metacpan.org/authors/id/";
        $url .= $dep->distribution();
        print '    url "'.$url.'"'."\n";
        system "curl -sOL $url > /dev/null";
        my $sha = Digest::SHA->new(256);
        $sha->addfile($filename);
        my $digest = $sha->hexdigest;
        print '    sha256 "'.$digest.'"'."\n";
        #if ( $dep->name() eq "Term::ReadLine::Gnu" ) {
        #  print '    if MacOS.version == :big_sur'."\n";
        #  print '      patch do'."\n";
        #  print '        url "https://gist.githubusercontent.com/apaffenholz/9db9fd984d2608f235a73b37a3a09301/raw/99fd09a404ca6d7ed9e24b55d495703dcf3356cd/polymake-homebrew-term-readline-gnu.patch"'."\n";
        #  print '        sha256 "0c6b0e266b06aa817df84c7087c6becd97f1335de4957c968a857d868eb79e27"'."\n";
        #  print '      end'."\n";
        #  print '    end'."\n";
        #}
        print "  end\n\n"
      }
    }
  }
}

print << 'END_BLOCK';
  def install
    # Fix file not found errors for /usr/lib/system/libsystem_symptoms.dylib and
    # /usr/lib/system/libsystem_darwin.dylib on 10.11 and 10.12, respectively
    ENV["SDKROOT"] = MacOS.sdk_path if MacOS.version == :sierra || MacOS.version == :el_capitan
    ENV.prepend_create_path "PERL5LIB", libexec/"perl5/lib/perl5"
    ENV.prepend_path "PERL5LIB", libexec/"perl5/lib/perl5/darwin-thread-multi-2level"

    resources.each do |r|
      next if r.name == "Term::ReadLine::Gnu"

      r.stage do
        # Prevent the Makefile to try and build universal binaries
        ENV.refurbish_args
        if MacOS.version == :catalina || MacOS.version == :mojave
          system_perl_subpath = "/System/Library/Perl/5.18/darwin-thread-multi-2level/CORE/"
          perl_cpath = "#{MacOS.sdk_path}#{system_perl_subpath}"
          ENV.prepend_create_path "CPATH", perl_cpath.to_str
        end
        case r.name
        when "IO::Socket::IP"
          system "perl", "Build.PL", "--install_base", libexec
          system "./Build"
          system "./Build", "test"
          system "./Build", "install"
        when "Net::SSLeay" 
          ENV.prepend_create_path "OPENSSL_PREFIX", Formula["openssl@1.1"].opt_prefix
          system "yes -N | perl Makefile.PL INSTALL_BASE=#{libexec}/perl5" 
          system "make", "install"
        when "XML::SAX" 
          system "yes | perl Makefile.PL INSTALL_BASE=#{libexec}/perl5"
          system "make", "install"
        else
          system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}/perl5"
          system "make", "install"
        end
      end
    end

    system "./configure", "--prefix=#{prefix}",
                          "--without-bliss",
                          "--without-java",
                          "--without-scip",
                          "--without-soplex",
                          "--without-singular",
                          "--with-brew=bottle",
                          "CXXFLAGS=-I#{HOMEBREW_PREFIX}/include",
                          "LDFLAGS=-L#{HOMEBREW_PREFIX}/lib"

    system "ninja", "-C", "build/Opt", "install"
    bin.env_script_all_files(libexec/"perl5/bin", PERL5LIB: ENV["PERL5LIB"])

    resource("Term::ReadLine::Gnu").stage do
      # Prevent the Makefile to try and build universal binaries
      ENV.refurbish_args
      system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}/perl5",
                     "--includedir=#{Formula["readline"].opt_include}",
                     "--libdir=#{Formula["readline"].opt_lib}"
      system "make", "install"
    end
  end

  def caveats
    <<~EOS
      Note: This version comes without support for SVG export.

      If you had any other version of polymake installed on your Mac
      (both previous versions installed via Homebrew or any other installations)
      you must start polymake once with
      "polymake --reconfigure"
      to remove the configuration of SVG support from your local
      polymake setup. Afterwards you can use "polymake" as usual.
    EOS
  end

  test do
    assert_match "1 23 23 1", shell_output("#{bin}/polymake 'print cube(3)->H_STAR_VECTOR'")
    command = "LIBRARY_PATH=/usr/local/lib #{bin}/polymake 'my $a=new Array<SparseMatrix<Float>>' 2>&1"
    assert_match "", shell_output(command)
    assert_match(/^polymake:  WARNING: Recompiling in .* please be patient\.\.\.$/, shell_output(command))
  end
END_BLOCK
print "end\n";
