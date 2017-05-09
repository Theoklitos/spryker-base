#!/bin/sh

# upgrade to alpine 3.5 as we need some nginx packages which are only available in alpine >3.5

sectionNote "update repositories to alpine 3.5"
sed -i -e 's/3\.4/3.5/g' /etc/apk/repositories

apk update

# `apk upgrade --clean-protected` for not creating *.apk-new (config)files
sectionNote "do the upgrade"
apk upgrade --clean-protected
