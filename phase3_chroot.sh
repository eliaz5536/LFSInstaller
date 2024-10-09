#!/bin/bash

# ===========================================================================
# Chapter 7. Entering chroot and Building Additional Temporary Tools
# ===========================================================================
# 7.2. Changing Ownership
# To address this issue, change the ownership of the $LFS/& directories to user root by running the following command:
chown --from lfs -R root:root $LFS/{usr,lib,var,etc,bin,sbin,tools}
case $(uname -m) in
  x86_64) chown --from lfs -R root:root $LFS/lib64 ;;
esac

# 7.3. Preparing Virtual Kernel File Systems
# Create the directories on which these virtual file systems will be mounted:
mkdir -pv $LFS/{dev,proc,sys,run}

# 7.3.1. Mounting and Populating /dev
mount -v --bind /dev $LFS/dev

# 7.3.2. Mounting Virtual Kernel File Systems
# Mount the remaining virtual kernel file systems:
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run

# In some host systems, /dev/shm is a symbolic link to a directory, typically /run/shm. The /run tmpfs was mounted above so in this case only a directory needs to be created with the correct permissions.
# In other host systems /dev/shm is a mount point for a tmpfs. In that case the mount of /dev above will only create /dev/shm as a directory in the chroot environment. In this situatino we must explicitly mount a tmpfs:
if [ -h $LFS/dev/shm ]; then
  install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
  mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi

# 7.4. Entering the Chroot Environment
# The chroot environment will be used to install the final system and finish installing the temporary tools. As user root, run the following command to enter the environment that is, at the moment, populated with nothing but temporary tools:
chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin     \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash --login

# 7.5. Creating Directories
# Create some root-level directories thatre not in the limited set required in the previous chapters by issuing the following command:
mkdir -pv $LFS/{boot,home,mnt,opt,srv}

# Create the required set of subdirectories below the root-level by issuing the following commands:
mkdir -pv $LFS/etc/{opt,sysconfig}
mkdir -pv $LFS/lib/firmware
mkdir -pv $LFS/media/{floppy,cdrom}
mkdir -pv $LFS/usr/{,local/}{include,src}
mkdir -pv $LFS/usr/lib/locale
mkdir -pv $LFS/usr/local/{bin,lib,sbin}
mkdir -pv $LFS/usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv $LFS/usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv $LFS/usr/{,local/}share/man/man{1..8}
mkdir -pv $LFS/var/{cache,local,log,mail,opt,spool}
mkdir -pv $LFS/var/lib/{color,misc,locate}

ln -sfv $LFS/run $LFS/var/run
ln -sfv $LFS/run/lock $LFS/var/lock

install -dv -m 0750 $LFS/root
install -dv -m 1777 $LFS/tmp $LFS/var/tmp

# 7.6. Creating Essential Files and Symlinks
# Historically, Lonux maintained a list of the mounted file systems in the file /etc/mtab. Modern kernels maintain this list internally and expose it to the user via the /proc filesystem. To satisfy utilities that expect to find /etc/mtab, create the following symbolic link:
ln -sv $LFS/proc/self/mounts $LFS/etc/mtab

# Create a basic /etc/hosts file to be references in some test suites, and in one of the Perl's configuration files as well:
cat > $LFS/etc/hosts << EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF

# In order for user root to be able to login and for the name "root" to be recognized, there must be relevant entries in the /etc/passwd and /etc/group files. Create the /etc/passwd file by running the following command:
cat > $LFS/etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

# The actual password for root will be set later.
# Create the /etc/group file by running the following command: 
cat > $LFS/etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

# Some packages need a locale.
localedef -i C -f UTF-8 C.UTF-8

# Some tests in Chapter 8 need a regular user. We aadd this user here and delete this account at the end of that chapter.
echo "tester:x:101:101::/home/tester:/bin/bash" >> $LFS/etc/passwd
echo "tester:x:101:" >> $LFs/etc/group
install -o tester -d /home/tester

# To remove the "I have no name!" prompt, start a new shell. Since the /etc/passwd and /etc/group files have been created, user name and group name resolution will now work:
exec /usr/bin/bash --login

# The login, agetty and init programs (and others) use a number of log files to record information such as who was logged into the system and when. However, these programs will not wrie to the log files if they do not already exist. Initialize the log files and give them proper permissions:
touch $LFS/var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp $LFS/var/log/lastlog
chmod -v 664  $LFS/var/log/lastlog
chmod -v 600  $LFS/var/log/btmp

# The /var/log/wtmp file records all logins and logouts.
# The /var/log/lastlog file records when each user laast logged in.
# The /var/log/faillog file records failed login attempts.
# The /var/log/btmp file records the bad login attempts.

# 7.7. Gettext-0.22.5
cd /mnt/lfs/sources/gettext-0.22.5

./configure --disable-shared

make

cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} $LFS/usr/bin

# 7.8. Bison-3.8.2
cd /mnt/lfs/sources/bison-3.8.2

./configure --prefix=$LFS/usr \
            --docdir=$LFS/usr/share/doc/bison-3.8.2

make

make install

# 7.9. Perl-5.40.0
cd /mnt/lfs/sources/perl-5.40.0

sh Configure -des                                         \
             -D prefix=$LFS/usr                           \
             -D vendorprefix=$LFS/usr                     \
             -D useshrplib                                \
             -D privlib=$LFS/usr/lib/perl5/5.40/core_perl \
             -D archlib=$LFS/usr/lib/perl5/5.40/core_perl \
             -D sitelib=/usr/lib/perl5/5.40/site_perl     \
             -D sitearch=/usr/lib/perl5/5.40/site_perl    \
             -D vendorlib=/usr/lib/perl5/5.40/vendor_perl \
             -D vendorarch=/usr/lib/perl5/5.40/vendor_perl

make

make install

# 7.10. Python-3.12.5
cd /mnt/lfs/sources/Python-3.12.5

./configure --prefix=$LFS/usr   \
            --enable-shared \
            --without-ensurepip

make 

make install

# 7.11. Texinfo-7.1
cd /mnt/lfs/sources/texinfo-7.1

./configure --prefix=$LFS/usr

make 

make install

# 7.12. Util-linux-2.40.2
cd /mnt/lfs/sources/util-linux-2.40.2

mkdir -pv /var/lib/hwclock

./configure --libdir=$LFS/usr/lib     \
            --runstatedir=$LFS/run    \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-static      \
            --disable-liblastlog2 \
            --without-python      \
            ADJTIME_PATH=$LFS/var/lib/hwclock/adjtime \
            --docdir=$LFS/usr/share/doc/util-linux-2.40.2

make

make install

