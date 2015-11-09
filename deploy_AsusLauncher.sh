#!/bin/bash

function syncSourceCode {
    local directory=$1
    local project=$2
    local branch=$3
    local tag=$4
    if [ ! -d "$directory" ]; then
        echo "[START] sync $directory"
        git clone ssh://${USER_NAME}@amax01:29418/${project} -b ${branch} ${directory}
        echo "[Success] sync $directory"
    elif [ ! -e "${directory}/AndroidManifest.xml" ]; then
        # abnormal status, re-sync project
        echo "[WARN] $directory already exist, but no source code, re-sync project..."
        if [ "${directory}" != "${DIRECTORY_AsusLauncher}" ]; then
            rm -rf ${directory}
            git clone ssh://${USER_NAME}@amax01:29418/${project} -b ${branch} ${directory}
            echo "[Success] sync $directory"
        fi
    else
        echo "[Info] $directory already exist"
        # rebase external project
        if [ "${directory}" != "${DIRECTORY_AsusLauncher}" ]; then
            cd ${directory}

            # repository changed, re-sync project
            if [ "$(git config --get remote.origin.url)" != "ssh://${USER_NAME}@amax01:29418/${project}" ]; then
                echo "[WARN] $directory already exist, but repository changed, re-sync project..."
                rm -rf ${directory}
                git clone ssh://${USER_NAME}@amax01:29418/${project} -b ${branch} ${directory}
                echo "[Success] sync $directory"
                cd ..
                return;
            fi

            # checkout build file to HEAD for rebase
            local array=("build.xml" "asus_build.xml" "project.properties" "build.gradle")
            for file in $(git status --porcelain 2>/dev/null| grep "^ M" | cut -d ' ' -f3)
            do
                local found=$(echo ${array[*]} | grep ${file})
                if [ "${found}" != "" ]; then
                    git checkout ${file}
                fi
            done

            # checkout to default if not currently on a branch
            if [ -z "$(git symbolic-ref --short -q HEAD)" ]; then
                git checkout ${branch}
            fi

            # sync to latest code base
            git pull --rebase

            # checkout to target tag
            if [ -n "${tag}" ]; then
                git checkout ${tag}
            fi
            cd ../
        fi
    fi
}

function syncLauncherSourceCode {
    local directory=$1
    local project=$2
    if [ ! -d "$directory" ]; then
        echo "[INFO] Choose you target branch:"
        local branch_options="AsusLauncher_1.4_dev AsusLauncher_1.4_beta AsusLauncher_1.4_play"
        select opt in ${branch_options}; do
            if [ "$opt" = "AsusLauncher_1.4_dev" ] || [ "$opt" = "AsusLauncher_1.4_beta" ] || [ "$opt" = "AsusLauncher_1.4_play" ]; then
                echo "[START] sync $directory"
                syncSourceCode ${directory} ${project} ${opt}
                echo "[Success] sync $directory"
                break
            else
                echo bad option
                exit
            fi
        done
    else
        echo "[WARN] sync fail, $directory exist"
    fi

    # fix no change id
    if [ -d "$directory" ]; then
        cp ${directory}/scripts/AntBuild/commit-msg ${directory}/.git/hooks/
    fi
}

function checkAndExtractAARfiles {
    local directory=$1
    # aar for ant build and Android Studio
    if ls -d ${directory}/*.aar ;then
        local aar_files=$(ls -d ${directory}/*.aar)
        for aar in ${aar_files}
        do
            local aar_for_studio=$(echo ${aar}|cut -d '.' -f1)/$(echo ${aar}|cut -d '/' -f2)
            if diff ${aar} ${aar_for_studio} >/dev/null ; then
                echo "[Info] $aar and $aar_for_studio same"
                continue;
            else
                echo "[Info] $aar and $aar_for_studio different"
            fi

            local aar_folder=$(echo ${aar}|cut -d '.' -f1)
            # rm assets copyed from unzipped .aar
            local copyed_assets=$(find ${aar_folder}/assets/ -type f | cut -d '/' -f4,5)
            for copyed_asset in ${copyed_assets}
            do
                rm -r ${directory}/assets/${copyed_asset}
                echo ${copyed_asset}
            done
            # remove any file except build.xml asus_build.xml project.projecties pre-load in aar folder
            all_files_in_aar_folder=$(ls ${aar_folder})
            local array=("build.xml" "asus_build.xml" "project.properties" "pre-load" "build.gradle")
            for file in ${all_files_in_aar_folder}
            do
                local found=$(echo ${array[*]} | grep ${file})
                if [ "${found}" != "" ]; then
                    echo "[Info] ignore ${file}"
                else
                    rm -rf ${aar_folder}/${file}
                fi
            done

            #unzip aar files
            find ${aar} -exec sh -c 'unzip -od "${1%.*}" "$1"' _ {} \;

            # move aar resource
            mkdir -p ${aar_folder}/src
            mkdir -p ${aar_folder}/pre-load
            mkdir -p ${aar_folder}/libs
            cp ${aar_folder}/*.jar ${aar_folder}/libs/
            for nativeso in $(ls ${aar_folder}/jni)
            do
                cp -arp ${aar_folder}/jni/${nativeso} ${aar_folder}/libs/
            done
            export INTERNAL_PROJECTS=$(echo ${INTERNAL_PROJECTS} ${aar_folder})
            cp -arp ${aar_folder}/assets/* ${directory}/assets/
            # cp aar for Android Studio
            cp ${aar} ${aar_folder}/
        done
    else
        echo "[Info] Don't have AAR files"
    fi
}

function syncExternalProject {
    local directory=$1

    if [ -d "$directory" ]; then
        local tag_array=$(echo ${EXTERNAL_TAG_LIST} | tr " " "\n")
        source ${directory}/scripts/AntBuild/external/sync.conf
        for dir in $(ls -d ${directory}/scripts/AntBuild/external/*/)
        do
            local dirName=$(echo ${dir}|cut -d '/' -f5)
            local projectName=$(echo ${dirName}|cut -d '_' -f1) # remove version, e.g. _1.0
            eval directory=DIRECTORY_\${projectName}
            eval branch=BRANCH_\${projectName}
            eval project=PROJECT_\${projectName}

            local tag=$(printf -- '%s\n' "${tag_array[@]}" | grep ${projectName})

            syncSourceCode ${!directory} ${!project} ${!branch} ${tag}
            echo "#########"
        done
    else
        echo "[WARN] sync external project fail, $directory exist"
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
                echo "[Success] setup external project $dirName ant build config"
            fi
        done
    fi
}

