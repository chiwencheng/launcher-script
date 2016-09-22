#!/bin/bash

#####################################

VERSION="1.8"
HOST="amax01.corpnet.asus"
MAIN_DIRECTORY="AsusLauncher"
MAIN_PROJECT="amax_L/packages/apps/AsusLauncher"
MAIN_BRANCH="AsusLauncher_1.4_dev AsusLauncher_1.4_beta AsusLauncher_1.4_play"

MOUNT_APK_POOL="/mnt/APK_Pool"
REMOTE_APK_POOL_PATH="//10.78.24.10/AMAX-release/APK_Pool"

COLOR_RED=`tput setaf 1`
COLOR_GREEN=`tput setaf 2`
COLOR_YELLOW=`tput setaf 3`
COLOR_RESET=`tput sgr0`

#####################################

function syncSourceCode {
    local directory=$1
    local project=$2
    local branch=$3
    local tag=$4
    echo "[START] sync $directory ${tag}"
    if [ ! -d "$directory" ]; then
        git clone ssh://${USER_NAME}@${HOST}:29418/${project} -b ${branch} ${directory}
    else
        cd ${directory}
        # repository changed, re-sync project
        local repostoryChanged=0
        if [ "$(git config --get remote.origin.url)" != "ssh://${USER_NAME}@${HOST}:29418/${project}" ]; then
            repostoryChanged=1
            printLog "WARN" "repostiory changed ${project}"
        fi
        cd ..

        local sourceCodeAbnormal=0
        if [ ! -e "${directory}/AndroidManifest.xml" ]; then
            sourceCodeAbnormal=1
            printLog "WARN" "source code abnormal"
        fi

        if [ ${sourceCodeAbnormal} == 1 ] || [ ${repostoryChanged} == 1 ]; then
            # abnormal status, re-sync project
            if [ "${directory}" != "${MAIN_DIRECTORY}" ]; then
                read -r -p "[INFO] Remove and re-sync ${directory}? [y/N] " response
                case ${response} in
                    [yY][eE][sS]|[yY])
                        rm -rf ${directory}
                        git clone ssh://${USER_NAME}@${HOST}:29418/${project} -b ${branch} ${directory}
                        ;;
                    *)
                        return
                        ;;
                esac
            fi
        fi
    fi

    if [ "${directory}" == "${MAIN_DIRECTORY}" ]; then
        printLog "WARN" "skip main project"
        return
    fi

    if [ -d "$directory" ]; then
        cd ${directory}

        # checkout build file to HEAD for rebase
        local array=("build.xml" "asus_build.xml" "project.properties" "build.gradle")
        for file in $(git status --porcelain | grep "^ M" | sed -e 's/^[ M]* //')
        do
            local found=$(echo ${array[*]} | grep ${file})
            if [ "${found}" != "" ]; then
                git checkout ${file}
            fi
        done
        for file in $(git status --porcelain | grep "^?? " | sed -e 's/^[?]* //')
        do
            local found=$(echo ${array[*]} | grep ${file})
            if [ "${found}" != "" ]; then
                local result=$(git clean -f ${file} 2>/dev/null 2>&1)
            fi
        done

        # reset symbolic link for windows
        local symbolicArray=("src" "res" "libs" "proguard.flags")
        if windows && [ -d "app/src/" ]; then
            for file in ${symbolicArray[@]}
            do
                if [ -h ${file} ]; then
                    git checkout ${file}
                else
                    printLog "WARN" "${file} is not symbolic link"
                fi
            done
        fi

        if [ -n "${tag}" ]; then
            # fetch lastest code
            git fetch
            # checkout to target tag
            var=$(git checkout ${tag} 2>&1)
            if test "${var#*error}" != "$var"; then
                printLog "ERROR" "${var}"
            else
                printLog "SUCCESS" "$(echo "${var}" | tail -n1)"
            fi
        else
            # checkout to default if not currently on a branch
            if [ -z "$(git symbolic-ref HEAD 2>/dev/null)" ] ||
                [ "$(git symbolic-ref HEAD)" !=  "refs/heads/${branch}" ]; then
                var=$(git checkout ${branch} 2>&1)
                if test "${var#*error}" != "$var"; then
                    printLog "ERROR" "${var}"
                fi
            fi

            # sync to latest code base
            var=$(git pull --rebase 2>&1)
            if test "${var#*Cannot pull with rebase}" != "$var"; then
                printLog "ERROR" "${var}"
            else
                printLog "SUCCESS" "${var}"
            fi
        fi

        # set symbolic link for windows
        if windows && [ -d "app/src/" ]; then
            for file in ${symbolicArray[@]}
            do
                link_path=$(cat ${file})
                if [ -d "${link_path}" ] ||  [ -f "${link_path}" ]; then
                    rm ${file}
                    link ${file} "${link_path}"
                else
                    printLog "WARN" "skip ${file}"
                fi
            done
            printLog "INFO" "set symbolic link done"
        fi
        cd ..

        # fix no change id
        cp ${MAIN_DIRECTORY}/scripts/AntBuild/commit-msg ${directory}/.git/hooks/
    fi
}

