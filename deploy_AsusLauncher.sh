#!/bin/bash

function syncSourceCode {
    local DIRECTORY=$1
    local PROJECT=$2
    local BRANCH=$3
    if [ ! -d "$DIRECTORY" ]; then
        echo "[START] sync $DIRECTORY"
        git clone ssh://${USER_NAME}@amax01:29418/${PROJECT} -b ${BRANCH} ${DIRECTORY}
        echo "[Success] sync $DIRECTORY"
    elif [ ! -e "${DIRECTORY}/AndroidManifest.xml" ]; then
        # abnormal status, re-sync project
        echo "[WARN] $DIRECTORY already exist, but no source code, re-sync project..."
        if [ "${DIRECTORY}" != "${DIRECTORY_AsusLauncher}" ]; then
            rm -rf ${DIRECTORY}
            git clone ssh://${USER_NAME}@amax01:29418/${PROJECT} -b ${BRANCH} ${DIRECTORY}
            echo "[Success] sync $DIRECTORY"
        fi
    else
        echo "[Info] $DIRECTORY already exist"
    fi
}

function syncLauncherSourceCode {
    local DIRECTORY=$1
    local PROJECT=$2
    if [ ! -d "$DIRECTORY" ]; then
        echo "Choose you target branch:"
        OPTIONS="AsusLauncher_1.4_dev AsusLauncher_1.4_beta AsusLauncher_1.4_play"
        select opt in ${OPTIONS}; do
            if [ "$opt" = "AsusLauncher_1.4_dev" ] || [ "$opt" = "AsusLauncher_1.4_beta" ] || [ "$opt" = "AsusLauncher_1.4_play" ]; then
                echo "[START] sync $DIRECTORY"
                syncSourceCode ${DIRECTORY} ${PROJECT} ${opt}
                echo "[Success] sync $DIRECTORY"
                break
            else
                echo bad option
                exit
            fi
        done
    else
        echo "[WARN] sync fail, $DIRECTORY exist"
    fi

    # fix no change id
    if [ -d "$DIRECTORY" ]; then
        cp ${DIRECTORY}/scripts/AntBuild/commit-msg ${DIRECTORY}/.git/hooks/
    fi
}

function checkAndExtractAARfiles {
    local DIRECTORY=$1
    # aar for ant build and Android Studio
    if ls -d ${DIRECTORY}/*.aar ;then
        AAR_FILES=$(ls -d ${DIRECTORY}/*.aar)
        for aar in ${AAR_FILES}
        do
            AAR_FOR_STUDIO=$(echo ${aar}|cut -d '.' -f1)/$(echo ${aar}|cut -d '/' -f2)
            if diff ${aar} ${AAR_FOR_STUDIO} >/dev/null ; then
                echo "[Info] $aar and $AAR_FOR_STUDIO same"
                continue;
            else
                echo "[Info] $aar and $AAR_FOR_STUDIO different"
            fi

            AAR_FOLDER=$(echo ${aar}|cut -d '.' -f1)
            # rm assets copyed from unzipped .aar
            COPYED_ASSETS=$(find ${AAR_FOLDER}/assets/ -type f | cut -d '/' -f4,5)
            for COPYED_ASSET in ${COPYED_ASSETS}
            do
                rm -r ${DIRECTORY}/assets/${COPYED_ASSET}
                echo ${COPYED_ASSET}
            done
            # remove any file except build.xml asus_build.xml project.projecties pre-load in aar folder
            ALL_FILES_IN_AAR_FOLDER=$(ls ${AAR_FOLDER})
            ARRAY=("build.xml" "asus_build.xml" "project.properties" "pre-load" "build.gradle")
            for file in ${ALL_FILES_IN_AAR_FOLDER}
            do
                FOUND=$(echo ${ARRAY[*]} | grep ${file})
                if [ "${FOUND}" != "" ]; then
                    echo "ignore ${file}"
                else
                    rm -rf ${AAR_FOLDER}/${file}
                fi
            done

            #unzip aar files
            find ${aar} -exec sh -c 'unzip -od "${1%.*}" "$1"' _ {} \;

            # move aar resource
            mkdir -p ${AAR_FOLDER}/src
            mkdir -p ${AAR_FOLDER}/pre-load
            mkdir -p ${AAR_FOLDER}/libs
            cp ${AAR_FOLDER}/*.jar ${AAR_FOLDER}/libs/
            for nativeso in $(ls ${AAR_FOLDER}/jni)
            do
                cp -arp ${AAR_FOLDER}/jni/${nativeso} ${AAR_FOLDER}/libs/
            done
            export INTERNAL_PROJECTS=$(echo ${INTERNAL_PROJECTS} ${AAR_FOLDER})
            cp -arp ${AAR_FOLDER}/assets/* ${DIRECTORY}/assets/
            # cp aar for Android Studio
            cp ${aar} ${AAR_FOLDER}/
        done
    else
        echo "[Info] Don't have AAR files"
    fi
}

function syncExternalProject {
    local DIRECTORY=$1
    if [ -d "$DIRECTORY" ]; then
        source ${DIRECTORY}/scripts/AntBuild/external/sync.conf
        for dir in $(ls -d ${DIRECTORY}/scripts/AntBuild/external/*/)
        do
            local dirName=$(echo ${dir}|cut -d '/' -f5)
            local projectName=$(echo ${dirName}|cut -d '_' -f1) # remove version, e.g. _1.0
            eval directory=DIRECTORY_\${projectName}
            eval branch=BRANCH_\${projectName}
            eval project=PROJECT_\${projectName}
            syncSourceCode ${!directory} ${!project} ${!branch}
        done
    else
        echo "[WARN] sync external project fail, $DIRECTORY exist"
    fi
}

function setExternalAntConfig {
    local DIRECTORY=$1
    if [ -d "$DIRECTORY" ]; then
        for dir in $(ls -d ${DIRECTORY}/scripts/AntBuild/external/*/)
        do
            local dirName=$(echo ${dir}|cut -d '/' -f5)
            if [ -d "$dirName" ]; then
                cp -r ${DIRECTORY}/scripts/AntBuild/external/${dirName} .
                echo "[Success] setup external project $dirName ant build config"
            fi
        done
    fi
}

#####################################

echo "[Info] version 1.3"

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

#####################################

DIRECTORY_AsusLauncher="AsusLauncher"
PROJECT_AsusLauncher="amax_L/packages/apps/AsusLauncher"

#####################################

syncLauncherSourceCode ${DIRECTORY_AsusLauncher} ${PROJECT_AsusLauncher}
checkAndExtractAARfiles ${DIRECTORY_AsusLauncher}

#set external project
syncExternalProject ${DIRECTORY_AsusLauncher}
setExternalAntConfig ${DIRECTORY_AsusLauncher}

echo "[Info] Finish deploy AsusLauncher"

