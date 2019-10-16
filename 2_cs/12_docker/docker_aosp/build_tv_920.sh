set -ex


work_dir=/aosp
cd $work_dir

REPO_BRANCH="amlogic_t920_new_master"

cpus=$(grep ^processor /proc/cpuinfo | wc -l)

repo init -u gome_tv:/platform/manifest -b ${REPO_BRANCH} --no-repo-verify

# Use default sync '-j' value embedded in manifest file to be polite
repo sync
export PATH=$PATH:$ENV_1:$ENV_2
source build/envsetup.sh
lunch r34tv-userdebug-32
make otapackage -j8 2>&1 | tee make.log