function syncMainSourceCode {
    local directory=$1
    local project=$2
    if [ ! -d "$directory" ]; then
        echo "[INFO] Choose you target branch:"
        select opt in ${MAIN_BRANCH}; do
            if test "${MAIN_BRANCH#*$opt}" != "$MAIN_BRANCH"; then
                syncSourceCode ${directory} ${project} ${opt}
                break
            else
                printLog "ERROR" "wrong branch"
                exit
            fi
        done
    else
        echo "[START] sync ${directory}"
        cd ${directory}
        git fetch
        cd ..
        printLog "SUCCESS" "fetch latest code for ${directory}"
    fi

    # fix no change id
    if [ -d "$directory" ]; then
        cp ${directory}/scripts/AntBuild/commit-msg ${directory}/.git/hooks/
    fi
}

function checkAndExtractAARfiles {
    local directory=$1
    # aar for ant build and Android Studio
    local aar_files;
    if ls -d ${directory}/*.aar 1> /dev/null 2>&1; then
        aar_files=$(ls -d ${directory}/*.aar)
    elif ls -d ${directory}/libs/*.aar 1> /dev/null 2>&1; then
        aar_files=$(ls -d ${directory}/libs/*.aar)
    fi

    if [ ! -z "${aar_files}" ];then
        for aar in ${aar_files}
        do
            local filename=$(basename "$aar")
            local aar_folder="${directory}/${filename%.*}"
            local aar_for_studio="${aar_folder}/${filename}"

            if diff ${aar} ${aar_for_studio} >/dev/null 2>&1; then
                echo "[Info] $aar and $aar_for_studio same"
                continue;
            else
                echo "[Info] $aar and $aar_for_studio different"
            fi

            # rm assets copyed from unzipped .aar
            local copyed_assets=$(find ${aar_folder}/assets/ -type f | cut -d '/' -f4,5)
            for copyed_asset in ${copyed_assets}
            do
                rm -r ${directory}/assets/${copyed_asset}
            done
            # remove any file except build.xml asus_build.xml project.projecties pre-load in aar folder
            all_files_in_aar_folder=$(ls ${aar_folder})
            local array=("build.xml" "asus_build.xml" "project.properties" "pre-load" "build.gradle")
            for file in ${all_files_in_aar_folder}
            do
                local found=$(echo ${array[*]} | grep ${file})
                if [ "${found}" == "" ]; then
                    rm -rf ${aar_folder}/${file}
                fi
            done

            # cp aar for Android Studio
            mkdir -p ${aar_folder}
            cp ${aar} ${aar_folder}/

            #unzip aar files
            cd ${aar_folder}
            if windows; then
                jar xf ${filename}
            else
                unzip ${filename}
            fi
            cd -

            # move aar resource
            mkdir -p ${aar_folder}/src
            mkdir -p ${aar_folder}/pre-load
            mkdir -p ${aar_folder}/libs
            cp ${aar_folder}/*.jar ${aar_folder}/libs/
            if ls -d ${aar_folder}/jni 1> /dev/null 2>&1; then
                for nativeso in $(ls ${aar_folder}/jni)
                do
                    cp -arp ${aar_folder}/jni/${nativeso} ${aar_folder}/libs/
                done
            fi
            if ls -d ${aar_folder}/assets/* 1> /dev/null 2>&1; then
                cp -arp ${aar_folder}/assets/* ${directory}/assets/
            fi

            export INTERNAL_PROJECTS=$(echo ${INTERNAL_PROJECTS} ${aar_folder})

            printLog "SUCCESS" "finish deploy ${aar}"
        done
    else
        echo "[Info] Don't have AAR files"
    fi
}

function syncExternalProject {
    local directory=$1

    if [ -d "$directory" ]; then
        local tag_array=$(echo ${CURRENT_EXTERNAL_TAG_LIST} | tr " " "\n")
        source ${directory}/scripts/AntBuild/external/sync.conf
        for dir in $(ls -d ${directory}/scripts/AntBuild/external/*/)
        do
            local dirName=$(echo ${dir}|cut -d '/' -f5)
            local projectName=$(echo ${dirName}|cut -d '_' -f1) # remove version, e.g. _1.0
            eval directory=DIRECTORY_\${projectName}
            eval branch=BRANCH_\${projectName}
            eval project=PROJECT_\${projectName}

            if [ -z "${!directory}" ] || [ ${!directory} != ${dirName} ]; then
                printLog "WARN" "${dirName} config not exist, skip..."
                echo "#########"
                continue;
            fi
            local tag=$(printf -- '%s\n' "${tag_array[@]}" | grep -m 1 -i ${projectName})

            syncSourceCode ${!directory} ${!project} ${!branch} ${tag}
            echo "#########"
        done
    else
        printLog "WARN" "sync external project fail, ${directory} exist"
    fi
}