function getExternalTagList {
    local directory=$1

    cd ${directory}
    echo "[Info] Current branch tag is $(git describe --abbrev=0)"
    echo "[Info] Type the tag that you want to check (default use current, enter 0 to skip), followed by [ENTER]:"
    read input_tag
    if [ -n "${input_tag}" ]; then
        if [ "${input_tag}" = "0" ]; then
            cd ..
            return;
        else
            input_tag=${input_tag}
        fi

    else
        input_tag=$(git describe --abbrev=0)
    fi
    cd ..
    local launcher_project_name=$(echo ${input_tag} | cut -d '_' -f1)
    local launcher_project_version=$(echo ${input_tag} | cut -d '_' -f2)
    local launcher_version_first=$(echo ${launcher_project_version} | cut -d '.' -f1)
    local launcher_version_second=$(echo ${launcher_project_version} | cut -d '.' -f2)
    local launcher_version_third=$(echo ${launcher_project_version} | cut -d '.' -f3)
    local launcher_version_fourth=$(echo ${launcher_project_version} | cut -d '.' -f4)

    PATH_LAUNCHER_VERSION=$(echo ${launcher_project_name}/${launcher_version_first}.${launcher_version_second}.${launcher_version_third}/${launcher_version_fourth})

    if [ ! -d "${MOUNT_APK_POOL}" ]; then
        sudo mkdir ${MOUNT_APK_POOL}
        sudo mount -t cifs ${REMOTE_APK_POOL_PATH} ${MOUNT_APK_POOL}
    fi

    if [ -d "${MOUNT_APK_POOL}/${PATH_LAUNCHER_VERSION}" ]; then
        local version_code=$(grep VERSION_CODE ${MOUNT_APK_POOL}/${PATH_LAUNCHER_VERSION}/build_config/build.cfg | cut -d '=' -f2)
        local version_name=$(grep VERSION_NAME ${MOUNT_APK_POOL}/${PATH_LAUNCHER_VERSION}/build_config/build.cfg | cut -d '=' -f2)
        EXTERNAL_TAG_LIST=$(grep EXTERNAL_TAG_LIST ${MOUNT_APK_POOL}/${PATH_LAUNCHER_VERSION}/build_config/build.cfg | cut -d '=' -f2)

        echo "[Info] VERSION_CODE: ${version_code}"
        echo "[Info] VERSION_NAME: ${version_name}"
        echo "[Info] APK PATH in local: ${MOUNT_APK_POOL}/${PATH_LAUNCHER_VERSION}/"
        echo "[Info] APK PATH in remote: ${REMOTE_APK_POOL_PATH}/${PATH_LAUNCHER_VERSION}/"
        echo ""

        if [ -n "${EXTERNAL_TAG_LIST}" ]; then
            echo "[Info] EXTERNAL_TAG_LIST:"
            echo "${EXTERNAL_TAG_LIST}"
            echo "[Info] Enter the external tag that you want to checkout (default for all, enter 0 to skip), followed by [ENTER]:"
            read external_tag_checkout

            if [ -n "${external_tag_checkout}" ]; then
                if [ "${external_tag_checkout}" = "0" ]; then
                    EXTERNAL_TAG_LIST=""
                else
                    EXTERNAL_TAG_LIST=${external_tag_checkout}
                fi
            fi
        fi

    else
        echo "[WARN] wrong tag"
    fi

}

#####################################

echo "###########################"
echo "[Info] version 1.4"

#####################################

USER_NAME=$(git config user.email | cut -d '@' -f1 | awk '{print tolower($0)}')
if [ ! -z "${1}" ]; then
    USER_NAME=${1}
fi
echo "[Info] SSH user is $USER_NAME"
echo "[Info] Customize SSH user in param 1 if connect fail"

if [ -z "$USER_NAME" ]; then
    echo "[FATAL] SSH user is is empty"
    exit
fi
echo "###########################"

#####################################

DIRECTORY_AsusLauncher="AsusLauncher"
PROJECT_AsusLauncher="amax_L/packages/apps/AsusLauncher"

MOUNT_APK_POOL="/mnt/APK_Pool"
REMOTE_APK_POOL_PATH="//10.78.24.10/AMAX-release/APK_Pool"

#####################################

getExternalTagList ${DIRECTORY_AsusLauncher}
echo "###########################"
syncLauncherSourceCode ${DIRECTORY_AsusLauncher} ${PROJECT_AsusLauncher}
echo "###########################"
checkAndExtractAARfiles ${DIRECTORY_AsusLauncher}
echo "###########################"

#set external project
syncExternalProject ${DIRECTORY_AsusLauncher}
echo "###########################"
setExternalAntConfig ${DIRECTORY_AsusLauncher}
echo "###########################"

echo "[Info] Finish deploy AsusLauncher"

