ARG DEBIAN_RELEASE=bookworm
FROM debian:${DEBIAN_RELEASE}
# We're using mount caches, so don't clean the apt cache after every apt command!
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

ENV DEBIAN_FRONTEND=noninteractive

RUN  --mount=target=/var/lib/apt/lists,type=cache,sharing=locked \
     --mount=target=/var/cache/apt,type=cache,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get -y update && \
    apt-get install -y \
       curl \
       pbuilder \
       vim \
       cdbs \
       autoconf \
       automake \
       quilt \
       reportbug \
       git-buildpackage \
       libpq-dev \
       libjpeg62-turbo-dev \
       zlib1g-dev \
       libgammu-dev \
       libldap-dev \
       libsasl2-dev \
       python3-dev \
       python3-all \
       libsnmp40t64 \
     && \
     apt-get clean

RUN  --mount=target=/var/lib/apt/lists,type=cache,sharing=locked \
     --mount=target=/var/cache/apt,type=cache,sharing=locked \
     apt-get -y update && \
     apt-get install -y \
         dh-virtualenv \
         dh-python \
         python3-setuptools

# Install Node.js for webpack
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs

RUN  chmod 777 /home
ENV  HOME=/home
ENV  QUILT_PATCHES=debian/patches
ENV  QUILT_NO_DIFF_INDEX=1
ENV  QUILT_NO_DIFF_TIMESTAMPS=1
ENV  QUILT_REFRESH_ARGS="-p ab"

CMD  ["/bin/bash"]
