#!/bin/bash

# these are the defaults for the commandline-options
KEYSIZE=4096
PASSPHRASE=
FILENAME=~/.ssh/id_test
KEYTYPE=ed25519
HOST=host
PORT=
USER=${USER}
JUMPHOST=
# set with --add-to-ssh-config to also register a fast-connection alias in ~/.ssh/config
SSH_CONFIG_NAME=

# use "-p <port>" if the ssh-server is listening on a different port
SSH_OPTS="-o PubkeyAuthentication=no"

#
# NO MORE CONFIG SETTING BELOW THIS LINE
#

function usage() {
	echo "Specify some parameters, valid ones are:"

    echo "  -u (--user)       <username>, default: ${USER}"
    echo "  -f (--file)       <file>,     default: ${FILENAME}"
    echo "  -h (--host)       <hostname>, default: ${HOST}"

    echo "  -p (--port)       <port>,     default: <default ssh port>"
    echo "  -j (--jumphost)   <jumphost>, default: <none>, e.g. 'user@jumphost' or 'user@jumphost:port'"
    echo "  -k (--keysize)    <size>,     default: ${KEYSIZE}"
    echo "  -t (--keytype)    <type>,     default: ${KEYTYPE}, typical values are 'rsa' or 'ed25519'"

    echo "  -P (--passphrase) <key-passphrase>, default: ${PASSPHRASE}"

    echo "      (--add-to-ssh-config) <config-name>, default: <none>, appends a 'Host <config-name>' block to ~/.ssh/config"

    exit 2
}

if [[ $# < 1 ]];then
	usage
fi

while [[ $# > 0 ]]
do
	key="$1"
	shift
	case $key in
		-u*|--user)
			USER="$1"
			shift
			;;
		-f*|--file)
			FILENAME="$1"
			shift
			;;
		-h*|--host)
			HOST="$1"
			shift
			;;
		-p*|--port)
			PORT="$1"
			SSH_OPTS="${SSH_OPTS} -p $1"
			shift
			;;
		-j*|--jumphost)
			JUMPHOST="$1"
			shift
			;;
		-k*|--keysize)
			KEYSIZE="$1"
			shift
			;;
		-t*|--keytype)
			KEYTYPE="$1"
			shift
			;;
		-P*|--passphrase)
			PASSPHRASE="$1"
			shift
			;;
		--add-to-ssh-config)
			SSH_CONFIG_NAME="$1"
			shift
			;;
		*)
			# unknown option
			usage "unknown parameter: $key, "
			;;
	esac
done

