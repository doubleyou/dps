#!/bin/sh


if [ ! -f /etc/apt/sources.list.d/backports.list ] ; then
  echo "deb http://backports.debian.org/debian-backports squeeze-backports main contrib non-free" > /etc/apt/sources.list.d/backports.list
fi

if [ ! -f /etc/apt/sources.list.d/sid.list ] ; then
  echo "deb http://mirrors.kernel.org/debian/ sid main" > /etc/apt/sources.list.d/sid.list
fi

apt-get update
apt-get -y install erlang-base-hipe erlang-eunit erlang-os-mon erlang-runtime-tools erlang-tools erlang-crypto git make

echo "*              hard    nofile          20480" > /etc/security/limits.d/nofile.conf
echo "*              soft    nofile          20480" >> /etc/security/limits.d/nofile.conf
