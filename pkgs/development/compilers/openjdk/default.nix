{ stdenv, fetchurl, unzip, zip, procps, coreutils, alsaLib, ant, freetype
, which, bootjdk, nettools, xorg, file
, fontconfig, cpio, cacert, perl, setJavaClassPath
, minimal ? false
}:

let

  /**
   * The JRE libraries are in directories that depend on the CPU.
   */
  architecture =
    if stdenv.system == "i686-linux" then
      "i386"
    else if stdenv.system == "x86_64-linux" then
      "amd64"
    else
      throw "openjdk requires i686-linux or x86_64 linux";

  update = "80";

  build = "32";

  # On x86 for heap sizes over 700MB disable SEGMEXEC and PAGEEXEC as well.
  paxflags = if stdenv.isi686 then "msp" else "m";

  cupsSrc = fetchurl {
    url = http://ftp.easysw.com/pub/cups/1.5.4/cups-1.5.4-source.tar.bz2;
    md5 = "de3006e5cf1ee78a9c6145ce62c4e982";
  };

  baseurl = "http://hg.openjdk.java.net/jdk7u/jdk7u";
  repover = "jdk7u${update}-b${build}";
  jdk7 = fetchurl {
    url = "${baseurl}/archive/${repover}.tar.gz";
    sha256 = "1r8xnn87nmqaq2f8i3cp3i9ngq66k0c0wgkdq5cf59lkgs8wkcdi";
  };
  langtools = fetchurl {
    url = "${baseurl}/langtools/archive/${repover}.tar.gz";
    sha256 = "01alj6pfrjqyf4irll9wg34h4w9nmb3973lvbacs528qm1nxgh9r";
  };
  hotspot = fetchurl {
    url = "${baseurl}/hotspot/archive/${repover}.tar.gz";
    sha256 = "14zla8axmg5344zf45i4cj7yyli0kmdjsh9yalmzqaphpkqjqpf2";
  };
  corba = fetchurl {
    url = "${baseurl}/corba/archive/${repover}.tar.gz";
    sha256 = "19z3ay3f2q7r2ra03c6wy8b5rbdbrkq5g2dzhrqcg0n4iydd3c40";
  };
  jdk = fetchurl {
    url = "${baseurl}/jdk/archive/${repover}.tar.gz";
    sha256 = "1q0r2l9bz2cyx4fq79x6cb2f5xycw83hl5cn1d1mazgsckp590lb";
  };
  jaxws = fetchurl {
    url = "${baseurl}/jaxws/archive/${repover}.tar.gz";
    sha256 = "1lp0mww2x3b6xavb7idrzckh6iw8jd6s1fvqgfvzs853z4ifksqj";
  };
  jaxp = fetchurl {
    url = "${baseurl}/jaxp/archive/${repover}.tar.gz";
    sha256 = "0pd874dkgxkb7frxg4n9py61kkhhck4x33dcynynwb3vl6k6iy79";
  };
  openjdk = stdenv.mkDerivation rec {
    name = "openjdk-7u${update}b${build}";

    srcs = [ jdk7 langtools hotspot corba jdk jaxws jaxp ];
    sourceRoot = ".";

    outputs = [ "out" "jre" ];

    buildInputs =
      [ unzip procps ant which zip cpio nettools alsaLib
        xorg.libX11 xorg.libXt xorg.libXext xorg.libXrender xorg.libXtst
        xorg.libXi xorg.libXinerama xorg.libXcursor xorg.lndir
        fontconfig perl file bootjdk
      ];

    NIX_LDFLAGS = if minimal then null else "-lfontconfig -lXcursor -lXinerama";

    postUnpack = ''
      ls | grep jdk | grep -v '^jdk7u' | awk -F- '{print $1}' | while read p; do
        mv $p-* $(ls | grep '^jdk7u')/$p
      done
      cd jdk7u-*

      sed -i -e "s@/usr/bin/test@${coreutils}/bin/test@" \
        -e "s@/bin/ls@${coreutils}/bin/ls@" \
        hotspot/make/linux/makefiles/sa.make

      sed -i "s@/bin/echo -e@${coreutils}/bin/echo -e@" \
        {jdk,corba}/make/common/shared/Defs-utils.gmk

      tar xf ${cupsSrc}
      cupsDir=$(echo $(pwd)/cups-*)
      makeFlagsArray+=(CUPS_HEADERS_PATH=$cupsDir)
    '';

    patches = [
      ./cppflags-include-fix.patch
      ./fix-java-home.patch
      ./paxctl.patch
      ./read-truststore-from-env.patch
      ./currency-date-range.patch
      ./linux-4.0.patch
    ];

    NIX_NO_SELF_RPATH = true;

    makeFlags = [
      "SORT=${coreutils}/bin/sort"
      "ALSA_INCLUDE=${alsaLib}/include/alsa/version.h"
      "FREETYPE_HEADERS_PATH=${freetype}/include"
      "FREETYPE_LIB_PATH=${freetype}/lib"
      "MILESTONE=${update}"
      "BUILD_NUMBER=b${build}"
      "USRBIN_PATH="
      "COMPILER_PATH="
      "DEVTOOLS_PATH="
      "UNIXCOMMAND_PATH="
      "BOOTDIR=${bootjdk.home}"
      "STATIC_CXX=false"
      "UNLIMITED_CRYPTO=1"
      "FULL_DEBUG_SYMBOLS=0"
    ] ++ stdenv.lib.optional minimal "BUILD_HEADLESS=1";

    configurePhase = "true";

    preBuild = ''
      # We also need to PaX-mark in the middle of the build
      substituteInPlace hotspot/make/linux/makefiles/launcher.make \
         --replace XXX_PAXFLAGS_XXX ${paxflags}
      substituteInPlace jdk/make/common/Program.gmk  \
         --replace XXX_PAXFLAGS_XXX ${paxflags}
    '';

    installPhase = ''
      mkdir -p $out/lib/openjdk $out/share $jre/lib/openjdk

      cp -av build/*/j2sdk-image/* $out/lib/openjdk

      # Move some stuff to top-level.
      mv $out/lib/openjdk/include $out/include
      mv $out/lib/openjdk/man $out/share/man

      # jni.h expects jni_md.h to be in the header search path.
      ln -s $out/include/linux/*_md.h $out/include/

      # Remove some broken manpages.
      rm -rf $out/share/man/ja*

      # Remove crap from the installation.
      rm -rf $out/lib/openjdk/demo $out/lib/openjdk/sample

      # Move the JRE to a separate output.
      mv $out/lib/openjdk/jre $jre/lib/openjdk/
      mkdir $out/lib/openjdk/jre
      lndir $jre/lib/openjdk/jre $out/lib/openjdk/jre

      rm -rf $out/lib/openjdk/jre/bin
      ln -s $out/lib/openjdk/bin $out/lib/openjdk/jre/bin

      # Set PaX markings
      exes=$(file $out/lib/openjdk/bin/* $jre/lib/openjdk/jre/bin/* 2> /dev/null | grep -E 'ELF.*(executable|shared object)' | sed -e 's/: .*$//')
      echo "to mark: *$exes*"
      for file in $exes; do
        echo "marking *$file*"
        paxmark ${paxflags} "$file"
      done

      # Remove duplicate binaries.
      for i in $(cd $out/lib/openjdk/bin && echo *); do
        if [ "$i" = java ]; then continue; fi
        if cmp -s $out/lib/openjdk/bin/$i $jre/lib/openjdk/jre/bin/$i; then
          ln -sfn $jre/lib/openjdk/jre/bin/$i $out/lib/openjdk/bin/$i
        fi
      done

      # Generate certificates.
      pushd $jre/lib/openjdk/jre/lib/security
      rm cacerts
      perl ${./generate-cacerts.pl} $jre/lib/openjdk/jre/bin/keytool ${cacert}/etc/ssl/certs/ca-bundle.crt
      popd

      ln -s $out/lib/openjdk/bin $out/bin
      ln -s $jre/lib/openjdk/jre/bin $jre/bin
    ''; # */

    # FIXME: this is unnecessary once the multiple-outputs branch is merged.
    preFixup = ''
      prefix=$jre stripDirs "$stripDebugList" "''${stripDebugFlags:--S}"
      patchELF $jre
      propagatedNativeBuildInputs+=" $jre"

      # Propagate the setJavaClassPath setup hook from the JRE so that
      # any package that depends on the JRE has $CLASSPATH set up
      # properly.
      mkdir -p $jre/nix-support
      echo -n "${setJavaClassPath}" > $jre/nix-support/propagated-native-build-inputs

      # Set JAVA_HOME automatically.
      mkdir -p $out/nix-support
      cat <<EOF > $out/nix-support/setup-hook
      if [ -z "\$JAVA_HOME" ]; then export JAVA_HOME=$out/lib/openjdk; fi
      EOF
    '';

    meta = {
      homepage = http://openjdk.java.net/;
      license = stdenv.lib.licenses.gpl2;
      description = "The open-source Java Development Kit";
      maintainers = [ stdenv.lib.maintainers.eelco stdenv.lib.maintainers.shlevy ];
      platforms = stdenv.lib.platforms.linux;
    };

    passthru = {
      inherit architecture;
      home = "${openjdk}/lib/openjdk";
    };
  };
in openjdk
