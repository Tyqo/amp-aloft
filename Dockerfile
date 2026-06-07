FROM        debian:trixie-slim
ENV         DEBIAN_FRONTEND="noninteractive"

ARG         TARGETARCH="amd64"
ARG         WINE_DIST="trixie"
ARG         WINE_BRANCHES="stable devel staging 11-stable 10-stable 9-stable"
ARG         WINE_BRANCH="stable"
ARG         WINE_LINK="https://dl.winehq.org/wine-builds/debian/pool/main/w/wine/"

ENV         LANG="en_US.UTF-8" LANGUAGE="en_US:en" LC_ALL="en_US.UTF-8"

STOPSIGNAL  SIGINT

RUN         set -eux; \
            mkdir -p /usr/share/man/man1; \
            apt-get update; \
            apt-get install -o APT::Keep-Downloaded-Packages="false" -y \
                ca-certificates curl wget tar unzip xz-utils bzip2 \
                coreutils procps iproute2 iputils-ping socat jq git git-lfs gnupg tmux dbus \
                tini tzdata locales gosu \
                libssl3t64 libcurl4t64 libsqlite3-0 libzstd1 libsdl2-2.0-0 libsdl1.2debian libfontconfig1 libicu76 \
                # Required for Proton
                python3 \
                # Required for Core Keeper
                xvfb xauth libxi6 \
                # Required for Valheim crossplay (and variously some others)
                libc6 libatomic1 libpulse0 libpulse-mainloop-glib0 \
                # Required for BeamMP
                liblua5.3-0 \
                # Required for Eco
                libgdiplus \
                # Required for Pavlov VR (and variously some others)
                gdb libc++1 libc++abi1 libunwind8 libgcc-s1;


COPY        scripts/wine/find-deps.sh /usr/local/bin/find-deps.sh
COPY        scripts/wine/create-common-deps-list.sh /usr/local/bin/create-common-deps-list.sh
RUN         chmod +x /usr/local/bin/find-deps.sh /usr/local/bin/create-common-deps-list.sh

RUN         set -eux; \
            dpkg --add-architecture i386; \
            apt-get update; \
            apt-get install -o APT::Keep-Downloaded-Packages="false" -y --no-install-recommends \
                ca-certificates curl wget gnupg xz-utils; \
            install -d -m 0755 /etc/apt/keyrings; \
            wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
            | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key -; \
            wget -NP /etc/apt/sources.list.d/ \
            "https://dl.winehq.org/wine-builds/debian/dists/${WINE_DIST}/winehq-${WINE_DIST}.sources"; \
            apt-get update; \
            \
            for b in ${WINE_BRANCHES}; do \
                /usr/local/bin/find-deps.sh "${b}" >"/tmp/wine-${b}-deps-amd64.txt"; \
            done; \
            mkdir -p /tmp/wine-files; \
            /usr/local/bin/create-common-deps-list.sh /tmp/wine-*-deps-amd64.txt \
                > /tmp/wine-files/wine-common-deps-amd64.txt; \
            mv /tmp/wine-*-deps-amd64.txt /tmp/wine-files/

# Install additional required packages and Wine stable
RUN         set -eux; \
            WINE_BUILD="$( \
                curl -fsSL "${WINE_LINK}" \
                | grep -oE "wine-${WINE_BRANCH}-amd64_[0-9][0-9.]*~${WINE_DIST}(-[0-9]+)?_amd64\.deb" \
                | sed -E "s/^wine-${WINE_BRANCH}-amd64_([0-9.]+~${WINE_DIST}(-[0-9]+)?)_amd64\.deb$/\1/" \
                | sort -V | tail -1 \
                )"; \
            \
            install -d -m 0755 /etc/apt/keyrings; \
            wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
                | gpg --batch --yes --dearmor \
                    -o /etc/apt/keyrings/winehq-archive.key; \
            wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/${WINE_DIST}/winehq-${WINE_DIST}.sources; \
            \
            apt-get update; \
            apt-get install -o APT::Keep-Downloaded-Packages="false" -y --install-recommends \
                winehq-${WINE_BRANCH}; \
            \
            rm -rf /tmp/wine-files; \
            apt-get clean; \
            rm -rf /var/lib/apt/lists/*

# COPY        ./scripts/ampstart.sh /ampstart.sh
# RUN         chmod +x /ampstart.sh
# ENTRYPOINT  ["/usr/bin/tini", "-g", "--", "/ampstart.sh"]
# CMD         []

# Enable i386 architecture and install SteamCMD

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl ca-certificates tar lib32gcc-s1 \
    && mkdir -p /opt/steamcmd \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C /opt/steamcmd


RUN mkdir /opt/aloft-amp
COPY  --chmod=+x ./scripts/ampstart.sh /opt/aloft-amp/ampstart.sh

WORKDIR /opt/aloft-amp

RUN cp /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd

# ENTRYPOINT ["./ampstart.sh"]
ENTRYPOINT ["tail", "-f", "/dev/null"]
