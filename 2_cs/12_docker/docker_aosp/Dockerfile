FROM ubuntu:16.04


RUN apt-get update && \
    apt-get install -y bc bison bsdmainutils build-essential curl \
        flex g++-multilib gcc-multilib git gnupg gperf lib32ncurses5-dev \
        lib32z1-dev libesd0-dev libncurses5-dev \
        libsdl1.2-dev libwxgtk3.0-dev libxml2-utils lzop sudo \
        openjdk-8-jdk \
        pngcrush schedtool xsltproc zip zlib1g-dev graphviz && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD https://mirrors.tuna.tsinghua.edu.cn/git/git-repo /usr/local/bin/repo
RUN chmod 777 /usr/local/bin/repo

# All builds will be done by user aosp
COPY gitconfig /root/.gitconfig
COPY ssh_config /root/.ssh/config

VOLUME ["/tmp/ccache", "/aosp"]

WORKDIR /aosp

COPY docker_entrypoint.sh /root/docker_entrypoint.sh
ENTRYPOINT ["/root/docker_entrypoint.sh"]