function setExternalAntConfig {
    local directory=$1
    if [ -d "$directory" ]; then
        for dir in $(ls -d ${directory}/scripts/AntBuild/external/*/)
        do
            local dirName=$(echo ${dir}|cut -d '/' -f5)
            if [ -d "$dirName" ]; then
                cp -r ${directory}/scripts/AntBuild/external/${dirName} .
            fi
        done
        echo "[INFO] setup external projects ant build config"
    fi
}

function getExternalTagList {
    local directory=$1

    cd ${directory}
    echo "[Info] Current branch tag is ${COLOR_YELLOW}$(git describe --abbrev=0)${COLOR_RESET}"
    echo "[Info] Type the tag that you want to check (press [ENTER] to skip, or enter 0 to use current branch tag), followed by [ENTER]:"
    read input_tag
    if [ -n "${input_tag}" ]; then
        if [ "${input_tag}" = "0" ]; then
            input_tag=$(git describe --abbrev=0)
        else
            input_tag=${input_tag}
        fi
    else
        cd ..
        return;
    fi
    cd ..
    local main_project_name=$(echo ${input_tag} | cut -d '_' -f1)
    local main_project_version=$(echo ${input_tag} | cut -d '_' -f2)
    local main_version_first=$(echo ${main_project_version} | cut -d '.' -f1)
    local main_version_second=$(echo ${main_project_version} | cut -d '.' -f2)
    local main_version_third=$(echo ${main_project_version} | cut -d '.' -f3)
    local main_version_fourth=$(echo ${main_project_version} | cut -d '.' -f4)
    PATH_CURRENT_VERSION=$(echo ${main_project_name}/${main_version_first}.${main_version_second}.${main_version_third}/${main_version_fourth})

    mountApkPool

    if [ -d "${MOUNT_APK_POOL}/${PATH_CURRENT_VERSION}" ]; then
        local version_code=$(grep VERSION_CODE ${MOUNT_APK_POOL}/${PATH_CURRENT_VERSION}/build_config/build.cfg | cut -d '=' -f2)
        local version_name=$(grep VERSION_NAME ${MOUNT_APK_POOL}/${PATH_CURRENT_VERSION}/build_config/build.cfg | cut -d '=' -f2)
        CURRENT_EXTERNAL_TAG_LIST=$(grep EXTERNAL_TAG_LIST ${MOUNT_APK_POOL}/${PATH_CURRENT_VERSION}/build_config/build.cfg | cut -d '=' -f2)

        echo "[Info] VERSION_CODE: ${version_code}"
        echo "[Info] VERSION_NAME: ${version_name}"
        echo "[Info] APK PATH in local: ${MOUNT_APK_POOL}/${PATH_CURRENT_VERSION}/"
        echo "[Info] APK PATH in remote: ${REMOTE_APK_POOL_PATH}/${PATH_CURRENT_VERSION}/"
        echo ""

        if [ -n "${CURRENT_EXTERNAL_TAG_LIST}" ]; then
            echo "[Info] CURRENT_EXTERNAL_TAG_LIST:"
            echo "${CURRENT_EXTERNAL_TAG_LIST}"
            echo ""
            echo "[Info] Enter the external tag that you want to checkout (press [ENTER] to apply all tag, enter -1 to gen release note), followed by [ENTER]:"
            read external_tag_checkout

            if [ -n "${external_tag_checkout}" ]; then
                if [ "${external_tag_checkout}" = "-1" ]; then
                    syncExternalProject ${MAIN_DIRECTORY}
                    release_note ${directory} ${input_tag}
                    exit;
                else
                    CURRENT_EXTERNAL_TAG_LIST=${external_tag_checkout}
                fi
            else
                echo "[Info] apply all tag"
            fi
        fi

    else
        printLog "WARN" "wrong tag"
    fi

}

function mountApkPool {
    if windows; then
        MOUNT_APK_POOL=${REMOTE_APK_POOL_PATH}
        return
    fi

    # require sudo to mount remote folder
    if ! mount | grep ${MOUNT_APK_POOL} > /dev/null; then
        echo "[Info] Mount APK_POOL require root (only once)"
        sudo mkdir ${MOUNT_APK_POOL}
        if ! dpkg -l | grep cifs-utils > /dev/null; then
            echo "[Info] Install cifs-utils for mount"
            sudo apt-get install cifs-utils
        fi
        sudo mount -t cifs ${REMOTE_APK_POOL_PATH} ${MOUNT_APK_POOL} -o guest
        echo mount | grep ${MOUNT_APK_POOL}
        # remove mount folder
        # sudo umount /mnt/APK_Pool
        # sudo rm /mnt/APK_Pool/ -r
    fi
}

function release_note() {
    local directory=$1
    local current_tag=$2

    cd ${directory}
    echo "[Info] Previous branch tag is ${COLOR_YELLOW}$(git describe --abbrev=0 --tags ${current_tag}^)${COLOR_RESET}"
    echo "[Info] Type the tag that you want to check (press [ENTER] to use previous branch tag, or enter target tag), followed by [ENTER]:"
    read previous_tag
    if [ -n "${previous_tag}" ]; then
        previous_tag=${previous_tag}
    else
        previous_tag=$(git describe --abbrev=0 --tags ${current_tag}^)
    fi
    cd ..
    local main_project_name=$(echo ${previous_tag} | cut -d '_' -f1)
    local main_project_version=$(echo ${previous_tag} | cut -d '_' -f2)
    local main_version_first=$(echo ${main_project_version} | cut -d '.' -f1)
    local main_version_second=$(echo ${main_project_version} | cut -d '.' -f2)
    local main_version_third=$(echo ${main_project_version} | cut -d '.' -f3)
    local main_version_fourth=$(echo ${main_project_version} | cut -d '.' -f4)
    PATH_PREVIOUS_VERSION=$(echo ${main_project_name}/${main_version_first}.${main_version_second}.${main_version_third}/${main_version_fourth})

    mountApkPool

    if [ -d "${MOUNT_APK_POOL}/${PATH_PREVIOUS_VERSION}" ]; then
        PREVIOUS_EXTERNAL_TAG_LIST=$(grep EXTERNAL_TAG_LIST ${MOUNT_APK_POOL}/${PATH_PREVIOUS_VERSION}/build_config/build.cfg | cut -d '=' -f2)
        echo "[Info] PREVIOUS_EXTERNAL_TAG_LIST:"
        echo "${PREVIOUS_EXTERNAL_TAG_LIST}"
        echo ""
    else
        printLog "WARN" "wrong tag"
    fi


    echo "###########################"
    echo "[Info] generate release note"
    echo "#########" > release_note.txt
    local release_note_path=$(readlink -f release_note.txt)
    echo "[Info] ${directory} from ${previous_tag} to ${current_tag}" >> ${release_note_path}
    echo "---------" >> ${release_note_path}

    cd ${directory}
    git log ${previous_tag}..${current_tag} --pretty="%s (%an)" >> ${release_note_path}
    cd ..

    for dir in $(ls -d ${directory}/scripts/AntBuild/external/*/)
    do


        local dirName=$(echo ${dir}|cut -d '/' -f5)
        local projectName=$(echo ${dirName}|cut -d '_' -f1) # remove version, e.g. _1.0
        eval directory=DIRECTORY_\${projectName}
        if [ -z "${!directory}" ] || [ ${!directory} != ${dirName} ]; then
            printLog "WARN" "${dirName} config not exist, skip..."
            continue
        fi

        local tag_array=$(echo ${CURRENT_EXTERNAL_TAG_LIST} | tr " " "\n")
        local previous_tag_array=$(echo ${PREVIOUS_EXTERNAL_TAG_LIST} | tr " " "\n")
        local external_current_tag=$(printf -- '%s\n' "${tag_array[@]}" | grep -m 1 -i ${projectName})
        local external_previous_tag=$(printf -- '%s\n' "${previous_tag_array[@]}" | grep -m 1 -i ${projectName})

        if [ -n "${external_previous_tag}" ] && [ "${external_previous_tag}" != "${external_current_tag}" ]; then
            echo "#########" >> ${release_note_path}
            echo "[Info] ${projectName} from ${external_previous_tag} to ${external_current_tag}" >> ${release_note_path}
            echo "---------" >> ${release_note_path}
            cd ${dirName}
            git log ${external_previous_tag}..${external_current_tag} --pretty="%s (%an)" >> ${release_note_path}
            cd ..
        fi
    done
    echo "[Info] complete! see ${COLOR_GREEN}${release_note_path}${COLOR_RESET}"
    echo "###########################"
}

