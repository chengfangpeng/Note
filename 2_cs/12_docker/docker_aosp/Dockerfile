FROM ubuntu:14.04


RUN apt-get update && \
    apt-get install -y bc bison bsdmainutils build-essential curl wget \
        flex g++-multilib gcc-multilib git gnupg gperf lib32ncurses5-dev \
        lib32readline-gplv2-dev lib32z1-dev libesd0-dev libncurses5-dev \
        libsdl1.2-dev libwxgtk2.8-dev libxml2-utils lzop \
        openjdk-7-jdk \
        pngcrush schedtool xsltproc zip zlib1g-dev \
        software-properties-common python-software-properties && \
        add-apt-repository ppa:git-core/ppa && apt-get update && apt-get install -y git && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD https://mirrors.tuna.tsinghua.edu.cn/git/git-repo /usr/local/bin/repo
RUN chmod 777 /usr/local/bin/repo && wget ftp://public:123456@10.2.53.233/tools/toolchains/gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz \
    && tar -xvJf gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz -C /opt && wget ftp://public:123456@10.2.53.233/tools/toolchains/gcc-linaro-arm-none-eabi-4.8-2013.11_linux.tar.xz \
    && tar -xvJf gcc-linaro-arm-none-eabi-4.8-2013.11_linux.tar.xz -C /opt && wget ftp://public:123456@10.2.53.233/tools/gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux.tgz \
    && tar -zxvf gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux.tgz -C /opt

WORKDIR /home/aosp/
ENV abc=hell
ENV ENV_1=/opt/gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux/bin
ENV ENV_2=/opt/gcc-linaro-arm-none-eabi-4.8-2013.11_linux/bin
ENV REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/'

ENV PATH=${PATH}:/opt/gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux/bin



# All builds will be done by user aosp
COPY gitconfig /root/.gitconfig
COPY ssh_config /root/.ssh/config
COPY id_rsa /root/.ssh/id_rsa
COPY id_rsa.pub /root/.ssh/id_rsa.pub
COPY build_tv_920.sh /root/build_tv_920.sh

VOLUME ["/tmp/ccache", "/aosp"]

WORKDIR /aosp

COPY docker_entrypoint.sh /root/docker_entrypoint.sh
ENTRYPOINT ["/root/docker_entrypoint.sh"]
