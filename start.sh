#!/bin/bash

echo "Starting Aloft..."

/usr/bin/steam \
-applaunch 1660080 \
-batchmode \
-nographics \
-server load#LinuxWorld# \
log#ERROR# \
disablevideo#true#

sleep 600

## https://eggs.pterodactyl.io/egg/games-aloft
