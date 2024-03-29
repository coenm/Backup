#!/bin/bash

# ! /bin/sh


#***************************************************************
VERSION="2019.11.22"

DATETIME_START="$(date +"%Y.%m.%d-%H.%M.%S")"

RSYNC_DEFAULT_OPTIONS='--hard-links --delete --delete-excluded --archive --chmod=oga-w'
RSYNC_DEFAULT_OPTIONS_REMOTE='--hard-links --delete --delete-excluded --archive --no-owner --no-group --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r'

# Get absolute path this script is in and use this path as a base for all other (relatve) filenames.
# !! Please make sure there are no spaces inside the path !!
# Source: https://stackoverflow.com/questions/242538/unix-shell-script-find-out-which-directory-the-script-file-resides
# 2017-12-07
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

# not sure if it should end with /
CONFIG_DIR=config

echo $SCRIPTPATH
echo $CONFIG_DIR


#***************************************************************
# Functions  
#***************************************************************

print_header()
{
	echo ""
	echo ""
	echo "#################################################"
	echo "#   $0 - version $VERSION" 
	echo "#################################################"
	echo ""
}


print_help()
{
	echo "Usage:																	"
	echo "																			"
	echo "	$0 -n name [-H <host> [-I <identity file>] [-P <port>]] [-c -p -v -q -h]"
	echo "																			"
	echo "	-h = Help																"
	echo "       List this help menu												"
	echo "																			"
	echo "	-n = Name of the backup (used as root folder in backup destination).    "
	echo "																			"
	echo "	-c = Checksum mode														"
	echo "       Forces sender to checksum all files before transfer.				"
	echo "       Can be quite slow.													"
	echo "																			"
	echo "	-v = Verbose mode														"
	echo "       Run rsync command with the -v switch to use verbose output			"
	echo "																			"
	echo "	-p = Progress mode														"
	echo "       Run rsync command with the -p switch to show the progress			"
	echo "																			"
	echo "	-q = Quiet mode															"
	echo "       Run rsync command with -q switch to suppress all output			"
	echo "       except errors														"
	echo "																			"
	echo "																			"
	echo "	== REMOTE BACKUP ==														"
	echo "																			"
	echo "	-H = Host name (required for remote)                                    "
	echo "       Hostname of remote machine. Can be IP4 or hostname.		     	"
	echo "																			"
	echo "	-P = SSH Port (optional, default 22)									"
	echo "       Destination SSH port of the remote machine.             	     	"
	echo "																			"
	echo "	-I = Identity file (optional, relative to path /tmp/.ssh/ ) 			"
	echo "       RSA or EC private key.                                  	     	"
	echo "       When not given, or file not found,                                 "
	echo "       - '/tmp/.ssh/ed_25519',                                            "
	echo "       - '/tmp/.ssh/id_rsa'                                               "
	echo "       will be used when available                                        "
	echo "																			"
	echo "----------------------------------------------------------------------------"
}


# https://stackoverflow.com/questions/9612090/how-to-loop-through-file-names-returned-by-find
# find /config -name "exclude_*.config"
for i in $(find /config -name "exclude_*.config"); do
    echo "Found exclude file: $i"
	RSYNC_EXCLUDE_FILES_ARRAY+=( --exclude-from "$i" )
done

RSYNC_EXCLUDE_FILES=${RSYNC_EXCLUDE_FILES_ARRAY[@]}
echo RSYNC_EXCLUDE_FILES: ${RSYNC_EXCLUDE_FILES}

#Wrapping up the excludes
RSYNC_EXCLUDES="$RSYNC_EXCLUDE_FILES"

opt_cap_p=22

#***************************************************************
# Get Options from the command line  
#***************************************************************
while getopts "n:H:P:I:hcvpq" options
do
	case $options in 
		c ) RSYNC_MODE_CHECKSUM='--checksum ';;
		v ) RSYNC_MODE_VERBOSE='--verbose ';;
		q ) RSYNC_MODE_QUIET='--quiet ';;
		p ) RSYNC_MODE_PROGRESS='--progress ';;	
		
		n ) opt_n=$OPTARG;;

		H ) 
		    opt_cap_h=$OPTARG
		    DO_REMOTE=1
		    ;;
		P ) opt_cap_p=$OPTARG;;
		I ) opt_cap_i=$OPTARG;;

		h ) opt_h=1;;
		* ) opt_h=1;;
	esac
done


 
#***************************************************************
# Print Help 
#***************************************************************
if [ $opt_h ]; then
	print_header
	print_help
	exit 1
fi 


# Destination base directory to store the backup.
# Should be an absolute path. If the backup is on a remote machine. Do not enter a path like user@host:/path/to/store/backup
BACKUP_DIR=/backup

#***************************************************************
# Name of backup
#***************************************************************
if [ ! -z $opt_n ]; then

	BACKUP_NAME=$opt_n
	echo "-- BACKUP_NAME: ${BACKUP_NAME}"

else

	print_header
	echo [ERROR] Backup name -n is empty
	echo
	print_help	
	exit 1

fi

# Backup directory. Must be absolute path. Directory must exists and the executing user of the script should have read rights.
BACKUP_SOURCE_DIR=/source/

