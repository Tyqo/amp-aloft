#!/bin/bash

echo "Starting Aloft..."

steamcmd +login  +force_install_dir . +app_update 1660080 validate +quit