# 7.12. Cleaning up and Saving the Temporary System
# 7.13.1. Cleaning
# First, remove the currently installed documentation files to prevent them from ending up in the final system, and to save about 35 MB:
rm -rf $LFS/usr/share/{info,man,doc}/*

# Second, on a modern Linux system, the libtool .la file are only useful for libltdl. No libraries in LFS are loaded by libltdl, and it's known that some .la files can cause BLFS package failures. Remove those files now:
find $LFS/usr/{lib,libexec} -name \*.la -delete

# The current system size is now about 3 GB, however the /tools directory is no longer needed. It uses about 1 GB of disk space. Delete it now:
rm -rf $LFS/tools

# ===========================================================================
# Chapter 8. Installing Basic System Software
# ===========================================================================
# 8.3. Man-pages-6.9.1
cd /mnt/lfs/sources/man-pages-6.9.1
# Remove two man pages for password hashing functions. Libxcrypt will provide a better version of these man pages:
rm -v man3/crypt*
# Install Man-pages by running:
make prefix=$LFS/usr install

# 8.4. Iana-Etc-20240806
# For this package, we only need to copy the files into place:
cd /mnt/lfs/sources/iana-etc-20240806
cp services protocols $LFS/etc

# 8.5. Glibc-2.40
cd /mnt/lfs/sources/glibc-2.40

patch -Np1 -i ../glibc-2.40-fhs-1.patch

mkdir -v build
cd       build

echo "rootsbindir=$LFS/usr/sbin" > configparms

../configure --prefix=$LFS/usr                        \
             --disable-werror                         \
             --enable-kernel=4.19                     \
             --enable-stack-protector=strong          \
             --disable-nscd                           \
             libc_cv_slibdir=/usr/lib

make

make check

touch $LFS/etc/ld.so.conf

sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile

make install

sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

localedef -i C -f UTF-8 C.UTF-8
localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
localedef -i de_DE -f ISO-8859-1 de_DE
localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i el_GR -f ISO-8859-7 el_GR
localedef -i en_GB -f ISO-8859-1 en_GB
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i en_HK -f ISO-8859-1 en_HK
localedef -i en_PH -f ISO-8859-1 en_PH
localedef -i en_US -f ISO-8859-1 en_US
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i es_ES -f ISO-8859-15 es_ES@euro
localedef -i es_MX -f ISO-8859-1 es_MX
localedef -i fa_IR -f UTF-8 fa_IR
localedef -i fr_FR -f ISO-8859-1 fr_FR
localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
localedef -i is_IS -f ISO-8859-1 is_IS
localedef -i is_IS -f UTF-8 is_IS.UTF-8
localedef -i it_IT -f ISO-8859-1 it_IT
localedef -i it_IT -f ISO-8859-15 it_IT@euro
localedef -i it_IT -f UTF-8 it_IT.UTF-8
localedef -i ja_JP -f EUC-JP ja_JP
localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2> /dev/null || true
localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
localedef -i se_NO -f UTF-8 se_NO.UTF-8
localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
localedef -i zh_CN -f GB18030 zh_CN.GB18030
localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
localedef -i zh_TW -f UTF-8 zh_TW.UTF-8

# Install all the locales listed in the glic-2.40/localdata/SUPPORTED file (it includes every locale listaed above and many more) at once with the following time-consuming command:
make localedata/install-locales

# Use the localedef command to create and install locales not listedi n the glibc-2.40/localedata/SUPPROTED file when you need them. For instance, the following two locales are needed for some tests later in this chapter:
localedef -i C -f UTF-8 C.UTF-8
localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2> /dev/null || true

# 8.5.2. Configuring Glibc
# 8.5.2.1. Adding nsswitch.conf

# The /etc/nsswitch.conf file needs to becreated because the glibc defaults do not work well in a networked environment.
# Create a new file /etc/nsswitch.conf by running the following:
cat > $LFS/etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF

# 8.5.2.2. Adding Time Zone Data
# Install and set up the time zone data with the following:
tar -xf ../../tzdata2024a.tar.gz

ZONEINFO=$LFS/usr/share/zoneinfo
mkdir -pv $ZONEINFO/{posix,right}

for tz in etcetera southamerica northamerica europe africa antarctica  \
          asia australasia backward; do
    zic -L /dev/null   -d $ZONEINFO       ${tz}
    zic -L /dev/null   -d $ZONEINFO/posix ${tz}
    zic -L leapseconds -d $ZONEINFO/right ${tz}
done

cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
zic -d $ZONEINFO -p America/New_York
unset ZONEINFO

# run the following script to determine the local time zone
tzselect

# Create the /etc/localtime by running:
ln -sfv $LFS/usr/share/zoneinfo/Europe/London /etc/localtime

# 8.5.2.3. Configuring the Dynamic Loader
# Create a new file /etc/ld.conf by running the following:
cat > $LFS/etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF

# 8.6. Zlib-1.3.1
cd /mnt/lfs/sources/zlib-1.3.1

./configure --prefix=$LFS/usr

make

make check

make install

rm -fv $LFS/usr/lib/libz.a

# 8.7. Bzip2-1.0.8
cd /mnt/lfs/sources/bzip2-1.0.8

patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch

sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile

sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile

make -f Makefile-libbz2_so
make clean

make

make PREFIX=$LFS/usr install

cp -av libbz2.so.* $LFS/usr/lib
ln -sv libbz2.so.1.0.8 $LFS/usr/lib/libbz2.so

cp -v bzip2-shared $LFS/usr/bin/bzip2
for i in /usr/bin/{bzcat,bunzip2}; do
  ln -sfv bzip2 $i
done

rm -fv $LFS/usr/lib/libbz2.a

# 8.8. Xz-5.6.2.
cd /mnt/lfs/sources/xz-5.6.2

./configure --prefix=$LFS/usr    \
            --disable-static \
            --docdir=/usr/share/doc/xz-5.6.2

make

make check

make install

# 8.9. Lz4-1.10.0
cd /mnt/lfs/sources/lz4-1.10.0

make BUILD_STATIC=no PREFIX=$LFS/usr

make -j1 check

make BUILD_STATIC=no PREFIX=$LFS/usr install

# 8.10. Zstd-1.5.6
cd /mnt/lfs/sources/zstd-1.5.6

make prefix=$LFS/usr

make check

make prefix=$LFS/usr install

rm -v $LFS/usr/lib/libzstd.a

# 8.11. File-5.45
cd /mnt/lfs/sources/file-5.45

./configure --prefix=$LFS/usr

make

make check

make install

# 8.12. Readline-8.2.13
cd /mnt/lfs/sources/readline-8.2.13

sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install

sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf

./configure --prefix=$LFS/usr    \
            --disable-static \
            --with-curses    \
            --docdir=$LFS/usr/share/doc/readline-8.2.13

make SHLIB_LIBS="-lncursesw"

make SHLIB_LIBS="-lncursesw" install

install -v -m644 doc/*.{ps,pdf,html,dvi} $LFS/usr/share/doc/readline-8.2.13

# 8.13. M4-1.4.19
cd /mnt/lfs/sources/m4-1.4.19

./configure --prefix=$LFS/usr

make

make check

make install

# 8.14. Bc-6.7.6
cd /mnt/lfs/sources/bc-6.7.6

CC=gcc ./configure --prefix=$LFS/usr -G -O3 -r

make

make test

make install

# 8.15. Flex-2.6.4
cd /mnt/lfs/sources/flex-2.6.4

./configure --prefix=$LFS/usr \
            --docdir=$LFS/usr/share/doc/flex-2.6.4 \
            --disable-static

make

make check

make install

ln -sv flex   $LFS/usr/bin/lex
ln -sv flex.1 $LFS/usr/share/man/man1/lex.1

# 8.16. Tcl-8.6.14
cd /mnt/lfs/sources/tcl8.6.14-src

SRCDIR=$(pwd)
cd unix
./configure --prefix=$LFS/usr           \
            --mandir=$LFS/usr/share/man \
            --disable-rpath

make

sed -e "s|$SRCDIR/unix|/usr/lib|" \
    -e "s|$SRCDIR|/usr/include|"  \
    -i tclConfig.sh

sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.7|/usr/lib/tdbc1.1.7|" \
    -e "s|$SRCDIR/pkgs/tdbc1.1.7/generic|/usr/include|"    \
    -e "s|$SRCDIR/pkgs/tdbc1.1.7/library|/usr/lib/tcl8.6|" \
    -e "s|$SRCDIR/pkgs/tdbc1.1.7|/usr/include|"            \
    -i pkgs/tdbc1.1.7/tdbcConfig.sh

sed -e "s|$SRCDIR/unix/pkgs/itcl4.2.4|/usr/lib/itcl4.2.4|" \
    -e "s|$SRCDIR/pkgs/itcl4.2.4/generic|/usr/include|"    \
    -e "s|$SRCDIR/pkgs/itcl4.2.4|/usr/include|"            \
    -i pkgs/itcl4.2.4/itclConfig.sh

unset SRCDIR

make test

make install

chmod -v u+w $LFS/usr/lib/libtcl8.6.so

make install-private-headers

ln -sfv tclsh8.6 $LFS/usr/bin/tclsh

mv $LFS/usr/share/man/man3/{Thread,Tcl_Thread}.3

cd ..
tar -xf ../tcl8.6.14-html.tar.gz --strip-components=1
mkdir -v -p $LFS/usr/share/doc/tcl-8.6.14
cp -v -r  ./html/* $LFS/usr/share/doc/tcl-8.6.14

# 8.17. Expect-5.45.4
cd /mnt/lfs/sources/expect5.45.4

python3 -c 'from pty import spawn; spawn(["echo", "ok"])'

patch -Np1 -i ../expect-5.45.4-gcc14-1.patch

./configure --prefix=$LFS/usr           \
            --with-tcl=$LFS/usr/lib     \
            --enable-shared         \
            --disable-rpath         \
            --mandir=$LFS/usr/share/man \
            --with-tclinclude=$LFS/usr/include

make

make test

make install
ln -svf expect5.45.4/libexpect5.45.4.so $LFS/usr/lib

# 8.18. DejaGNU-1.6.3
cd /mnt/lfs/sources/dejagnu-1.6.3

mkdir -v build
cd       build

../configure --prefix=$LFS/usr
makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi

make check

make install
install -v -dm755  $LFS/usr/share/doc/dejagnu-1.6.3
install -v -m644   doc/dejagnu.{html,txt} $LFS/usr/share/doc/dejagnu-1.6.3

# 8.19. Pkgconf-2.3.0
cd /mnt/lfs/sources/pkgconf-2.3.0

./configure --prefix=$LFS/usr              \
            --disable-static           \
            --docdir=$LFS/usr/share/doc/pkgconf-2.3.0

make

make install

ln -sv pkgconf   $LFS/usr/bin/pkg-config
ln -sv pkgconf.1 $LFS/usr/share/man/man1/pkg-config.1

# 8.20. Binutils-2.43.1
cd /mnt/lfs/sources/binutils-2.43.1

mkdir -v build
cd       build

../configure --prefix=$LFS/usr       \
             --sysconfdir=$LFS/etc   \
             --enable-gold       \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --enable-new-dtags  \
             --with-system-zlib  \
             --enable-default-hash-style=gnu

make tooldir=$LFS/usr

make -k check

grep '^FAIL:' $(find -name '*.log')

make tooldir=$LFS/usr install

rm -fv $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a

# 8.21. GMP-6.30
cd /mnt/lfs/sources/gmp-6.3.0

./configure --prefix=$LFS/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=$LFS/usr/share/doc/gmp-6.3.0

make
make html

make check 2>&1 | tee gmp-check-log

awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log

make install
make install-html

# 8.22. MPFR-4.2.1
cd /mnt/lfs/sources/mpfr-4.2.1

./configure --prefix=$LFS/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=$LFS/usr/share/doc/mpfr-4.2.1

make
make html

make check

make install
make install-html

# 8.23. MPC-1.3.1
cd /mnt/lfs/sources/mpc-1.3.1

./configure --prefix=$LFS/usr    \
            --disable-static \
            --docdir=$LFS/usr/share/doc/mpc-1.3.1

make
make html

make check

make install
make install-html

# 8.24. Attr-2.5.2
cd /mnt/lfs/sources/attr-2.5.2

./configure --prefix=$LFS/usr     \
            --disable-static  \
            --sysconfdir=$LFS/etc \
            --docdir=$LFS/usr/share/doc/attr-2.5.2

make

make check

make install

# 8.25. Acl-2.3.2
cd /mnt/lfs/sources/acl-2.3.2

./configure --prefix=$LFS/usr         \
            --disable-static      \
            --docdir=$LFS/usr/share/doc/acl-2.3.2

make

make install

# 8.26. Libcap-2.70
cd /mnt/lfs/sources/libcap-2.70

sed -i '/install -m.*STA/d' libcap/Makefile

make prefix=$LFS/usr lib=lib

make test

make prefix=$LFS/usr lib=lib install

# 8.27. Libxcrypt-4.4.36
cd /mnt/lfs/sources/libxcrypt-4.4.36

./configure --prefix=$LFS/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=no     \
            --disable-static             \
            --disable-failure-tokens

make

make check

make install

# 8.28. Shadow-4.16.0
cd /mnt/lfs/sources/shadow-4.16.0

sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;

sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
    -i etc/login.defs

touch $LFS/usr/bin/passwd
./configure --sysconfdir=$LFS/etc   \
            --disable-static    \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --with-group-name-max-length=32

make

make exec_prefix=$LFS/usr install
make -C man install-man

# 8.28.2. Configuring Shadow
# To enable shadowed passwords, run the following command:
pwconv

# To enable shadowed group passwords, run:
grpconv

# 8.28.3. Setting the Root Password
# passwd root

# 8.29. GCC-14.2.0
cd /mnt/lfs/sources/gcc-14.2.0

case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac

mkdir -v build
cd       build

../configure --prefix=$LFS/usr            \
             LD=ld                    \
             --enable-languages=c,c++ \
             --enable-default-pie     \
             --enable-default-ssp     \
             --enable-host-pie        \
             --disable-multilib       \
             --disable-bootstrap      \
             --disable-fixincludes    \
             --with-system-zlib

make

ulimit -s -H unlimited

sed -e '/cpython/d'               -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp
sed -e 's/no-pic /&-no-pie /'     -i ../gcc/testsuite/gcc.target/i386/pr113689-1.c
sed -e 's/300000/(1|300000)/'     -i ../libgomp/testsuite/libgomp.c-c++-common/pr109062.c
sed -e 's/{ target nonpic } //' \
    -e '/GOTPCREL/d'              -i ../gcc/testsuite/gcc.target/i386/fentryname3.c

chown -R tester .
su tester -c "PATH=$PATH make -k check"

../contrib/test_summary

make install

chown -v -R root:root \
    $LFS/usr/lib/gcc/$(gcc -dumpmachine)/14.2.0/include{,-fixed}

ln -svr $LFS/usr/bin/cpp /usr/lib

ln -sv gcc.1 $LFS/usr/share/man/man1/cc.1

ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/14.2.0/liblto_plugin.so \
        $LFS/usr/lib/bfd-plugins/

echo 'int main(){}' > dummy.c
cc dummy.c -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'

#grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log
grep -E -o '/mnt/lfs/usr/lib.*/S?crt[1in].*succeeded' dummy.log

