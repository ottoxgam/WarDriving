#!/bin/bash
#
# This bash script is designed to automate the collection and uploading of WarDriving data.
# WarDriving is the act of collecting locational and technical details of WiFi hotspots.
# The data can be uploaded to wigle.net, pi-resource.com and/or a FTP server of your choosing.
#
# This script performs the following actions:
#	1. Check directory structure exists, if it doesn't, creat it
#	2. Stop kismet server to force it to write out the log files
#	3. Move Kismet log files to an alternative directory
#	4. Start Kismet Server
#	5. Check is any files that require compression, if so, compress them
#	6. Check if we have files to upload and an internet connection. If so, upload them
#	8. Check disk space, delete old logs if running low
#	9. Wait a set amount of time before restarting this script
#
# Author: pi-resource.com
# Version: 1.2
# Date: 2017-11-15

#############
# Constants #
#############
DEFAULT=$'\e[0m'
BOLD=$'\e[1m'
UNDERLINE=$'\e[4m'
RED=$'\e[0;91m'
GREEN=$'\e[0;92m'
YELLOW=$'\e[0;93m'
BLUE=$'\e[0;94m'
MAGENTA=$'\e[0;95m'
CYAN=$'\e[0;96m'

#############
# Functions #
#############

# Directory structure expected:
# ~/WarDriving/
# ~/WarDriving/logs
# ~/WarDriving/logs/kismet
# ~/WarDriving/logs/compressed
# ~/WarDriving/logs/uploaded
# ~/WarDriving/wigle
function createDirStructure {
	printf "\n%sChecking directory structure: " $MAGENTA
        mkdir -p /home/pi/WarDriving/logs/kismet
        mkdir -p /home/pi/WarDriving/logs/preprocessed
        mkdir -p /home/pi/WarDriving/logs/compressed
        mkdir -p /home/pi/WarDriving/cookies
	printf "%sDONE" $GREEN
}

# Check internet connection
# returns: 0 if connection available
#          1 if no connection
function checkOnline {
	# Declare an array with websites to be checked.
	declare -a arr=("http://www.google.com" "http://www.yahoo.com" "http://www.microsoft.com" "http://www.facebook.com")

	# Loop through them and if any of them are active, then an internet connection is present.
	for i in "${arr[@]}"
	do
		if wget -q --spider "$i"; then
			return 0
		fi
	done

	# If we get this far, and none of the sites have returned a sucessful response, then the internet isn't available
	return 1
}

# Check if Kismet Server is running
# returns: 0 if running
#          1 if not running
function checkKismetRunning {
	if pgrep -x "kismet_server" > /dev/null
	then
	    return 0
	else
	    return 1
	fi
}

# Wait function
# arg1 = time to wait in seconds
# arg2 = text to place before countdown
# arg3 = text to place after countdown
function countDown {
	if [ "$1" -lt  1 ]; then
		return
        else
		printf '\n'
		for (( count=$1; count>=0; count-- ))
		do
			printf "\r%s %s %s" "$2" "$count" "$3"
			sleep 1
		done
        fi
}

# Prints the intro out to screen.
function displayIntro {
	printf "\n%s%sWarDriving by pi-resource" $RED $UNDERLINE
	printf "\n%sThis bash script automates the collection of WarDriving data and can upload the data to %s%swww.wigle.net%s, %s%swww.pi-resource.com%s and a FTP server if configured to do so." $DEFAULT $BLUE $UNDERLINE $DEFAULT $BLUE $UNDERLINE $DEFAULT
	printf "\n%sIt uses Kismet to log WiFi hotspots. After a set amount of time Kismet is restarted which forces Kismet to write its log files." $DEFAULT
	printf "\n%sOnce the Kismet Server has restarted, the war driving files from the previous instance are compressed an attempt made to upload them." $DEFAULT
	printf "\n%sAny Comments, questions or suggested improvements, please visit %s%shttp://www.pi-resource.com" $DEFAULT $BLUE $UNDERLINE
	printf "\n%sVersion: 1.1" $DEFAULT
	printf "\n%sRelease date: 2017-11-15" $DEFAULT
}

