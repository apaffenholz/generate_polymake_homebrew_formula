#!/usr/bin/perl

use CPAN::FindDependencies;
use File::Basename;
use Digest::SHA;

my %installed;

my @needed = ("Term::ReadLine::Gnu", "SVG", "Moo", "MongoDB", "JSON", "Net::SSLeay" );

print << 'END_BLOCK';
class Polymake < Formula
  desc "Tool for computations in algorithmic discrete geometry"
  homepage "https://polymake.org/"
  url "https://polymake.org/lib/exe/fetch.php/download/polymake-4.0r1.tar.bz2"
  version "4.0r1"
  sha256 "06654c5b213e74d7ff521a4f52e446f46a54e52e7da795396b79dd8beead3000"

  depends_on "boost"
  depends_on "gmp"
  depends_on "mpfr"
  depends_on "ninja"
  depends_on "ppl"
  depends_on "readline"
  depends_on "singular"

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

    resource("Term::ReadLine::Gnu").stage do
      # Prevent the Makefile to try and build universal binaries
      ENV.refurbish_args
      system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}/perl5",
                     "--includedir=#{Formula["readline"].opt_include}",
                     "--libdir=#{Formula["readline"].opt_lib}"
      system "make", "install"
    end

    resources.each do |r|
      next if r.name == "Term::ReadLine::Gnu"

      r.stage do
        # Prevent the Makefile to try and build universal binaries
        ENV.refurbish_args
        if MacOS.version == :catalina
          system_perl_subpath = "/System/Library/Perl/5.18/darwin-thread-multi-2level/CORE/"
          perl_cpath = "#{MacOS.sdk_path}#{system_perl_subpath}"
          ENV.prepend_create_path "CPATH", perl_cpath.to_str
        end
        system "perl", "Makefile.PL", "INSTALL_BASE=#{libexec}/perl5"
        system "make", "install"
      end
    end

    system "./configure", "--prefix=#{prefix}",
                          "--without-bliss",
                          "--without-java",
                          "--without-soplex"

    system "ninja", "-C", "build/Opt", "install"
    bin.env_script_all_files(libexec/"perl5/bin", :PERL5LIB => ENV["PERL5LIB"])
  end

  test do
    assert_match "1 23 23 1", shell_output("#{bin}/polymake 'print cube(3)->H_STAR_VECTOR'")
    command = "LIBRARY_PATH=/usr/local/lib #{bin}/polymake 'my $a=new Array<SparseMatrix<Float>>' 2>&1"
    assert_match "", shell_output(command)
    assert_match /^polymake:  WARNING: Recompiling in .* please be patient\.\.\.$/, shell_output(command)
  end
END_BLOCK
print "end";