#grep -B4 '^ /usr/include' dummy.log
grep -B4 '^ /mnt/lfs/usr/include' dummy.log

#grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
grep '/mnt/lfs/SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'

grep "/lib.*/libc.so.6 " dummy.log

grep found dummy.log

rm -v dummy.c a.out dummy.log

mkdir -pv $LFS/usr/share/gdb/auto-load/usr/lib
#mv -v $LFS/usr/lib/*gdb.py $LFS/usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py $LFS/usr/share/gdb/auto-load/usr/lib

# 8.30. Ncurses-6.5
cd /mnt/lfs/sources/ncurses-6.5

./configure --prefix=$LFS/usr           \
            --mandir=$LFS/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --with-cxx-shared       \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig

make

make DESTDIR=$PWD/dest install
install -vm755 dest/usr/lib/libncursesw.so.6.5 $LFS/usr/lib
rm -v  dest/usr/lib/libncursesw.so.6.5
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i dest/usr/include/curses.h
cp -av dest/* /

for lib in ncurses form panel menu ; do
    ln -sfv lib${lib}w.so $LFS/usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc    $LFS/usr/lib/pkgconfig/${lib}.pc
done

ln -sfv libncursesw.so $LFS/usr/lib/libcurses.so

cp -v -R doc -T $LFS/usr/share/doc/ncurses-6.5

# 8.31. Sed-4.9
cd /mnt/lfs/sources/sed-4.9

./configure --prefix=$LFS/usr

make
make html

chown -R tester .
su tester -c "PATH=$PATH make check"

make install
install -d -m755           $LFS/usr/share/doc/sed-4.9
install -m644 doc/sed.html $LFS/usr/share/doc/sed-4.9

# 8.32. Psmisc-23.7
cd /mnt/lfs/sources/psmisc-23.7

./configure --prefix=$LFS/usr

make

make check

make install

# 8.33. Gettext-0.22.5
cd /mnt/lfs/sources/gettext-0.22.5

./configure --prefix=$LFS/usr    \
            --disable-static \
            --docdir=$LFS/usr/share/doc/gettext-0.22.5

make

make check

make install
chmod -v 0755 $LFS/usr/lib/preloadable_libintl.so

# 8.34. Bison-3.8.2
cd /mnt/lfs/sources/bison-3.8.2

./configure --prefix=$LFS/usr --docdir=$LFS/usr/share/doc/bison-3.8.2

make

make check

make install

# 8.35. Grep-3.11
cd /mnt/lfs/sources/grep-3.11

sed -i "s/echo/#echo/" src/egrep.sh

./configure --prefix=$LFS/usr

make

make check

make install

# 8.36. Bash-5.2.32
cd /mnt/lfs/sources/bash-5.2.32

./configure --prefix=$LFS/usr             \
            --without-bash-malloc     \
            --with-installed-readline \
            bash_cv_strtold_broken=no \
            --docdir=$LFS/usr/share/doc/bash-5.2.32

make

chown -R tester .

su -s /usr/bin/expect tester << "EOF"
set timeout -1
spawn make tests
expect eof
lassign [wait] _ _ _ value
exit $value
EOF

make install

exec $LFS/usr/bin/bash --login

# 8.37. Libtool-2.4.7
cd /mnt/lfs/sources/libtool-2.4.7

./configure --prefix=$LFS/usr

make

make -k check

make install

rm -fv $LFS/usr/lib/libltdl.a

# 8.38. GDBM-1.24
cd /mnt/lfs/sources/gdbm-1.24

./configure --prefix=$LFS/usr    \
            --disable-static \
            --enable-libgdbm-compat

make

make check

make install

# 8.39. Gperf-3.1
cd /mnt/lfs/sources/gperf-3.1

./configure --prefix=$LFS/usr --docdir=$LFS/usr/share/doc/gperf-3.1

make

make -j1 check

make install

# 8.40. Expat-2.6.2
cd /mnt/lfs/sources/expat-2.6.2

./configure --prefix=$LFS/usr    \
            --disable-static \
            --docdir=$LFS/usr/share/doc/expat-2.6.2

make

make check

make install

install -v -m644 doc/*.{html,css} $LFS/usr/share/doc/expat-2.6.2

# 8.41. Inetutils-2.5
cd /mnt/lfs/sources/inetutils-2.5

sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c

./configure --prefix=$LFS/usr        \
            --bindir=$LFS/usr/bin    \
            --localstatedir=$LFS/var \
            --disable-logger     \
            --disable-whois      \
            --disable-rcp        \
            --disable-rexec      \
            --disable-rlogin     \
            --disable-rsh        \
            --disable-servers

make

make check

make install

mv -v $LFS/usr/{,s}bin/ifconfig

# 8.42. Less-661
cd /mnt/lfs/sources/less-661

./configure --prefix=$LFS/usr --sysconfdir=$LFS/etc

make

make check

make install

# 8.43. Perl-5.40.0
cd /mnt/lfs/sources/perl-5.40.0

export BUILD_ZLIB=False
export BUILD_BZIP2=0

sh Configure -des                                          \
             -D prefix=$LFS/usr                                \
             -D vendorprefix=$LFS/usr                          \
             -D privlib=$LFS/usr/lib/perl5/5.40/core_perl      \
             -D archlib=$LFS/usr/lib/perl5/5.40/core_perl      \
             -D sitelib=$LFS/usr/lib/perl5/5.40/site_perl      \
             -D sitearch=$LFS/usr/lib/perl5/5.40/site_perl     \
             -D vendorlib=$LFS/usr/lib/perl5/5.40/vendor_perl  \
             -D vendorarch=$LFS/usr/lib/perl5/5.40/vendor_perl \
             -D man1dir=$LFS/usr/share/man/man1                \
             -D man3dir=$LFS/usr/share/man/man3                \
             -D pager="$LFS/usr/bin/less -isR"                 \
             -D useshrplib                                 \
             -D usethreads

make

TEST_JOBS=$(nproc) make test_harness

make install
unset BUILD_ZLIB BUILD_BZIP2

# 8.44. XML::Parser-2.47
cd /mnt/lfs/sources/XML-Parser-2.47

perl Makefile.PL

make

make test

make install

# 8.45. Intltool-0.51.0
cd /mnt/lfs/sources/intltool-0.51.0

sed -i 's:\\\${:\\\$\\{:' intltool-update.in

./configure --prefix=$LFS/usr

make

make check

make install
install -v -Dm644 doc/I18N-HOWTO $LFS/usr/share/doc/intltool-0.51.0/I18N-HOWTO

# 8.46. Autoconf-2.72
cd /mnt/lfs/sources/autoconf-2.72

./configure --prefix=$LFS/usr

make

make check

make install

# 8.47. Automake-1.17
cd /mnt/lfs/sources/automake-1.17

./configure --prefix=$LFS/usr --docdir=$LFS/usr/share/doc/automake-1.17

make

make -j$(($(nproc)>4?$(nproc):4)) check

make install

# 8.48. OpenSSL-3.3.1
cd /mnt/lfs/sources/openssl-3.3.1

./config --prefix=$LFS/usr         \
         --openssldir=$LFS/etc/ssl \
         --libdir=lib          \
         shared                \
         zlib-dynamic

make

HARNESS_JOBS=$(nproc) make test

sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
make MANSUFFIX=ssl install

mv -v $LFS/usr/share/doc/openssl $LFS/usr/share/doc/openssl-3.3.1

cp -vfr doc/* $LFS/usr/share/doc/openssl-3.3.1

# 8.49. Kmod-33
cd /mnt/lfs/sources/kmod-33

./configure --prefix=$LFS/usr     \
            --sysconfdir=$LFS/etc \
            --with-openssl    \
            --with-xz         \
            --with-zstd       \
            --with-zlib       \
            --disable-manpages

make

make install

for target in depmod insmod modinfo modprobe rmmod; do
  ln -sfv ../bin/kmod $LFS/usr/sbin/$target
  rm -fv $LFS/usr/bin/$target
done

# 8.50. Libelf from Elfutils-0.191
cd /mnt/lfs/sources/elfutils-0.191

./configure --prefix=$LFS/usr                \
            --disable-debuginfod         \
            --enable-libdebuginfod=dummy

make

make check

make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
rm /usr/lib/libelf.a

# 8.51. Libffi-3.4.6
cd /mnt/lfs/sources/libffi-3.4.6

./configure --prefix=$LFS/usr          \
            --disable-static       \
            --with-gcc-arch=native

make

make check

make install

# 8.52. Python-3.12.5
cd /mnt/lfs/sources/Python-3.12.5

./configure --prefix=$LFS/usr        \
            --enable-shared      \
            --with-system-expat  \
            --enable-optimizations

make

make test TESTOPTS="--timeout 120"

make install

cat > $LFS/etc/pip.conf << EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF

install -v -dm755 $LFS/usr/share/doc/python-3.12.5/html

tar --no-same-owner \
    -xvf ../python-3.12.5-docs-html.tar.bz2
cp -R --no-preserve=mode python-3.12.5-docs-html/* \
    $LFS/usr/share/doc/python-3.12.5/html

# 8.53. Flit-Core-3.9.0
cd /mnt/lfs/sources/flit_core-3.9.0

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

pip3 install --no-index --no-user --find-links dist flit_core

# 8.54. Wheel-0.44.0
cd /mnt/lfs/sources/wheel-0.44.0

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

pip3 install --no-index --find-links=dist wheel

# 8.55. Setuptools-72.2.0
cd /mnt/lfs/sources/setuptools-72.2.0

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

pip3 install --no-index --find-links dist setuptools

# 8.56. Ninja-1.12.1
cd /mnt/lfs/sources/ninja-1.12.1

export NINJAJOBS=4

sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc

python3 configure.py --bootstrap

install -vm755 ninja /usr/bin/
install -vDm644 misc/bash-completion $LFS/usr/share/bash-completion/completions/ninja
install -vDm644 misc/zsh-completion  $LFS/usr/share/zsh/site-functions/_ninja

# 8.57. Meson-1.5.1
cd /mnt/lfs/sources/meson-1.5.1

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

pip3 install --no-index --find-links dist meson
install -vDm644 data/shell-completions/bash/meson $LFS/usr/share/bash-completion/completions/meson
install -vDm644 data/shell-completions/zsh/_meson $LFS/usr/share/zsh/site-functions/_meson

# 8.58. Coreutils-9.5
cd /mnt/lfs/sources/coreutils-9.5

patch -Np1 -i ../coreutils-9.5-i18n-2.patch

autoreconf -fiv
FORCE_UNSAFE_CONFIGURE=1 ./configure \
            --prefix=$LFS/usr            \
            --enable-no-install-program=kill,uptime

make

make NON_ROOT_USERNAME=tester check-root

groupadd -g 102 dummy -U tester

chown -R tester . 

su tester -c "PATH=$PATH make -k RUN_EXPENSIVE_TESTS=yes check" \
   < /dev/null

groupdel dummy

make install

mv -v $LFS/usr/bin/chroot $LFS/usr/sbin
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' $LFS/usr/share/man/man8/chroot.8

# 8.59. Check-0.15.2
cd /mnt/lfs/sources/check-0.15.2

./configure --prefix=$LFS/usr --disable-static

make

make check

make docdir=$LFS/usr/share/doc/check-0.15.2 install

# 8.60. Diffutils-3.10
cd /mnt/lfs/sources/diffutils-3.10

./configure --prefix=$LFS/usr

make

make check

make install

# 8.61. Gawk-5.3.0
cd /mnt/lfs/sources/gawk-5.3.0

sed -i 's/extras//' Makefile.in

./configure --prefix=$LFS/usr

make

chown -R tester .
su tester -c "PATH=$PATH make check"

rm -f $LFS/usr/bin/gawk-5.3.0
make install

ln -sv gawk.1 $LFS/usr/share/man/man1/awk.1

mkdir -pv                                   $LFS/usr/share/doc/gawk-5.3.0
cp    -v doc/{awkforai.txt,*.{eps,pdf,jpg}} $LFS/usr/share/doc/gawk-5.3.0

# 8.62. Findutils-4.10.0
cd /mnt/lfs/sources/findutils-4.10.0

./configure --prefix=$LFS/usr --localstatedir=$LFS/var/lib/locate

make

chown -R tester .
su tester -c "PATH=$PATH make check"

make install

# 8.63. Groff-1.23.0
cd /mnt/lfs/sources/groff-1.23.0

PAGE="A4" ./configure --prefix=$LFS/usr

make

make check

make install

# 8.64. GRUB-2.12
cd /mnt/lfs/sources/grub-2.12

unset {C,CPP,CXX,LD}FLAGS

echo depends bli part_gpt > grub-core/extra_deps.lst

./configure --prefix=$LFS/usr          \
            --sysconfdir=$LFS/etc      \
            --disable-efiemu       \
            --disable-werror

make

make install
mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions

# 8.65. Gzip-1.13
cd /mnt/lfs/sources/gzip-1.13

./configure --prefix=$LFS/usr

make

make check

make install

# 8.66. IPRoute2-6.10.0
cd /mnt/lfs/sources/iproute2-6.10.0

sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8

make NETNS_RUN_DIR=$LFS/run/netns

make SBINDIR=$LFS/usr/sbin install

mkdir -pv             $LFS/usr/share/doc/iproute2-6.10.0
cp -v COPYING README* $LFS/usr/share/doc/iproute2-6.10.0

# 8.67. Kbd-2.6.4
cd /mnt/lfs/sources/kbd-2.6.4

patch -Np1 -i ../kbd-2.6.4-backspace-1.patch

sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in

./configure --prefix=$LFS/usr --disable-vlock

make

make check

make install

cp -R -v docs/doc -T $LFS/usr/share/doc/kbd-2.6.4

# 8.68. Libpipeline-1.5.7
cd /mnt/lfs/sources/libpipeline-1.5.7

./configure --prefix=$LFS/usr

make

make check

make install

# 8.69. Make-4.4.1
cd /mnt/lfs/sources/make-4.4.1

./configure --prefix=$LFS/usr

make

chown -R tester .
su tester -c "PATH=$PATH make check"

make install

# 8.70. Patch-2.7.6
cd /mnt/lfs/sources/patch-2.7.6

./configure --prefix=$LFS/usr

make

make check

make install

# 8.71. Tar-1.35
cd /mnt/lfs/sources/tar-1.35

FORCE_UNSAFE_CONFIGURE=1  \
./configure --prefix=$LFS/usr

make

make check

make install
make -C doc install-html docdir=/usr/share/doc/tar-1.35

# 8.72. Texinfo-7.1
cd /mnt/lfs/sources/texinfo-7.1

./configure --prefix=$LFS/usr

make

make check

make install

make TEXMF=$LFS/usr/share/texmf install-tex

pushd $LFS/usr/share/info
  rm -v dir
  for f in *
    do install-info $f dir 2>/dev/null
  done
popd

# 8.73. Vim-9.1.0660
cd /mnt/lfs/sources/vim-9.1.0660

echo '#define SYS_VIMRC_FILE "$LFS/etc/vimrc"' >> src/feature.h

./configure --prefix=$LFS/usr

make

chown -R tester .

su tester -c "TERM=xterm-256color LANG=en_US.UTF-8 make -j1 test" \
   &> vim-test.log

make install

ln -sv vim $LFS/usr/bin/vi
for L in  $LFS/usr/share/man/{,*/}man1/vim.1; do
    ln -sv vim.1 $(dirname $L)/vi.1
