#!/bin/sh

# Author: Tony Fahrion <tony.fahrion@de.clara.net>

#
# This script adds the nodejs package repo and installs nodejs and npm
# It requires that the ENV var NODEJS_VERSION is set!
#
# NOTE: it will install the latest minor version of the selected major version!
#

SUPPORTED_NODEJS_VERSIONS='6 7'
SUPPORTED_NODEJS_PACKAGE_MANAGER='npm yarn'
NPM='npm'


# include helper functions
source ./build_library.sh
source ./functions.sh

# abort on error
set -e

#get amount of available prozessors * 2 for faster compiling of sources
COMPILE_JOBS=$((`getconf _NPROCESSORS_ONLN`*2))

#
#  Prepare
#

infoText "check if we support the requested NODEJS_VERSION"
if is_not_in_list "$NODEJS_VERSION" "$SUPPORTED_NODEJS_VERSIONS"; then
  errorText "Requested NODEJS_VERSION '$NODEJS_VERSION' is not supported. Abort!"
  infoText  "Supported nodejs version is one of: $SUPPORTED_NODEJS_VERSIONS"
  exit 1
fi
successText "YES! Support is available for $NODEJS_VERSION"

infoText "check if we support the requested NODEJS_PACKAGE_MANAGER"
if is_not_in_list "$NODEJS_PACKAGE_MANAGER" "$SUPPORTED_NODEJS_PACKAGE_MANAGER"; then
  errorText "Requested NODEJS_PACKAGE_MANAGER '$NODEJS_PACKAGE_MANAGER' is not supported. Abort!"
  infoText  "Supported nodejs package manager is one of: $SUPPORTED_NODEJS_PACKAGE_MANAGER"
  exit 1
fi
successText "YES! Support is available for $NODEJS_PACKAGE_MANAGER"


#
#  Install nodejs & package manager
#

infoText "install nodejs version $NODEJS_VERSION and npm"
if [ "$NODEJS_VERSION" = "7" ]; then
  apk add --no-cache nodejs-current
else
  apk add --no-cache nodejs
fi


# install yarn if requested as package manager
if [ "$NODEJS_PACKAGE_MANAGER" == 'yarn' ]; then
  apk add --no-cache yarn
  NPM='yarn'
fi


#
#  Install antelope
#


installAntelope() {
    labelText "Install antelope tool (static assets generator)"
    
    apk add --no-cache --virtual .antelope_deps python make gcc g++ linux-headers git
    MAKEFLAGS="-j$COMPILE_JOBS" $NPM install antelope
    apk del .antelope_deps
    
    writeErrorMessage "Antelope setup failed"
}

installAntelope