## Create the destination path (also the escaped variant)
DESTINATION_DIR=${BACKUP_DIR}/${BACKUP_NAME}
DESTINATION_DIR_ESCAPED=${DESTINATION_DIR// /\\ }

echo "-- DESTINATION_DIR: ${DESTINATION_DIR}"
echo "-- DESTINATION_DIR_ESCAPED: ${DESTINATION_DIR_ESCAPED}"


#***************************************************************
# Misc
#***************************************************************

#Check if source exists
if [ ! -d "$BACKUP_SOURCE_DIR" ]; then
	print_header
	echo [ERROR] $BACKUP_SOURCE_DIR does not exist.
	exit 1
fi


#***************************************************************
# Run the real backup
#***************************************************************
echo Started at $DATETIME_START using backupscript $VERSION

echo "-- DO_REMOTE: ${DO_REMOTE}"
echo "-- HOST: ${opt_cap_h}"
echo "-- PORT: ${opt_cap_p}"

if [ $DO_REMOTE -eq 1 ]; then

	DEST_HOST=${opt_cap_h}

	DEST_PORT=${opt_cap_p}
	SSH_PORT='-p '$DEST_PORT	

	if [[ ! -z ${opt_cap_i} && -f /tmp/.ssh/${opt_cap_i} ]]; then
		DEST_KEYFILE=/tmp/.ssh/${opt_cap_i}
		echo "Using key set by -I argument: ${DEST_KEYFILE}"
	elif [ -f /tmp/.ssh/id_ed25519 ]; then
		DEST_KEYFILE=/tmp/.ssh/id_ed25519
		echo "Using key: ${DEST_KEYFILE}"
	elif [ -f /tmp/.ssh/id_rsa ]; then
		DEST_KEYFILE=/tmp/.ssh/id_rsa
		echo "Using key: ${DEST_KEYFILE}"
	else
		echo
		echo [ERROR] No privet key found.
		echo
		print_help
		exit 1
	fi

    # copy the private key to other directory
	# make sure the permissions are okay and use that key.
	mkdir -p /root/backupscript/
	cp ${DEST_KEYFILE} root/backupscript/private_key
	DEST_KEYFILE=root/backupscript/private_key
	chown root:root ${DEST_KEYFILE}
	chmod 600 ${DEST_KEYFILE}
   
	SSH_KEY='-i '${DEST_KEYFILE}		
			
	echo Start remote backup
	echo

	echo Create working dir for backup
	
	# Remote username. This user should exist on the remote machine, should have SSH access with public key authorization enabled.
	DEST_USER=$SSH_USERNAME


	ssh \
		"-o StrictHostKeyChecking=false " $SSH_PORT $SSH_KEY ${DEST_USER}@${DEST_HOST} \
		"mkdir -p \"$DESTINATION_DIR/incomplete/\" && mkdir -p \"$DESTINATION_DIR/partial/\""

	echo
	
	echo Start RSync
	echo
	echo DESTINATION_DIR_ESCAPED: ${DESTINATION_DIR_ESCAPED}
	
	rsync \
		$RSYNC_MODE_CHECKSUM \
		$RSYNC_MODE_VERBOSE \
		$RSYNC_MODE_PROGRESS \
		$RSYNC_MODE_QUIET \
		${RSYNC_DEFAULT_OPTIONS_REMOTE} \
		${RSYNC_EXCLUDES} \
		-e 'ssh -o StrictHostKeyChecking=false -p '${DEST_PORT}' -i'${DEST_KEYFILE} \
		--link-dest="${DESTINATION_DIR_ESCAPED}/current"  \
		"${BACKUP_SOURCE_DIR}" \
		${DEST_USER}@${DEST_HOST}:"${DESTINATION_DIR_ESCAPED}/incomplete/" 2>&1
		
		
	echo
	
	echo wrapping up...
	echo
	
	ssh \
		"-o StrictHostKeyChecking=false " $SSH_PORT $SSH_KEY ${DEST_USER}@${DEST_HOST} \
		"cd \"$DESTINATION_DIR\" && mv incomplete/ $DATETIME_START/ && rm -rf current && ln -s $DATETIME_START current && rm -rf partial"


	rm -rf ${DEST_KEYFILE}
	
else

	echo start local backup
	echo
	
	echo Create working dir for backup
	
	mkdir -p "${DESTINATION_DIR}/current"
	mkdir -p "${DESTINATION_DIR}/incomplete/"
	mkdir -p "${DESTINATION_DIR}/partial/"

	echo

	echo Start RSync
	echo
	
	rsync \
		$RSYNC_MODE_CHECKSUM \
		$RSYNC_MODE_VERBOSE \
		$RSYNC_MODE_PROGRESS \
		$RSYNC_MODE_QUIET \
		${RSYNC_DEFAULT_OPTIONS} \
		${RSYNC_EXCLUDES} \
		--link-dest="${DESTINATION_DIR}/current" \
		"${BACKUP_SOURCE_DIR}" \
		"${DESTINATION_DIR}/incomplete/" 2>&1

		
	echo
	
	echo wrapping up...
	echo
	cd "${DESTINATION_DIR}"

	mv incomplete/ ${DATETIME_START}/ 
	rm -rf current 
	ln -s $DATETIME_START current
	rm -rf partial	
fi


# .. and we are done...
DATETIME_FINISHED="$(date +"%Y.%m.%d-%H.%M.%S")"

echo Finished at $DATETIME_FINISHED
echo Backup finished