# resolve the key filename to an absolute, real path so ~/.ssh/config gets a stable, unambiguous path
# works for paths that do not exist yet, and on GNU (realpath -m) / macOS (python3 or grealpath) alike
resolve_key_path() {
    local path="$1" out
    if command -v realpath >/dev/null 2>&1;then
        out=$(realpath -m "$path" 2>/dev/null) && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    fi
    if command -v grealpath >/dev/null 2>&1;then
        out=$(grealpath -m "$path" 2>/dev/null) && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    fi
    if command -v python3 >/dev/null 2>&1;then
        out=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" 2>/dev/null) && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    fi
    if command -v readlink >/dev/null 2>&1;then
        out=$(readlink -f "$path" 2>/dev/null) && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
    fi
    # last resort, pure bash: make it absolute if its directory already exists
    if [[ "$path" == */* ]];then
        local dir="${path%/*}" base="${path##*/}"
        out=$( cd "$dir" >/dev/null 2>&1 && pwd -P )
        if [ -n "$out" ];then
            printf '%s/%s\n' "$out" "$base"; return 0
        fi
    fi
    return 1
}
RESOLVED_KEY=$(resolve_key_path "${FILENAME}")
if [ -n "${RESOLVED_KEY}" ];then
    FILENAME="${RESOLVED_KEY}"
fi

if [ -n "${JUMPHOST}" ];then
	SSH_OPTS="${SSH_OPTS} -J ${JUMPHOST}"
fi

echo
echo "Transferring key from ${FILENAME} to ${USER}@${HOST} using options '${SSH_OPTS}', keysize ${KEYSIZE} and keytype: ${KEYTYPE}"
echo
echo "Press ENTER to continue or CTRL-C to abort"
read

# check that we have all necessary parts
SSH_KEYGEN=`which ssh-keygen`
SSH=`which ssh`
SSH_COPY_ID=`which ssh-copy-id`

if [ -z "${SSH_KEYGEN}" ];then
    echo Could not find the 'ssh-keygen' executable
    exit 1
fi
if [ -z "${SSH}" ];then
    echo Could not find the 'ssh' executable
    exit 1
fi

echo
# perform the actual work
if [ -f "${FILENAME}" ];then
    echo "Using existing key ${FILENAME} - key already present, skipping key creation and upload"
    if [ -z "${SSH_CONFIG_NAME}" ];then
        echo "Note: nothing else to do. Pass --add-to-ssh-config <name> to register it in ~/.ssh/config"
    fi
else
    echo "Creating a new key using ${SSH_KEYGEN}"
    ${SSH_KEYGEN} -t $KEYTYPE -b $KEYSIZE  -f "${FILENAME}" -N "${PASSPHRASE}"
    RET=$?
    if [ ${RET} -ne 0 ];then
        echo "ssh-keygen failed: ${RET}"
        exit 1
    fi

    if [ ! -f "${FILENAME}.pub" ];then
        echo "Did not find the expected public key at ${FILENAME}.pub"
        exit 1
    fi

    echo
    echo "Having key-information"
    ssh-keygen -l -f "${FILENAME}"

    echo
    echo "Adjust permissions of generated key-files locally"
    chmod 0600 "${FILENAME}" "${FILENAME}.pub"
    RET=$?
    if [ ${RET} -ne 0 ];then
        echo "chmod failed: ${RET}"
        exit 1
    fi

    echo
    echo "Copying the key to the remote machine ${USER}@${HOST}, this usually will ask for the password"
    if [ -z "${SSH_COPY_ID}" ];then
        echo "Could not find the 'ssh-copy-id' executable, using manual copy instead"
        cat "${FILENAME}.pub" | ssh ${SSH_OPTS} ${USER}@${HOST} 'cat >> ~/.ssh/authorized_keys'
    else
        ${SSH_COPY_ID} ${SSH_OPTS} -i ${FILENAME}.pub ${USER}@${HOST}
        RET=$?
        if [ ${RET} -ne 0 ];then
            echo "Executing ssh-copy-id via ${SSH_COPY_ID} failed, trying to manually copy the key-file instead"
            cat "${FILENAME}.pub" | ssh ${SSH_OPTS} ${USER}@${HOST} 'cat >> ~/.ssh/authorized_keys'
        fi
    fi

    RET=$?
    if [ ${RET} -ne 0 ];then
        echo "ssh-copy-id failed: ${RET}"
        exit 1
    fi

    echo
    echo "Adjusting permissions to avoid errors in ssh-daemon, this may ask once more for the password"
    ${SSH} ${SSH_OPTS} ${USER}@${HOST} "chmod go-w ~ && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
    RET=$?
    if [ ${RET} -ne 0 ];then
        echo "ssh-chmod failed: ${RET}"
        exit 1
    fi
fi

# optionally register the new connection in ~/.ssh/config for a fast 'ssh <name>' alias
if [ -n "${SSH_CONFIG_NAME}" ];then
    echo
    SSH_CONFIG_FILE="${HOME}/.ssh/config"

    # 1) the key must actually exist before we register it
    if [ ! -f "${FILENAME}" ];then
        echo Warning: key file ${FILENAME} not found, skipping ~/.ssh/config update
    # 2) skip if this exact key (IdentityFile) is already configured
    elif grep -qE "^[[:space:]]*IdentityFile[[:space:]]+${FILENAME}[[:space:]]*$" "${SSH_CONFIG_FILE}" 2>/dev/null;then
        echo "A config entry already references this key (${FILENAME}), not appending a duplicate"
    # 3) skip if a Host block with this name already exists
    elif grep -qE "^[[:space:]]*Host[[:space:]]+${SSH_CONFIG_NAME}[[:space:]]*$" "${SSH_CONFIG_FILE}" 2>/dev/null;then
        echo A 'Host ${SSH_CONFIG_NAME}' block already exists in ${SSH_CONFIG_FILE}, leaving it unchanged
    else
        echo "Registering host '${SSH_CONFIG_NAME}' in ~/.ssh/config"
        {
            echo
            echo "Host ${SSH_CONFIG_NAME}"
            echo "    HostName ${HOST}"
            [ -n "${PORT}" ] && echo "    Port ${PORT}"
            echo "    User ${USER}"
            echo "    IdentityFile ${FILENAME}"
            [ -n "${JUMPHOST}" ] && echo "    ProxyJump ${JUMPHOST}"
        } >> "${SSH_CONFIG_FILE}"
        echo Done, you can now simply run: ssh ${SSH_CONFIG_NAME}
    fi
fi

# Cut out PubKeyAuth=no here as it should work without it now
echo
echo Setup finished, now try to run ${SSH} `echo ${SSH_OPTS} | sed -e 's/-o PubkeyAuthentication=no//g'` -i "${FILENAME}" ${USER}@${HOST}

echo
echo If it still does not work, you can try the following steps:
echo "- Check if ~/.ssh/config has some custom configuration for this host"
echo "- Make sure the type of key is supported, e.g. 'dsa' is deprecated and might be disabled"
echo "- Try running ssh with '-v' and look for clues in the resulting output"