function printLog {
    local type=$1
    local message=$2

    case ${type} in
    INFO)
      echo "${COLOR_GREEN}[${type}]${COLOR_RESET} ${message}"
      ;;
    SUCCESS)
      echo "${COLOR_GREEN}[${type}]${COLOR_RESET} ${message}"
      ;;
    WARN)
      echo "${COLOR_YELLOW}[${type}]${COLOR_RESET} ${message}"
      ;;
    ERROR)
      echo "${COLOR_RED}[${type}]${COLOR_RESET} ${message}"
      ;;
    FATAL)
      echo "${COLOR_RED}[${type}]${COLOR_RESET} ${message}"
      ;;
    *)
      echo "[${type}] ${message}"
      ;;
    esac
}

# We still need this.
windows() { [[ -n "$WINDIR" ]]; }

# Cross-platform symlink function. With one parameter, it will check
# whether the parameter is a symlink. With two parameters, it will create
# a symlink to a file or directory, with syntax: link $linkname $target
link() {
    if [[ -z "$2" ]]; then
        # Link-checking mode.
        if windows; then
            fsutil reparsepoint query "$1" > /dev/null
        else
            [[ -h "$1" ]]
        fi
    else
        # Link-creation mode.
        if windows; then
            # Windows needs to be told if it's a directory or not. Infer that.
            # Also: note that we convert `/` to `\`. In this case it's necessary.
            if [[ -d "$2" ]]; then
                cmd <<< "mklink /D \"$1\" \"${2//\//\\}\"" > /dev/null
            else
                cmd <<< "mklink \"$1\" \"${2//\//\\}\"" > /dev/null
            fi
        else
            # You know what? I think ln's parameters are backwards.
            ln -s "$2" "$1"
        fi
    fi
}

#####################################

echo "###########################"
echo "[Info] ${COLOR_YELLOW}version ${VERSION}${COLOR_RESET}"

#####################################

USER_NAME=$(grep "${HOST}" ~/.ssh/config -A2 | grep '^user' | cut -d ' ' -f2)
if [ ! -z "${1}" ]; then
    USER_NAME=${1}
fi
echo "[Info] SSH user is ${COLOR_YELLOW}${USER_NAME}${COLOR_RESET}"
echo "[Info] Customize SSH user in param 1 if connect fail"

if [ -z "$USER_NAME" ]; then
    printLog "ERROR" "SSH user is is empty"
    exit
fi
echo "###########################"

#####################################

syncMainSourceCode ${MAIN_DIRECTORY} ${MAIN_PROJECT}
echo "###########################"
checkAndExtractAARfiles ${MAIN_DIRECTORY}
echo "###########################"
getExternalTagList ${MAIN_DIRECTORY}
echo "###########################"

#set external project
syncExternalProject ${MAIN_DIRECTORY}
echo "###########################"
setExternalAntConfig ${MAIN_DIRECTORY}
echo "###########################"

echo "[Info] Finish deploy ${MAIN_DIRECTORY}"
