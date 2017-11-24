#!/bin/bash

# Install XDS cli

DESTDIR=${DESTDIR:-/opt/AGL/xds/cli}

ROOT_SRCDIR=$(cd $(dirname "$0")/.. && pwd)

install() {
    mkdir -p "${DESTDIR}" && cp "${ROOT_SRCDIR}/bin/*" "${DESTDIR}" || exit 1

    FILE=/etc/profile.d/xds-cli.sh
    sed -e "s;%%XDS_INSTALL_BIN_DIR%%;${DESTDIR};g" "${ROOT_SRCDIR}/conf.d/${FILE}" > ${FILE} || exit 1
}

uninstall() {
    rm -rf "${DESTDIR}"
    rm -f /etc/profile.d/xds-cli.sh
}

if [ "$1" == "uninstall" ]; then
    echo -n "Are-you sure you want to remove ${DESTDIR} [y/n]? "
    read answer
    if [ "${answer}" = "y" ]; then
        uninstall
        echo "xds-cli sucessfully uninstalled."
    else
        echo "Uninstall canceled."
    fi
else
    install
fi