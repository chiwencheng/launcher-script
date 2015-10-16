#!/bin/bash

function syncSourceCode {
    local DIRECTORY=$1
    local PROJECT=$2
    local BRANCH=$3
    if [ ! -d "$DIRECTORY" ]; then
        echo "[START] sync $DIRECTORY"
        git clone ssh://${USER_NAME}@amax01:29418/${PROJECT} -b ${BRANCH} ${DIRECTORY}
        echo "[Success] sync $DIRECTORY"
    else
        echo "[WARN] sync fail, $DIRECTORY exist"
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
            COPYED_ASSETS=$(find ${AAR_FOLDER}/assets/ -type f | cut -d '/' -f4)
            for COPYED_ASSET in ${COPYED_ASSETS}
            do
                rm -r ${DIRECTORY}/assets/${COPYED_ASSET}
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

function setAntConfig {
    local DIRECTORY=$1
    if [ -d "$DIRECTORY" ]; then
        cp -r config/${DIRECTORY}/* ${DIRECTORY}/
        mkdir -p ${DIRECTORY}/pre-load
        echo "[Success] setup ant build for $DIRECTORY"
    fi
}

function setAntConfigByBranch {
    local BRANCH=$1
    local DIRECTORY=$2
    if [ -d "$DIRECTORY" ]; then
        cp -r config/${BRANCH}/* ${DIRECTORY}/
        cp -r config/ant/ ${DIRECTORY}/
        echo "[Success] setup ant build for $DIRECTORY to $BRANCH"
    fi
}

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

#external project
DIRECTORY_UserVoiceSDK="UserVoiceSDK_1.1"
PROJECT_UserVoiceSDK="amax_L/packages/sharelibs/UserVoiceSDK"
BRANCH_UserVoiceSDK="UserVoiceSDK_1.0_Android-5.0"

DIRECTORY_AndroidSupportV7Recyclerview="AndroidSupportV7Recyclerview_23.0"
PROJECT_AndroidSupportV7Recyclerview="amax_L/packages/sharelibs/Android_Support_V7_Recyclerview"
BRANCH_AndroidSupportV7Recyclerview="android_support_v7_recyclerview_23.0.1"

DIRECTORY_AndroidSupportV7Appcompat="AndroidSupportV7Appcompat_23.0"
PROJECT_AndroidSupportV7Appcompat="amax_L/packages/sharelibs/Android_Support_V7_Appcompat"
BRANCH_AndroidSupportV7Appcompat="android_support_v7_appcompat_23.0.1"

DIRECTORY_AndroidSupportV7Cardview="AndroidSupportV7Cardview_23.0"
PROJECT_AndroidSupportV7Cardview="amax_L/packages/sharelibs/Android_Support_V7_Cardview"
BRANCH_AndroidSupportV7Cardview="android_support_v7_cardview_23.0.1"

DIRECTORY_AndroidDesignSupport="AndroidDesignSupport_23.0"
PROJECT_AndroidDesignSupport="amax_L/packages/sharelibs/Android_Support_Design"
BRANCH_AndroidDesignSupport="android_support_design_23.0.1"

DIRECTORY_TaskContract="TaskContract_2.0"
PROJECT_TaskContract="amax_L/packages/sharelibs/TaskContract"
BRANCH_TaskContract="AMAX_android-L"

DIRECTORY_ZenNow="ZenNow_1.0"
PROJECT_ZenNow="amax_L/packages/sharelibs/ZenNow"
BRANCH_ZenNow="ZenNow_1.0"

DIRECTORY_AsusUi="AsusUi_0.8"
PROJECT_AsusUi="amax_L/packages/sharelibs/AsusUi"
BRANCH_AsusUi="AMAX_android-L"

#####################################
echo ""
echo "[Info] Please checkout to target branch first."
echo "[Info] This script will not checkout branch if AsusLauncher exist."
echo ""

echo "Choose you target branch:"
OPTIONS="AsusLauncher_1.4_dev AsusLauncher_1.4_beta AsusLauncher_1.4_play AsusLauncher_1.4_dev-zenuinow-570619"
select opt in ${OPTIONS}; do
    if [ "$opt" = "AsusLauncher_1.4_dev" ] || [ "$opt" = "AsusLauncher_1.4_beta" ]; then
        syncSourceCode ${DIRECTORY_AsusLauncher} ${PROJECT_AsusLauncher} ${opt}
        setAntConfig ${DIRECTORY_AsusLauncher}
        setAntConfigByBranch "AsusLauncher_1.4_beta" ${DIRECTORY_AsusLauncher}
        checkAndExtractAARfiles ${DIRECTORY_AsusLauncher}
        #set external project
        syncSourceCode ${DIRECTORY_UserVoiceSDK} ${PROJECT_UserVoiceSDK} ${BRANCH_UserVoiceSDK}
        setAntConfig ${DIRECTORY_UserVoiceSDK}
        syncSourceCode ${DIRECTORY_AndroidSupportV7Recyclerview} ${PROJECT_AndroidSupportV7Recyclerview} ${BRANCH_AndroidSupportV7Recyclerview}
        setAntConfig ${DIRECTORY_AndroidSupportV7Recyclerview}
        syncSourceCode ${DIRECTORY_AndroidSupportV7Appcompat} ${PROJECT_AndroidSupportV7Appcompat} ${BRANCH_AndroidSupportV7Appcompat}
        setAntConfig ${DIRECTORY_AndroidSupportV7Appcompat}
        syncSourceCode ${DIRECTORY_AndroidSupportV7Cardview} ${PROJECT_AndroidSupportV7Cardview} ${BRANCH_AndroidSupportV7Cardview}
        setAntConfig ${DIRECTORY_AndroidSupportV7Cardview}
        syncSourceCode ${DIRECTORY_AndroidDesignSupport} ${PROJECT_AndroidDesignSupport} ${BRANCH_AndroidDesignSupport}
        setAntConfig ${DIRECTORY_AndroidDesignSupport}
        break
    elif [ "$opt" = "AsusLauncher_1.4_play" ]; then
        syncSourceCode ${DIRECTORY_AsusLauncher} ${PROJECT_AsusLauncher} ${opt}
        setAntConfig ${DIRECTORY_AsusLauncher}
        setAntConfigByBranch ${opt} ${DIRECTORY_AsusLauncher}
        checkAndExtractAARfiles ${DIRECTORY_AsusLauncher}
        #set external project
        syncSourceCode ${DIRECTORY_UserVoiceSDK} ${PROJECT_UserVoiceSDK} ${BRANCH_UserVoiceSDK}
        setAntConfig ${DIRECTORY_UserVoiceSDK}
        break
    elif [ "$opt" = "AsusLauncher_1.4_dev-zenuinow-570619" ]; then
        syncSourceCode ${DIRECTORY_AsusLauncher} ${PROJECT_AsusLauncher} ${opt}
        setAntConfig ${DIRECTORY_AsusLauncher}
        setAntConfigByBranch ${opt} ${DIRECTORY_AsusLauncher}
        checkAndExtractAARfiles ${DIRECTORY_AsusLauncher}
        #set external project
        syncSourceCode ${DIRECTORY_UserVoiceSDK} ${PROJECT_UserVoiceSDK} ${BRANCH_UserVoiceSDK}
        setAntConfig ${DIRECTORY_UserVoiceSDK}
        syncSourceCode ${DIRECTORY_TaskContract} ${PROJECT_TaskContract} ${BRANCH_TaskContract}
        setAntConfig ${DIRECTORY_TaskContract}
        syncSourceCode ${DIRECTORY_ZenNow} ${PROJECT_ZenNow} ${BRANCH_ZenNow}
        setAntConfig ${DIRECTORY_ZenNow}
        syncSourceCode ${DIRECTORY_AsusUi} ${PROJECT_AsusUi} ${BRANCH_AsusUi}
        setAntConfig ${DIRECTORY_AsusUi}
        break
    else
        echo bad option
        exit
    fi
done
echo "[Info] Finish deploy AsusLauncher"

