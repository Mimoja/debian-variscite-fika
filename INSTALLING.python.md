# Building python3.12.1

For use of the pyImprov library as well as some other features in the backend the
minimal python version is 3.10, ideally 3.11. As debian 11 ships with at most
python3.9 we need to build our own python3.

## Entering the chroot
We don't crosscompile python due to the bootstrapping requirements and instead build inside
a rootfs chroot.

We enter the chroot via systemd-nspawn, but manual chroot would also work
```
sudo systemd-nspawn -D rootfs --bind=./variscite/python:/opt/python
```

Install dependencies in the chroot with:

For Debian 11 where python3.9 is the latest version:
```
apt install wget libffi-dev libbz2-dev liblzma-dev libsqlite3-dev libncurses5-dev libgdbm-dev zlib1g-dev libreadline-dev libssl-dev tk-dev build-essential libncursesw5-dev libc6-dev openssl git
apt build-dep python3
apt build-dep python3.9
```

## Fetching the source


```
cd /opt/python
mkdir -p sources
wget https://www.python.org/ftp/python/3.12.1/Python-3.12.1.tar.xz -P /tmp
tar xfv /tmp/Python-3.12.1.tar.xz -C sources
cd Python-3.12.1
```

## Building python

Ideally we can now build python with all dependencies

```
./configure --enable-optimizations

```
If you want to create a compressable tar from it later pass --prefix to the configure script:

```
mkdir -p /tmp/python-install/usr
./configure --prefix=/tmp/python-install/usr --enable-optimizations
```

```
make -j`nproc`
```

Running the profile tests might take some time

## Installing python

The now prebuild python image can be compressed so that the var_make_debian.sh or installed systemwide (in that case as root)

```
make -j`nproc` altinstall
```

Compress the python image afterwards:
```
cd /tmp/python-install/
tar --exclude='./usr/lib/python3.12/__pycache__' --exclude='./usr/lib/python3.12/test' --exclude='./usr/lib/python3.12/config-3.12-aarch64-linux-gnu' -zcvf /opt/python/python3.12.tar.gz ./usr
```