done

ln -sv ../vim/vim91/doc $LFS/usr/share/doc/vim-9.1.0660

cat > $LFS/etc/vimrc << "EOF"
" Begin /etc/vimrc

" Ensure defaults are set before customizing settings, not after
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF

# 8.74. MarkupSafe-2.1.5
cd /mnt/lfs/sources/MarkupSafe-2.1.5

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

pip3 install --no-index --no-user --find-links dist Markupsafe

# 8.75. Jinja2-3.1.4
cd /mnt/lfs/sources/jinja2-3.1.4

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD

pip3 install --no-index --no-user --find-links dist Jinja2

# 8.76. Udev from Systemd-256.4
cd /mnt/lfs/sources/systemd-256.4

sed -i -e 's/GROUP="render"/GROUP="video"/' \
       -e 's/GROUP="sgx", //' rules.d/50-udev-default.rules.in

sed '/systemd-sysctl/s/^/#/' -i rules.d/99-systemd.rules.in

sed '/NETWORK_DIRS/s/systemd/udev/' -i src/basic/path-lookup.h

mkdir -p build
cd       build

meson setup ..                  \
      --prefix=$LFS/usr         \
      --buildtype=release       \
      -D mode=release           \
      -D dev-kvm-mode=0660      \
      -D link-udev-shared=false \
      -D logind=false           \
      -D vconsole=false

