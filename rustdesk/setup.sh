#!/bin/bash

branch=$1
rustdesk_client_version=1.1.9
vcpkg_version=2021.12.01

# load MYSERVERIP and MYPORT and MYRELAYPORT env variables
if [ -f $HOME/.ssh/my_server_and_port.sh ]
then
    . $HOME/.ssh/my_server_and_port.sh
fi

apt install -y zip patch g++ gcc git curl wget nasm yasm libgtk-3-dev clang libxcb-randr0-dev libxdo-dev libxfixes-dev libxcb-shape0-dev libxcb-xfixes0-dev libasound2-dev libpulse-dev cmake libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

cd $HOME
git clone https://github.com/microsoft/vcpkg
cd vcpkg
git checkout $vcpkg_version
cd ..
./vcpkg/bootstrap-vcpkg.sh -disableMetrics
export VCPKG_ROOT=$HOME/vcpkg
./vcpkg/vcpkg install libvpx libyuv opus

# install rust build environment
curl -sSf https://sh.rustup.rs > rustup.sh
sh rustup.sh -y

echo "git clone https://github.com/rustdesk/rustdesk.git"
git clone https://github.com/rustdesk/rustdesk.git
cd rustdesk
echo "git checkout $rustdesk_client_version -b v$rustdesk_client_version"
git checkout $rustdesk_client_version -b v$rustdesk_client_version
echo "apply patch my_server_and_port.patch"
# applying patch to set rendezvous and relay servers as command line parameters
patch -p1 < $HOME/lbs-rustdesk/rustdesk/my_server_and_port.patch || exit -1
echo "apply patch fix_config_locks.patch"
# applying patch to fix issue: https://github.com/rustdesk/rustdesk/pull/1900
patch -p1 < $HOME/lbs-rustdesk/fix_config_locks.patch || exit -1

mkdir -p target/release
curl -sSf https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.lnx/x64/libsciter-gtk.so > target/release/libsciter-gtk.so

# the actual build of rustdesk client
source $HOME/.cargo/env
VCPKG_ROOT=$HOME/vcpkg cargo build --release || exit -1
# see result in target/release

cd $HOME
DELIVERY=$HOME/rustdesk-bin
mkdir -p $DELIVERY
cp rustdesk/target/release/libsciter-gtk.so $DELIVERY
cp rustdesk/target/release/rustdesk $DELIVERY
mkdir -p $DELIVERY/src/ui
cp rustdesk/src/ui/* $DELIVERY/src/ui
cat > $DELIVERY/rustdesk.sh << FINISH
#!/bin/bash
cd /usr/share/rustdesk
FINISH
if [ ! -z $MYSERVERIP ]
then
    # setting the server details in the configuration
    echo "./rustdesk --rendezvous_server $MYSERVERIP:$MYPORT --relay_server $MYSERVERIP:$MYRELAYPORT" >> $DELIVERY/rustdesk.sh
fi
echo "./rustdesk" >> $DELIVERY/rustdesk.sh
chmod a+x $DELIVERY/rustdesk.sh
cat > $DELIVERY/rustdesk.desktop << FINISH
[Desktop Entry]
Encoding=UTF-8
Comment=A remote control software.
Exec=rustdesk
Icon=rustdesk
Name=RustDesk
Terminal=false
Type=Application
MimeType=
Version=$rustdesk_client_version
FINISH
cp rustdesk/snap/gui/rustdesk.png $DELIVERY
mkdir -p $HOME/sources
tar czf $HOME/sources/rustdesk-bin.tar.gz $DELIVERY

cd ~/lbs-rustdesk/rustdesk
sed -i "s/1.0.0/$rustdesk_client_version/g" debian/changelog
sed -i  "s/1.0.0/$rustdesk_client_version/g" rustdesk.dsc
