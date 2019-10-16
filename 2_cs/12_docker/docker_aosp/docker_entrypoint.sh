#!/bin/bash
set -e

# This script designed to be used a docker ENTRYPOINT "workaround" missing docker
# feature discussed in docker/docker#7198, allow to have executable in the docker
# container manipulating files in the shared volume owned by the USER_ID:GROUP_ID.
#
# It creates a user named `aosp` with selected USER_ID and GROUP_ID (or
# 1000 if not specified).

# Example:
#
#  docker run -ti -e USER_ID=$(id -u) -e GROUP_ID=$(id -g) imagename bash
#

# Reasonable defaults if no USER_ID/GROUP_ID environment variables are set.
if [ -z ${USER_ID+x} ]; then USER_ID=1000; fi
if [ -z ${GROUP_ID+x} ]; then GROUP_ID=1000; fi

msg="docker_entrypoint: Creating user UID/GID [$USER_ID/$GROUP_ID]" && echo $msg
groupadd -g $GROUP_ID -r aosp && \
useradd -u $USER_ID --create-home -r -g aosp aosp
echo "$msg - done"

msg="docker_entrypoint: Copying .gitconfig and .ssh/config to new user home" && echo $msg
cp /root/.gitconfig /home/aosp/.gitconfig && \
chown aosp:aosp /home/aosp/.gitconfig && \
mkdir -p /home/aosp/.ssh && \
cp /root/.ssh/config /home/aosp/.ssh/config && \
cp /root/.ssh/id_rsa /home/aosp/.ssh/id_rsa && \
cp /root/.ssh/id_rsa.pub /home/aosp/.ssh/id_rsa.pub && \
chown aosp:aosp -R /home/aosp/.ssh && \
echo "    IdentityFile ~/.ssh/id_rsa" >> /etc/ssh/ssh_config && \
echo "$msg - done"



msg="docker_entrypoint: Creating /tmp/ccache and /aosp directory" && echo $msg
mkdir -p /tmp/ccache /aosp
chown aosp:aosp /tmp/ccache /aosp
echo "$msg - done"

echo "docker_entrypoint:create tv 920 shell"
chown aosp:aosp -R /home/aosp/
cp /root/build_tv_920.sh /home/aosp/build_tv_920.sh && \
chown aosp:aosp /home/aosp/build_tv_920.sh && \
chmod +x /home/aosp/build_tv_920.sh

# Default to 'bash' if no arguments are provided
args="$@"
if [ -z "$args" ]; then
  args="bash"
fi

# Execute command as `aosp` user
export HOME=/home/aosp
exec sudo -E -u aosp $args