export udev_helpers=$(grep "'name' :" ../src/udev/meson.build | \
                      awk '{print $3}' | tr -d ",'" | grep -v 'udevadm')

ninja udevadm systemd-hwdb                                           \
      $(ninja -n | grep -Eo '(src/(lib)?udev|rules.d|hwdb.d)/[^ ]*') \
      $(realpath libudev.so --relative-to .)                         \
      $udev_helpers

install -vm755 -d {$LFS/usr/lib,$LFS/etc}/udev/{hwdb.d,rules.d,network}
install -vm755 -d $LFS/usr/{lib,share}/pkgconfig
install -vm755 udevadm                             $LFS/usr/bin/
install -vm755 systemd-hwdb                        $LFS/usr/bin/udev-hwdb
ln      -svfn  ../bin/udevadm                      $LFS/usr/sbin/udevd
cp      -av    libudev.so{,*[0-9]}                 $LFS/usr/lib/
install -vm644 ../src/libudev/libudev.h            $LFS/usr/include/
install -vm644 src/libudev/*.pc                    $LFS/usr/lib/pkgconfig/
install -vm644 src/udev/*.pc                       $LFS/usr/share/pkgconfig/
install -vm644 ../src/udev/udev.conf               $LFS/etc/udev/
install -vm644 rules.d/* ../rules.d/README         $LFS/usr/lib/udev/rules.d/
install -vm644 $(find ../rules.d/*.rules \
                      -not -name '*power-switch*') $LFS/usr/lib/udev/rules.d/
install -vm644 hwdb.d/*  ../hwdb.d/{*.hwdb,README} $LFS/usr/lib/udev/hwdb.d/
install -vm755 $udev_helpers                       $LFS/usr/lib/udev
install -vm644 ../network/99-default.link          $LFS/usr/lib/udev/network

tar -xvf ../../udev-lfs-20230818.tar.xz
make -f udev-lfs-20230818/Makefile.lfs install

tar -xf ../../systemd-man-pages-256.4.tar.xz                            \
    --no-same-owner --strip-components=1                              \
    -C /usr/share/man --wildcards '*/udev*' '*/libudev*'              \
                                  '*/systemd.link.5'                  \
                                  '*/systemd-'{hwdb,udevd.service}.8

