{ stdenv, fetchurl, zlib, readline, openssl }:

let version = "9.0.20"; in

stdenv.mkDerivation rec {
  name = "postgresql-${version}";

  src = fetchurl {
    url = "mirror://postgresql/source/v${version}/${name}.tar.bz2";
    sha256 = "0vxa90d1ghv6vg4c6kxvm2skypahvlq4sd968q7l9ff3dl145z02";
  };

  buildInputs = [ zlib readline openssl ];

  LC_ALL = "C";

  configureFlags = [ "--with-openssl" ];

  patches = [ ./less-is-more.patch ];

  passthru = {
    inherit readline;
    psqlSchema = "9.0";
  };

  meta = with stdenv.lib; {
    homepage = http://www.postgresql.org/;
    description = "A powerful, open source object-relational database system";
    license = licenses.postgresql;
    maintainers = [ maintainers.ocharles ];
    platforms = platforms.unix;
    hydraPlatforms = platforms.linux;
  };
}
