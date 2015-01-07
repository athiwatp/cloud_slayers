#!/usr/bin/env bash

set -e

if [ -d /etc/apt ]; then
  apt-get install -y docker.io
elif [ -d /etc/yum.repos.d ]; then
  yum install -y docker-io
  chkconfig --add docker
else
  echo "Unsupported distro"
fi