sed 's|systemd/network|udev/network|'                                 \
    $LFS/usr/share/man/man5/systemd.link.5                                \
  > $LFS/usr/share/man/man5/udev.link.5

sed 's/systemd\(\\\?-\)/udev\1/' $LFS/usr/share/man/man8/systemd-hwdb.8   \
                               > $LFS/usr/share/man/man8/udev-hwdb.8

sed 's|lib.*udevd|sbin/udevd|'                                        \
    $LFS/usr/share/man/man8/systemd-udevd.service.8                       \
  > $LFSS/usr/share/man/man8/udevd.8

rm $LFS/usr/share/man/man*/systemd*

unset udev_helpers

udev-hwdb update

# 8.77. Man-DB-2.12.1
cd /mnt/lfs/sources/man-db-2.12.1

./configure --prefix=$LFS/usr                         \
            --docdir=$LFS/usr/share/doc/man-db-2.12.1 \
            --sysconfdir=$LFS/etc                     \
            --disable-setuid                      \
            --enable-cache-owner=bin              \
            --with-browser=$LFS/usr/bin/lynx          \
            --with-vgrind=$LFS/usr/bin/vgrind         \
            --with-grap=$LFS/usr/bin/grap             \
            --with-systemdtmpfilesdir=            \
            --with-systemdsystemunitdir=

make

make check

make install

# 8.78. Procps-ng-4.0.4
cd /mnt/lfs/sources/procps-ng-4.0.4

./configure --prefix=$LFS/usr                           \
            --docdir=$LFS/usr/share/doc/procps-ng-4.0.4 \
            --disable-static                        \
            --disable-kill

make

chown -R tester .
su tester -c "PATH=$PATH make check"

make install

# 8.79. Util-linux-2.40.2
cd /mnt/lfs/sources/util-linux-2.40.2

./configure --bindir=$LFS/usr/bin     \
            --libdir=$LFS/usr/lib     \
            --runstatedir=$LFS/run    \
            --sbindir=$LFS/usr/sbin   \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-liblastlog2 \
            --disable-static      \
            --without-python      \
            --without-systemd     \
            --without-systemdsystemunitdir        \
            ADJTIME_PATH=$LFS/var/lib/hwclock/adjtime \
            --docdir=$LFS/usr/share/doc/util-linux-2.40.2

make 

bash tests/run.sh --srcdir=$PWD --builddir=$PWD

touch $LFS/etc/fstab
chown -R tester .
su tester -c "make -k check"

make install

# 8.80. E2fsprogs-1.47.1
cd /mnt/lfs/sources/e2fsprogs-1.47.1

mkdir -v build
cd       build

../configure --prefix=$LFS/usr           \
             --sysconfdir=$LFS/etc       \
             --enable-elf-shlibs     \
             --disable-libblkid      \
             --disable-libuuid       \
             --disable-uuidd         \
             --disable-fsck

make

make check

make install

rm -fv $LFS/usr/lib/{libcom_err,libe2p,libext2fs,libss}.a

gunzip -v $LFS/usr/share/info/libext2fs.info.gz
install-info --dir-file=$LFS/usr/share/info/dir $LFS/usr/share/info/libext2fs.info