# Prints the configuration out to screen.
function displayConfig {
	printf "\n%s%sConfiguration" $MAGENTA $UNDERLINE
	printf "\n%s    On start-up, pause for %s%s%s%s%s second(s) to allow the GPS to get a fix" $DEFAULT $YELLOW $BOLD $UNDERLINE $timerGps $DEFAULT
	printf "\n%s    Save and compress logs every %s%s%s%s%s minute(s)" $DEFAULT $YELLOW $BOLD $UNDERLINE $(( timerRepeat / 60 )) $DEFAULT

	printf "\n%s    Upload to %s%swww.wigle.net%s? "  $DEFAULT $BLUE $UNDERLINE $DEFAULT
	if [ $wigleUpload -eq 1 ]; then
		printf "%s%s%sYES" $YELLOW $BOLD $UNDERLINE
		printf "\n%s       -- Wigle User: " $DEFAULT
		if [ -z "$wigleUserName" ] && [ -z "$wiglePassword" ]; then
			printf "%s%s%sAnonymous%s (Wigle username and password not set)" $YELLOW $BOLD $UNDERLINE $DEFAULT
		elif [ -z $wigleUserName ]; then
			printf "%s%s%sAnonymous%s (Wigle username not set)" $YELLOW $BOLD $UNDERLINE $RED
		elif [ -z $wiglePassword ]; then
			printf "%s%s%sAnonymous%s (Wigle password not set)" $YELLOW $BOLD $UNDERLINE $RED
		else
			printf "%s%s%s%s" $YELLOW $BOLD $UNDERLINE $wigleUserName
			printf "\n%s       -- Wigle Password: %s%s%s********" $DEFAULT $YELLOW $BOLD $UNDERLINE
		fi
	else
		printf "%s%s%sNO" $YELLOW $BOLD $UNDERLINE
	fi

	printf "\n%s    Upload to %s%swww.pi-resource.com%s? "  $DEFAULT $BLUE $UNDERLINE $DEFAULT
	if [ $piResourceUpload -gt 0 ]; then
		printf "%s%s%sYES" $YELLOW $BOLD $UNDERLINE
	else
		printf "%s%s%sNO" $YELLOW $BOLD $UNDERLINE
	fi

	printf "\n%s    Upload to a FTP server of your choosing? " $DEFAULT
	if [ $ftpUpload -gt 0 ]; then
		printf "%s%s%sYES" $YELLOW $BOLD $UNDERLINE

		printf "\n%s        -- FTP Host: " $DEFAULT
		if [ -z "$ftpHost" ]; then
			printf "%sERROR%s - FTP Host not set" $RED $DEFAULT
		else
			printf "%s%s%s%s%s" $YELLOW $BOLD $UNDERLINE $ftpHost $DEFAULT
		fi

		printf "\n%s        -- FTP Remote Directory: " $DEFAULT
		if [ -z "$ftpRemoteDirectory" ]; then
			printf "%sERROR%s - FTP Remote directory not set" $RED $DEFAULT
		else
			printf "%s%s%s%s%s" $YELLOW $BOLD $UNDERLINE $ftpRemoteDirectory $DEFAULT
		fi

		printf "\n%s        -- FTP Connection Timeout: " $DEFAULT
		if [ -z "$ftpConnectTimeout" ]; then
			printf "%sERROR%s - FTP Connection timeout not set" $RED $DEFAULT
		else
			printf "%s%s%s%s%s second(s)" $YELLOW $BOLD $UNDERLINE $ftpConnectTimeout $DEFAULT
		fi

		printf "\n%s        -- FTP Username: " $DEFAULT
		if [ -z "$ftpUser" ]; then
			printf "%sWARNING%s - FTP Username not set. will try Anonymous login" $CYAN $DEFAULT
		else
			printf "%s%s%s%s%s" $YELLOW $BOLD $UNDERLINE $ftpUser $DEFAULT
		fi

		printf "\n%s        -- FTP Password: " $DEFAULT
		if [ -z "$ftpPassword" ]; then
			printf "%sWARNING%s - FTP Password not set" $CYAN $DEFAULT
		else
			printf "%s%s%s********" $YELLOW $BOLD $UNDERLINE
		fi
	else
		printf "%s%s%sNO" $YELLOW $BOLD $UNDERLINE
	fi

	printf "\n%s    Files to be deleted after upload? "  $DEFAULT
	if [ $deleteAfterUpload -eq 1 ]; then
		printf "%s%s%sYES" $YELLOW $BOLD $UNDERLINE
	else
		printf "%s%s%sNO" $YELLOW $BOLD $UNDERLINE
	fi

	printf "\n%s    Files will be deleted even if not uploaded once used disk space exceeds: %s%s%s%s%s %%"  $DEFAULT $YELLOW $BOLD $UNDERLINE "$filesystemUsedSpaceLimit" $DEFAULT
}

