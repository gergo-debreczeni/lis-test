#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved. 
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0  
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################


ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"
CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}



UpdateSummary()
{
    echo $1 >> ~/summary.log
}

UpdateTestState()
{
    echo $1 > ~/state.txt
}


# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: in ${CONSTANTS_FILE} file"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

#
# Create the state.txt file so ICA knows we are running
#
UpdateTestState $ICA_TESTRUNNING

#
# Cleanup any old summary.log files
#
if [ -e ~/summary.log ]; then
    LogMsg "Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

#
# Make sure the constants.sh file exists
#
if [ ! -e ./constants.sh ];
then
    echo "Cannot find constants.sh file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#Check for Testcase count
if [ ! ${TC_COVERED} ]; then
    LogMsg "Error: The TC_COVERED variable is not defined."
    echo "Error: The TC_COVERED variable is not defined." >> ~/summary.log
    UpdateTestState "TestAborted"
    exit 1
fi

echo "Covers : ${TC_COVERED}" >> ~/summary.log

# Count the number of SCSI= and IDE= entries in constants
#
diskCount=0
for entry in $(cat ./constants.sh)
do
    # Convert to lower case
    lowStr="$(tr '[A-Z]' '[a-z' <<<"$entry")"

    # does it start wtih ide or scsi
    if [[ $lowStr == ide* ]];
    then
        diskCount=$((diskCount+1))
    fi

    if [[ $lowStr == scsi* ]];
    then
        diskCount=$((diskCount+1))
    fi
done

echo "constants disk count = $diskCount"

#
# Compute the number of sd* drives on the system.
#
sdCount=0
for drive in $(find /sys/devices/ -name sd* | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
    sdCount=$((sdCount+1))
done

#
# Subtract the boot disk from the sdCount, then make
# sure the two disk counts match
#
sdCount=$((sdCount-1))
echo "/sys/devices disk count = $sdCount"

if [ $sdCount != $diskCount ];
then
    echo "constants.sh disk count ($diskCount) does not match disk count from /sys/devices ($sdCount)"
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

#
# For each drive, run fdisk -l and extract the drive
# size in bytes.  The setup script will add Fixed
#.vhd of size 1GB, and Dynamic .vhd of 137GB
#
FixedDiskSize=1073741824
Disk4KSize=4096
DynamicDiskSize=136365211648

firstDrive=1
for drive in $(find /sys/devices/ -name sd* | grep 'sd.$' | sed 's/.*\(...\)$/\1/')
do
    #
    # Skip /dev/sda
    #
  if [ ${drive} = "sda" ];
    then
        continue
    fi
    driveName="/dev/${drive}"
    fdisk -l $driveName > fdisk.dat 2> /dev/null
    # Format the Disk and Create a file system , Mount and create file on it . 
    (echo d;echo;echo w)|fdisk  $driveName
    (echo n;echo p;echo 1;echo;echo;echo w)|fdisk  $driveName
    if [ "$?" = "0" ]; then
    sleep 5
    mkfs.ext3  ${driveName}1
    if [ "$?" = "0" ]; then
        LogMsg "mkfs.ext3   ${driveName}1 successful..."
        mount   ${driveName}1 /mnt
                if [ "$?" = "0" ]; then
                LogMsg "Drive mounted successfully..."
                mkdir /mnt/Example
                dd if=/dev/zero of=/mnt/Example/data bs=10M count=50
                if [ "$?" = "0" ]; then
                    LogMsg "Successful created directory /mnt/Example"
                    LogMsg "Listing directory: ls /mnt/Example"
                    ls /mnt/Example
                    df -h
                    umount /mnt
                    if [ "$?" = "0" ]; then
                        LogMsg "Drive unmounted successfully..."
                 fi
                    LogMsg "Disk test completed for ${driveName}1"
                    echo "Disk test is completed for ${driveName}1" >> ~/summary.log
                else
                    LogMsg "Error in creating directory /mnt/Example..."
                    echo "Error in creating directory /mnt/Example" >> ~/summary.log
                    UpdateTestState $ICA_TESTFAILED
                    exit 60
                fi
            else
                LogMsg "Error in mounting drive..."
                echo "Drive mount : Failed" >> ~/summary.log
                UpdateTestState $ICA_TESTFAILED
                exit 70
            fi
        else
            LogMsg "Error in creating file system.."
            echo "Creating Filesystem : Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 80
        fi
    else
        LogMsg "Error in executing fdisk  ${driveName}1"
        echo "Error in executing fdisk  ${driveName}1" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 90
    fi  


    #
    # The fdisk output appears as one word on each line of the file
    # The 6th element (index 5) is the disk size in bytes
    #
    elementCount=0
    for word in $(cat fdisk.dat)
    do
        elementCount=$((elementCount+1))
        if [ $elementCount == 5 ];
        then
            if [ $word -ne $FixedDiskSize -a $word -ne $DynamicDiskSize -a $word -ne $Disk4KSize ];
            then
                echo "Warn: $driveName has an unknown disk size: $word"
		        echo "Warn: $driveName has an unknown disk size: $word" >> ~/summary.log
            fi
         fi
    done
done

UpdateTestState $ICA_TESTCOMPLETED

exit 0