makeinfo -o      doc/com_err.info ../lib/et/com_err.texinfo
install -v -m644 doc/com_err.info $LFS/usr/share/info
install-info --dir-file=$LFS/usr/share/info/dir $LFS/usr/share/info/com_err.info

sed 's/metadata_csum_seed,//' -i $LFS/etc/mke2fs.conf

# 8.81. Sysklogd-2.6.1
cd /mnt/lfs/sources/sysklogd-2.6.1

./configure --prefix=$LFS/usr      \
            --sysconfdir=$LFS/etc  \
            --runstatedir=$LFS/run \
            --without-logger

make

make install

cat > $LFS/etc/syslog.conf << "EOF"
# Begin /etc/syslog.conf

auth,authpriv.* -/mnt/lfs/var/log/auth.log
*.*;auth,authpriv.none -/mnt/lfs/var/log/sys.log
daemon.* -/mnt/lfs/var/log/daemon.log
kern.* -/mnt/lfs/var/log/kern.log
mail.* -/mnt/lfs/var/log/mail.log
user.* -/mnt/lfs/var/log/user.log
*.emerg *

# Do not open any internet ports.
secure_mode 2

# End /etc/syslog.conf
EOF

# 8.82. SysVinit-3.10
cd /mnt/lfs/sources/sysvinit-3.10

patch -Np1 -i ../sysvinit-3.10-consolidated-1.patch

make

make install

# 8.85. Cleaning Up
rm -rf $LFS/tmp/{*,.*}
find $LFS/usr/lib $LFS/usr/libexec -name \*.la -delete
find $LFS/usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf
userdel -r tester

# ===========================================================================
# Chapter 9. System Configuration
# ===========================================================================
# 9.2. LFS-Bootscripts-20240825
cd /mnt/lfs/sources/lfs-bootscripts-20240825

make install

# 9.5.1. Creating Network Interface Configuration Files
# The following command creates a sample file for the eth0 device with a static IP address:
cd $LFS/etc/sysconfig/
cat > ifconfig.eth0 << "EOF"
ONBOOT=yes
IFACE=eth0
SERVICE=ipv4-static
IP=192.168.1.2
GATEWAY=192.168.1.1
PREFIX=24
BROADCAST=192.168.1.255
EOF

# 9.5.2. Creating the /etc/resolv.conf File
cat > $LFS/etc/resolv.conf << "EOF"
# Begin /etc/resolv.conf

# End /etc/resolv.conf
EOF

# 9.5.3. Configuring the System Hostname
# Create the /etc/hostname file and enter a hostname by running:
# Prompt hostname here
echo "lfs" > $LFS/etc/hostname

# 9.5.4. Customizing the /etc/hosts File
# Prompt localdomains over here
cat > $LFS/etc/hosts << "EOF"
# Begin /etc/hosts

127.0.0.1 localhost.localdomain localhost
127.0.1.1 localhost.localdomain localhost
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters

# End /etc/hosts
EOF

# 9.6 System V Bootscript Usage and Configuration
# 9.6.2. Configuring SysVinit
cat > $LFS/etc/inittab << "EOF"
# Begin /etc/inittab

id:3:initdefault:

si::sysinit:/etc/rc.d/init.d/rc S

l0:0:wait:/etc/rc.d/init.d/rc 0
l1:S1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6

ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now

su:S06:once:/sbin/sulogin
s1:1:respawn:/sbin/sulogin

1:2345:respawn:/sbin/agetty --noclear tty1 9600
2:2345:respawn:/sbin/agetty tty2 9600
3:2345:respawn:/sbin/agetty tty3 9600
4:2345:respawn:/sbin/agetty tty4 9600
5:2345:respawn:/sbin/agetty tty5 9600
6:2345:respawn:/sbin/agetty tty6 9600

# End /etc/inittab
EOF

# 9.6.4. Configuring the System Clock
cat > $LFS/etc/sysconfig/clock << "EOF"
# Begin /etc/sysconfig/clock

UTC=1

# Set this to any options you might need to give to hwclock,
# such as machine hardware clock type for Alphas.
CLOCKPARAMS=

# End /etc/sysconfig/clock
EOF

# 9.6.5. Configuring the Linux Console
cat > $LFS/etc/sysconfig/console << "EOF"
# Begin /etc/sysconfig/console

UNICODE="1"
FONT="Lat2-Terminus16"

# End /etc/sysconfig/console
EOF

# 9.6.8. The rc-site File
# rc.site
# Optional parameters for boot scripts.

# Distro Information
# These values, if specified here, override the defaults
#DISTRO="Linux From Scratch" # The distro name
#DISTRO_CONTACT="lfs-dev@lists.linuxfromscratch.org" # Bug report address
#DISTRO_MINI="LFS" # Short name used in filenames for distro config

# Define custom colors used in messages printed to the screen

# Please consult `man console_codes` for more information
# under the "ECMA-48 Set Graphics Rendition" section
#
# Warning: when switching from a 8bit to a 9bit font,
# the linux console will reinterpret the bold (1;) to
# the top 256 glyphs of the 9bit font.  This does
# not affect framebuffer consoles

# These values, if specified here, override the defaults
#BRACKET="\\033[1;34m" # Blue
#FAILURE="\\033[1;31m" # Red
#INFO="\\033[1;36m"    # Cyan
#NORMAL="\\033[0;39m"  # Grey
#SUCCESS="\\033[1;32m" # Green
#WARNING="\\033[1;33m" # Yellow

# Use a colored prefix
# These values, if specified here, override the defaults
#BMPREFIX="      "
#SUCCESS_PREFIX="${SUCCESS}  *  ${NORMAL} "
#FAILURE_PREFIX="${FAILURE}*****${NORMAL} "
#WARNING_PREFIX="${WARNING} *** ${NORMAL} "

# Manually set the right edge of message output (characters)
# Useful when resetting console font during boot to override
# automatic screen width detection
#COLUMNS=120

# Interactive startup
#IPROMPT="yes" # Whether to display the interactive boot prompt
#itime="3"    # The amount of time (in seconds) to display the prompt

# The total length of the distro welcome string, without escape codes
#wlen=$(echo "Welcome to ${DISTRO}" | wc -c )
#welcome_message="Welcome to ${INFO}${DISTRO}${NORMAL}"

# The total length of the interactive string, without escape codes
#ilen=$(echo "Press 'I' to enter interactive startup" | wc -c )
#i_message="Press '${FAILURE}I${NORMAL}' to enter interactive startup"

# Set scripts to skip the file system check on reboot
#FASTBOOT=yes

# Skip reading from the console
#HEADLESS=yes

# Write out fsck progress if yes
#VERBOSE_FSCK=no

# Speed up boot without waiting for settle in udev
#OMIT_UDEV_SETTLE=y

# Speed up boot without waiting for settle in udev_retry
#OMIT_UDEV_RETRY_SETTLE=yes

# Skip cleaning /tmp if yes
#SKIPTMPCLEAN=no

# For setclock
#UTC=1
#CLOCKPARAMS=

# For consolelog (Note that the default, 7=debug, is noisy)
#LOGLEVEL=7

# For network
#HOSTNAME=mylfs

# Delay between TERM and KILL signals at shutdown
#KILLDELAY=3

# Optional sysklogd parameters
#SYSKLOGD_PARMS="-m 0"