function UploadToWigle {
	
	# Variable which is set to zero after the first upload, so the header is only printed out to screen the once.
	firstWigleUpload=1

	#define an array to capture file names to be uploaded to Wigle
	filesWigle=()

	#identify files with the first charactor set to Y
	for file in /home/pi/WarDriving/logs/compressed/*
	do
		baseFileName=$(basename "$file")
		if [[ ${baseFileName:0:1} == "Y" ]]; then
			filesWigle+=("$file")
		fi
	done

	if [ ${#filesWigle[@]} -ne 0 ]; then            # Check if the array is empty, true if non-zero returned.
		# Log into Wigle if username and password are present
		if [ -n "$wigleUserName" ] && [ -n "$wiglePassword" ]; then
			printf "\n%sLogging into wigle.net: " $MAGENTA
			loginResponse=$(curl --silent --max-time 5 -A 'pi-resource' -c /home/pi/WarDriving/cookies/wigle.txt -d 'credential_0='$wigleUserName'&credential_1='$wiglePassword 'https://api.wigle.net/api/v2/login')

			# Check login was successful
			if [[ "$loginResponse" == *"\"success\":true"* ]]; then
				printf "%sSUCCESS" $GREEN
			else
				printf "%sERROR%s - Login to Wigle failed. Proceeding to upload as Anonymous. Error returned: %s" $RED $DEFAULT $loginResponse
			fi

		fi

		# Upload files to Wigle
		for file in "${filesWigle[@]}"
		do
			baseFileName=$(basename "$file")
			
			if [ $firstWigleUpload -eq 1 ]; then 
				printf "\n%sUploading %s%s%i%s files to Wigle:" $MAGENTA $YELLOW $UNDERLINE ${#filesWigle[@]} $MAGENTA
				let firstWigleUpload=0
			fi
						
			printf "\n      %s%s " $DEFAULT "$baseFileName"
			uploadResponse=$(curl --silent --max-time 60 -A 'pi-resource' -b /home/pi/WarDriving/cookies/wigle.txt -F "observer=$wigleUserName" -F "file=@$file" https://api.wigle.net/api/v2/file/upload)
			
			# Check upload was successful
			if [[ "$uploadResponse" == *"\"success\":true"* ]]; then
				printf " %sSUCCESS" $GREEN
			
				#rename file to replace the Y flag with an N flag
				newBaseFileName="N${baseFileName:1}"
				mv -f "$file" "$(dirname "$file")"/"$newBaseFileName"				
			else
				printf "%s ERROR%s - Upload to Wigle failed. %s" $RED $DEFAULT $uploadResponse
			fi			
		done
	fi
}

function UploadToPiResource {
	
	#define an array to capture file names to be uploaded to PiResource
	filesPiResource=()

	#identify files with the second charactor set to Y	
	for file in /home/pi/WarDriving/logs/compressed/*
	do
		baseFileName=$(basename "$file")
		if [[ ${baseFileName:1:1} == "Y" ]]; then
			filesPiResource+=("$file")
		fi
	done
		
	if [ ${#filesPiResource[@]} -ne 0 ]; then            # Check if the array is empty, true if non-zero returned.		
		printf "\n%sUploading %s%i%s files to %swww.pi-resource.com%s:" $MAGENTA $YELLOW$UNDERLINE ${#filesPiResource[@]} $MAGENTA $BLUE$UNDERLINE $MAGENTA
		
		# Upload files to PiResource
		for file in "${filesPiResource[@]}"
		do
		
			baseFileName=$(basename "$file")
			baseFileNameWithoutFlags="${baseFileName:4}"  #base file name with the first 3 Flags and dot removed.

			printf "\n      %s%s " $DEFAULT "$baseFileName"

			#FTP Upload
			if curl --silent --connect-timeout 3 --max-time 60 --upload-file "$file" --user pi-resource-WD:zpIdL%yT9Bs^sAib34PKH ftp.pi-resource.com/"$baseFileNameWithoutFlags"; then
				printf "%sSUCCESS" $GREEN

				#rename file to replace the second flag with an N flag
				newBaseFileName="${baseFileName:0:1}N${baseFileName:2}"
				mv -f "$file" "$(dirname "$file")"/"$newBaseFileName"
			else
				curlExitCode=$?
				if [ $curlExitCode -eq 28 ]; then
					printf "%sERROR%s - FTP server at www.pi-resource.com is busy or not currently available, please try again later." $RED $DEFAULT
				else
					printf "%sERROR%s - curl exit code %s (tip - use 'man curl' to look it up)" $RED $DEFAULT $curlExitCode
				fi
			fi
		done
	fi
}

function UploadToFTP {

	#define an array to capture file names to be uploaded to users custom FTP server
	filesFTP=()

	#identify files with the third charactor set to Y	
	for file in /home/pi/WarDriving/logs/compressed/*
	do
		baseFileName=$(basename "$file")
		if [[ ${baseFileName:2:1} == "Y" ]]; then
			filesFTP+=("$file")
		fi
	done
	
	if [ ${#filesFTP[@]} -ne 0 ]; then            # Check if the array is empty, true if non-zero returned.		
		printf "\n%sUploading %s%i%s files to %s%s%s:" $MAGENTA $YELLOW$UNDERLINE ${#filesFTP[@]} $MAGENTA $BLUE$UNDERLINE "$ftpHost" $MAGENTA
	
		# Upload files to FTP Server
		for file in "${filesFTP[@]}"
		do	

			baseFileName=$(basename "$file")
			baseFileNameWithoutFlags="${baseFileName:4}"  #base filename with the first 3 Flags and dot removed.

			printf "\n      %s%s " $DEFAULT "$baseFileName"

			#FTP Upload
			if curl  --silent --connect-timeout $ftpConnectTimeout --max-time 60 --upload-file "$file" --user $ftpUser:$ftpPassword $ftpHost$ftpRemoteDirectory"$baseFileNameWithoutFlags"; then
				printf "%sSUCCESS" $GREEN

				#rename file to replace the third flag with an N flag
				newBaseFileName="${baseFileName:0:2}N${baseFileName:3}"
				mv -f "$file" "$(dirname "$file")"/"$newBaseFileName"
			else
				curlExitCode=$?
				printf "%sERROR%s - FTP upload failed, curl exit code %s (tip - use 'man curl' to look it up)" $RED $DEFAULT $curlExitCode
			fi
		done
	fi
}

###########################
# Start of main programme #
###########################

# Load configuration file
cfg_file="WarDriving.cfg"
if [ -f "$cfg_file" ]
then
	source "$cfg_file"
else
	printf "%sERROR%s - Configuration file not found. Expecting %s/%s" $RED $DEFAULT $PWD $cfg_file
	printf "\nExiting ...\n"
	exit 1
fi

####################
# 0. Display Intro #
####################
displayIntro
printf '\n'
displayConfig

# Initial Sleep to allow GPS to gain a fix. Suggest 60 seconds.
printf '\n'
countDown $timerGps $DEFAULT"Waiting" "seconds before starting Kismet server to allow the GPS a chance to get a fix    "

# Start infinite loop with no exit conditions.
while :
do

	###############################################################
	# 1. Check directory structur exists, if it doesn't, creat it #
	###############################################################
	createDirStructure

	#########################
	# 2. Stop Kismet Server #
	#########################
	printf "\n%sChecking if Kismet Server is running: " $MAGENTA
	if checkKismetRunning; then
		printf "%sKismet Server is running, therefore killing the server. " $DEFAULT
		sudo pkill kismet_server
		while : ; do
			sleep 1
			if ! checkKismetRunning; then
				break
			fi
		done
		printf "%sDONE%s - Kismet Server killed" $GREEN $DEFAULT
	else
		printf "%sDONE%s - Kismet Server was not running" $GREEN $DEFAULT
	fi

	####################################################################################################################
	# 3. Move kismet log files to an alternative directory so that they can be processed whilst Kismet Server restarts #
	####################################################################################################################
	printf "\n%sChecking if there are kismet log files to move: " $MAGENTA
	let filecounter1=$(find /home/pi/WarDriving/logs/kismet/ -maxdepth 1 -type f | grep -cv '/\.')
	if [ $filecounter1 -gt 0 ]; then
		mv -f /home/pi/WarDriving/logs/kismet/* /home/pi/WarDriving/logs/preprocessed/
		printf "%sDONE%s - %s Log file(s) moved" $GREEN $DEFAULT "$filecounter1"
	else
		printf "%sDONE%s - No Log files required moving" $GREEN $DEFAULT
	fi

	##########################
	# 4. Start kismet server #
	##########################
	printf "\n%sStarting Kismet Server: %s" $MAGENTA $DEFAULT
    sudo kismet_server -s -p /home/pi/WarDriving/logs/kismet > /dev/null &
	sleep 1
	if checkKismetRunning; then
		printf "%sSUCCESS%s - Kismet Server Started" $GREEN $DEFAULT
	else
		printf "%sERROR%s - Unable to start Kismet, check kismet logs" $RED $DEFAULT
	fi

	##########################################################################
	#  5. Check if any files that require compression, if so, compress files #
	##########################################################################
	printf "\n%sChecking if there are kismet log files that require compression: " $MAGENTA
	let filecounter2=$(find /home/pi/WarDriving/logs/preprocessed/ -maxdepth 1 -type f | grep -cv '/\.')
	if [ $filecounter2 -gt 0 ]; then

		# Set flag to be used in filename which will identify which sites to upload to. Format:
		#      First  charactor, upload to Wigle?         Y=Yes, anything else = No
		#      Second charactor, upload to pi-resource?   Y=Yes, anything else = No
		#      Third  charactor, upload to an FTP server? Y=Yes, anything else = No
		flag='NNN'
		if [ $wigleUpload -gt 0 ]; then
			flag="Y${flag:1}"
		fi
		if [ $piResourceUpload -gt 0 ]; then
			flag="${flag:0:1}Y${flag:2}"
		fi
		if [ $ftpUpload -gt 0 ]; then
			flag="${flag:0:2}Y"
		fi

		# Fetch a MAC address to use as a machine UUID. Not perfect, but good enough for this application.
		mac=$(ifconfig | grep -m 1 -oP 'HWaddr \K.................' | sed 's/://g')

		# Generate a random 8 character alphanumeric string (upper and lowercase)
		# uuid=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
		uuid=$RANDOM
		#create the tar gzip file.
		tar -czf /home/pi/WarDriving/logs/compressed/"$flag.$mac.$(date +%s).$uuid".tar.gz -C /home/pi/WarDriving/logs/preprocessed .  # dont forget the dot on the end - it's important!

		#remove the pre processed files
		rm -rf /home/pi/WarDriving/logs/preprocessed/*

		printf "%sDONE%s - %s File(s) compressed" $GREEN $DEFAULT "$filecounter2"
	else
		printf "%sDONE%s - No files required compression" $GREEN $DEFAULT
	fi

	#########################################################################
	# 6. Check for an internet connection before attempting to upload files #
	#########################################################################
	printf "\n%sChecking for Internet Connection:  " $MAGENTA
	if checkOnline; then
		printf "%sSUCCESS%s - Internet connection available"  $GREEN $DEFAULT
		UploadToWigle
		UploadToPiResource
		UploadToFTP
	else
		printf "%sFAILURE%s - Internet connection NOT available"  $RED $DEFAULT
	fi

	######################################################################################
	# 7. Delete files that have been sucessfully uploaded to all configured destinations #
	######################################################################################

	if [ $deleteAfterUpload -eq 1 ]; then
		printf "\n%sThe following files are identified for deletion:" $MAGENTA

		#identify files with all flags (first 3 charactors) set to NNN
		for file in /home/pi/WarDriving/logs/compressed/*
		do
			baseFileName=$(basename "$file")
			if [[ ${baseFileName:0:3} == "NNN" ]]; then
				printf "\n      %s%s" $DEFAULT "$baseFileName"
				if rm "$file"; then
					printf "%s DELETED" $GREEN
				else
					printf "%s ERROR - %s" $RED $?
				fi
			fi
		done
	fi

	####################################################################################################
	# 8. Check disk space.                                                                             #
	#    If less than a set amount, delete oldest wardriving files even if they haven't been uploaded  #
	####################################################################################################

	diskSpaceUsed=$(df -H | grep $filesystem | awk '{ print $5 }' | cut -d'%' -f1)
	printf "\n%sChecking used disk space: " $MAGENTA
	if [ "$diskSpaceUsed" -gt $filesystemUsedSpaceLimit ]; then
		printf "%s%s%%" $RED "$diskSpaceUsed"
		printf "\n%sDeleting the following files to create disk space:" $MAGENTA

		while [ $(find /home/pi/WarDriving/logs/compressed/ -maxdepth 1 -type f | grep -v '/\.' | wc -l) -gt 0 ] && [ $(df -H | grep $filesystem | awk '{ print $5 }' | cut -d'%' -f1) -gt $filesystemUsedSpaceLimit ]
		do
			oldestFile=$(ls -tp /home/pi/WarDriving/logs/compressed | grep -v '/$' | tail -n 1)
			if rm /home/pi/WarDriving/logs/compressed/"$oldestFile"; then
				printf "\n      %s%s%s DELETED" $DEFAULT "$oldestFile" $GREEN
			else
				printf "\n      %s%s%s ERROR - %s" $DEFAULT "$oldestFile" $RED $?
			fi
		done

		if [ $(df -H | grep $filesystem | awk '{ print $5 }' | cut -d'%' -f1) -gt $filesystemUsedSpaceLimit ]; then
			printf "\n%s      WARNING%s - There are no files identified for deleting that will create any more space" $CYAN $DEFAULT
		fi
	else
		printf "%s%s%%" $GREEN "$diskSpaceUsed"
	fi

	#########################################
	# 9. Wait before restarting this script #
	#########################################
	countDown $timerRepeat $DEFAULT"Waiting" "seconds before restarting the cycle     "

done