# Console parameters
#UNICODE=1
#KEYMAP="de-latin1"
#KEYMAP_CORRECTIONS="euro2"
#FONT="lat0-16 -m 8859-15"
#LEGACY_CHARSET=

# 9.7. Configuring the System Locale
# The list of all locales supported by Glibc can be obtained by running the following command:
locale -a

# Charmaps can have a number of aliases, e.g. ISO-8859-1 is also referred to as iso8859-1 and iso88591. Some applications cannot handle the various synonyms correctly (e.g., require that UTF-8 is written as UTF-8, not utf8), so it is the safest in most cases to choose the canonical name for a particular locale. To determine the canonical name, run the following command, where <locale name> is the output given by locale a for your preferred locale (en_GB.iso88591 in our example).
LC_ALL="en_GB.iso88591" locale charmap

# For the en_GB.iso88591 locale, the above command will print:
# ISO-8859-1

# The results in a final locale setting of en_GB.ISO-8859-1. It is important that the locale found using the heuristic above is tested prior it being added to the Bashstartup files:
LC_ALL="en_GB.iso88591" locale language
LC_ALL="en_GB.iso88591" locale charmap
LC_ALL="en_GB.iso88591" locale int_curr_symbol
LC_ALL="en_GB.iso88591" locale int_prefix

# Create the /etc/profile once the proper locale settings have been determined to set the desired locale, but set the C.UTF-8 locale instead if running in the Linux console (to prevent programs from outputting characterss that the Linux console is unable to render):
cat > $LFS/etc/profile << "EOF"
# Begin /etc/profile

for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
#else
#  export LANG=en_GB_iso88591.<charmap><@modifiers>
fi

# End /etc/profile
EOF

# 9.8. Creating the /etc/inputrc File
cat > $LFS/etc/inputrc << "EOF"
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line

# End /etc/inputrc
EOF

# 9.9. Creating the /etc/shells File
# It is a requirement for application such as GDM which does not populate the face browser if it can't find /etc/shells, or FTP daemons which traditionally disallow access to users with shells not included in this file.
cat > $LFS/etc/shells << "EOF"
# Begin /etc/shells

/bin/sh
/bin/bash

# End /etc/shells
EOF

# ===========================================================================
# Chapter 10. Making the LFS System Bootable
# ===========================================================================
# The /etc/fstab file is used by some programs to determine where file systems are to be mounted by default, in which order, and which must be checked (for integrity errors) prior to mounting. Create a new file systems table like this:
cat > $LFS/etc/fstab << "EOF"
# Begin /etc/fstab

# file system  mount-point    type     options             dump  fsck
#                                                                order

/dev/sda1      /              ext4     defaults            1     1
/dev/sd2       swap           swap     pri=1               0     0
proc           /proc          proc     nosuid,noexec,nodev 0     0
sysfs          /sys           sysfs    nosuid,noexec,nodev 0     0
devpts         /dev/pts       devpts   gid=5,mode=620      0     0
tmpfs          /run           tmpfs    defaults            0     0
devtmpfs       /dev           devtmpfs mode=0755,nosuid    0     0
tmpfs          /dev/shm       tmpfs    nosuid,nodev        0     0
cgroup2        /sys/fs/cgroup cgroup2  nosuid,noexec,nodev 0     0

# End /etc/fstab
EOF

# 10.3. Linux-6.10.5
cd /mnt/lfs/sources/linux-6.10.5

make mrproper

make menuconfig

make 

make modules_install

mount $LFS/boot

# Have a look at this part over here

# The following command assumes an x86 architecture
#cp -iv arch/x86/boot/bzImage /boot/vmlinuz-6.10.5-lfs-12.2
cp -iv arch/x86/boot/bzImage $LFS/boot/vmlinuz-6.10.5-lfs-12.2

# System.map is a symbol file for the kernel. It maps the function entry points of every function in the kernel API, as well as the addresses of the kernel data structures for the running kernel. It is used as a resource when investigating kernel problems. Issue the following command to install the map file:
#cp -iv System.map /boot/System.map-6.10.5
cp -iv System.map $LFS/boot/System.map-6.10.5

# The kernel configuration file .config produced by the make menuconfig step above contains all the configuration selections for the kernel that was just compiled. It is a good idea to keep this file for future reference:
#cp -iv .config /boot/config-6.10.5
cp -iv .config $LFS/boot/config-6.10.5

# Install the documentation for the Linux kernel:
#cp -r Documentation -T /usr/share/doc/linux-6.10.5
cp -r Documentation -T $LFS/usr/share/doc/linux-6.10.5

# 10.3.2. Configuring Linux Module Load Order
# Create a new file /etc/modprobe.d/usb.conf by running the following:
# install -v -m755 -d /etc/modprobe.d
install -v -m755 -d $LFS/etc/modprobe.d
cat > $LFS/etc/modprobe.d/usb.conf << "EOF"
# Begin /etc/modprobe.d/usb.conf

install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true

# End /etc/modprobe.d/usb.conf
EOF

# 10.4. Using GRUB to Set Up the Boot Process
# 10.4.1. Introduction
#cd /tmp
#grub-mkrescue --output=grub-img.iso
#xorriso -as cdrecord -v dev=/dev/cdrw blank=as_needed grub-img.iso

# 10.4.3. Setting Up the Configuration
# Install the GRUB files into /boot/grub and set up the boot track:
grub-install $LFS/dev/sda

# 10.4.4. Creating the GRUB Configuration File
# Generate /boot/grub/grub.cfg:
cat > $LFS/boot/grub/grub.cfg << "EOF"
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod part_gpt
insmod ext2
set root=(hd0,2)

menuentry "GNU/Linux, Linux 6.10.5-lfs-12.2" {
        linux   /boot/vmlinuz-6.10.5-lfs-12.2 root=/dev/sda2 ro
}
EOF

# ===========================================================================
# Chapter 11. Entering chroot and Building Additional Temporary Tools
# ===========================================================================

# It may be a good idea to create an /etc/lfs-release file. By having this file, it is very easy for you to find out which LFS version is installedo n the system. Create this file by running:
echo 12.2 > $LFS/etc/lfs-release

# Two files describing the installed system may be used by packages that can be installed on the system later; either in binary form or by building them
# The first one shows the status of your new system with respect to the Linux Standards Base (LSB). To create this file, run:
cat > $LFS/etc/lsb-release << "EOF"
DISTRIB_ID="Linux From Scratch"
DISTRIB_RELEASE="12.2"
DISTRIB_CODENAME="Version"
DISTRIB_DESCRIPTION="Linux From Scratch"
EOF

# The second one contains roughly the same information, and is used by systemd and some graphical desktop environments. To create this file, run:
cat > $LFS/etc/os-release << "EOF"
NAME="Linux From Scratch"
VERSION="12.2"
ID=lfs
PRETTY_NAME="Linux From Scratch 12.2"
VERSION_CODENAME="Version"
HOME_URL="https://www.linuxfromscratch.org/lfs/"
EOF

# Be sure to customize the fields 'DISTRIB_CODENAME' and 'VERSION_CODENAME' to make the system uniquely yours.

# 11.3. Rebooting the System
logout

umount -v $LFS/dev/pts
mountpoint -q $LFS/dev/shm && umount -v $LFS/dev/shm
umount -v $LFS/dev
umount -v $LFS/run
umount -v $LFS/proc
umount -v $LFS/sys

umount -v $LFS/home
umount -v $LFS

umount -v $LFS

echo "You must now reboot the system in order to take its effect with LFS"