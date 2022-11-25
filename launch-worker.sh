#!/bin/bash


# Variables
WORKER_POOLNAME=public
DEPOSIT=4000000000
CHAIN=bellecour
MINETHEREUM=0.0
HUBCONTRACT=0x3eca1B216A7DF1C7689aEb259fFB83ADFB894E7f
WORKER_DOCKER_IMAGE_VERSION=7.1.0 # NFT Wallet worker
#WORKER_DOCKER_IMAGE_VERSION=7.0.1 # Non NFT wallet Worker
IEXEC_CORE_HOST=workerpool.iexecenterprise.com #18.185.47.13 #NFT wallet pool
#IEXEC_CORE_HOST=3.66.230.42 # Non NFT wallet pool
IEXEC_CORE_PORT=7001
IEXEC_SDK_VERSION=7.2.2
IEXEC_WORKER_SSL_TRUSTSTORE="/usr/lib/jvm/zulu-11/lib/security/cacerts"
IEXEC_WORKER_SSL_TRUSTSTORE_PASSWORD="YaD&@g4U&!bFfiH3yNtz"
IEXEC_CORE_PROTOCOL=https
IEXEC_TEE_ENABLED=false
GAS_PRICE_CAP=0
GAS_PRICE_MULTIPLIER=0
TOTAL_AVAILABLE_CPUS=1
WORKER_DEFAULT_CPU=1
WORKER_AVAILABLE_CPU=1
CHAIN_URL=https://bellecour.iex.ec
RESULTS_DIR=/tmp/results
KEYSTORE_DIR=
IMPORT_WALLET=no

# Configuration array declaration
declare -A config

file="/vagrant/worker_config.properties"
while IFS='=' read -r key value; do
CLEANEDVALUE=${value//[$'\t\r\n']}
   config["$key"]="$CLEANEDVALUE"
done < "$file"


#Config Variables
CREATE_NEW_WALLET=${config["CREATE_NEW_WALLET"]}
WALLET_PRIVATE_KEY=${config["WALLET_PRIVATE_KEY"]} 
WORKERWALLETPASSWORD=${config["WALLET_PASSWORD"]}
WORKER_NAME=${config["WORKER_NAME"]}



# Function that prints messages
function message() {
  echo "[$1] $2"
  if [ "$1" == "ERROR" ]; then
    read -p "Press [Enter] to exit..."
    exit 1
  fi
}

# Function which checks exit status and stops execution
function checkExitStatus() {
  if [ $1 -eq 0 ]; then
    message "OK" ""
  else
    message "ERROR" "$2"
  fi
}

# Remove worker function
function removeWorker(){
    message "INFO" "Removing worker."
    docker rm -f "$WORKER_POOLNAME-worker"
}

# Remove worker option
if [ "$1" == "--remove" ]; then
    removeWorker
    checkExitStatus $? "Unable to remove $WORKER_POOLNAME worker."
    message "INFO" "To start a new worker please relaunch the script."
    read -p "Press [Enter] to exit..."
    exit 1
fi

# Update worker option
if [ "$1" == "--update" ]; then
    message "INFO" "Updating worker."
    removeWorker
    message "INFO" "Starting a new worker."
fi


echo "________________________________________________________________"
echo "                                                                "
echo "Before proceeding further please confirm below details are correct: "
echo "                                                                "

if [ "$WALLET_PRIVATE_KEY" != "" ]; then
   echo " You want to import existing wallet for private key = $WALLET_PRIVATE_KEY "
   CREATE_NEW_WALLET=no
   IMPORT_WALLET=yes
elif [ "$CREATE_NEW_WALLET" == "YES" ] || [ "$CREATE_NEW_WALL	ET" == "yes" ]; then	
   echo " You want to create new wallet = $CREATE_NEW_WALLET"
   IMPORT_WALLET=no
fi


#echo " You want to create new wallet = $CREATE_NEW_WALLET" 
#echo " You want to import existing wallet for private key = $WALLET_PRIVATE_KEY "
echo " Your wallet password is = $WORKERWALLETPASSWORD "
echo " Your public worker name will be = $WORKER_NAME "

#Set CPUs for worker the number is less than by 1 from available CPUS of the machine.
TOTAL_AVAILABLE_CPUS=$(nproc --all) 
WORKER_AVAILABLE_CPU=$(expr  $TOTAL_AVAILABLE_CPUS - 1)

if [ "$WORKER_AVAILABLE_CPU" == 0 ]; then
	WORKER_AVAILABLE_CPU=$WORKER_DEFAULT_CPU
	echo " Number of CPUs for your worker = $WORKER_AVAILABLE_CPU out of ($TOTAL_AVAILABLE_CPUS)"
    echo " ( Stting up default CPUs for worker to $WORKER_DEFAULT_CPU )"    
fi

echo "                                                                "
echo "________________________________________________________________"
echo "                                                                "

#Set to yes to skip user inputs
answercontinue=yes
while [ "$answercontinue" != "yes" ] && [ "$answercontinue" != "no" ]; do
	read -p "Do you want continue with the above details? [yes/no] " answercontinue
done	

if [ "$answercontinue" == "no" ]; then
    #read -p " Press [Enter] to exit..."
    exit 1
fi

# Determine OS platform
message "INFO" "Detecting OS platform..."
UNAME=$(uname | tr "[:upper:]" "[:lower:]")

# If Linux, try to determine specific distribution
if [ "$UNAME" == "linux" ]; then
  # If available, use LSB to identify distribution
  if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
      DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
  # Otherwise, use release info file
  else
      DISTRO=$(ls -d /etc/[A-Za-z]*[_-][rv]e[lr]* | grep -v "lsb" | cut -d'/' -f3 | cut -d'-' -f1 | cut -d'_' -f1 | head -n 1)
  fi
fi

# For everything else (or if above failed), just use generic identifier
[ "$DISTRO" == "" ] && DISTRO=$UNAME

# Check if OS platform is supported
if [ "$DISTRO" != "Ubuntu" ] && [ "$DISTRO" != "darwin" ] && [ "$DISTRO" != "centos" ]; then
  message "ERROR" "Only Ubuntu OS and MacOS platform is supported for now. Your platform is: $DISTRO"
else
  message "OK" "Detected supported OS platform [$DISTRO] ..."
fi

# Launch iexec sdk function
function iexec {
  if [ "$DISTRO" != "darwin" ]; then
    docker run -e DEBUG=$DEBUG --interactive --tty --rm -v /tmp:/tmp -v $(pwd):/iexec-project -v /home/$(whoami)/.ethereum/keystore:/home/node/.ethereum/keystore -w /iexec-project iexechub/iexec-sdk:$IEXEC_SDK_VERSION "$@"
  else
    docker run -e DEBUG=$DEBUG --interactive --tty --rm -v /tmp:/tmp -v $(pwd):/iexec-project -v /Users/$(whoami)/Library/Ethereum/keystore:/home/node/.ethereum/keystore -w /iexec-project iexechub/iexec-sdk:$IEXEC_SDK_VERSION "$@"
  fi
}

# Check if docker is installed
message "INFO" "Checking if docker is installed..."
which docker >/dev/null 2>/dev/null
if [ $? -eq 0 ]
then
    (docker --version | grep "Docker version")>/dev/null  2>/dev/null
    if [ $? -eq 0 ]
    then
        message "OK" "Docker is installed."
    else
        message "ERROR" "Docker is not installed at your system. Please install it."
    fi
else
    message "ERROR" "Docker is not installed at your system. Please install it."
fi

# Checking connection and changing docker mirror if necessary
message "INFO" "Checking connection [trying to contact google.com] ..."

if ping -c 1 google.com &> /dev/null; then
  message "OK" "Connection is ok."
else
  while [ "$answerdocker" != "yes" ] && [ "$answerdocker" != "no" ]; do
    read -p "Are you from China? [yes/no] " answerdocker
  done

  if [ "$answerdocker" == "yes" ]; then
    message "INFO" "Changing docker mirror..."
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<-'EOF'   
{
 "registry-mirrors": ["https://registry.docker-cn.com"]
}
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart docker
  fi
fi

# Checking containers
RUNNINGWORKERS=$(docker ps --format '{{.ID}}' --filter="name=$WORKER_POOLNAME-worker")
STOPPEDWORKERS=$(docker ps --filter "status=exited" --filter "status=created" --format '{{.ID}}' --filter="name=$WORKER_POOLNAME-worker")

DEADWORKERS=$(docker ps --filter "status=dead" --format '{{.ID}}' --filter="name=$WORKER_POOLNAME-worker")
if [ ! -z "${DEADWORKERS}" ]; then
  docker rm -f $(echo $DEADWORKERS)
fi

# If worker is already running we will just attach to it
if [ ! -z "${RUNNINGWORKERS}" ]; then

    message "INFO" "iExec $WORKER_POOLNAME worker is already running at your machine..."

    #Set to yes just to skip user inputs
    attachworker=yes
    # Attach to worker container
    while [ "$attachworker" != "yes" ] && [ "$attachworker" != "no" ]; do
      read -p "Do you want to see logs of your worker? [yes/no] " attachworker
    done

    if [ "$attachworker" == "yes" ]; then
      message "INFO" "Showing logs of worker container."
      docker container logs -f $(echo $RUNNINGWORKERS)
    fi

elif [ ! -z "${STOPPEDWORKERS}" ]; then

    message "INFO" "Stopped $WORKER_POOLNAME worker detected."

    relaunchworker=yes #Set to yes to skip user inputs 
    # Relaunch worker container    
    while [ "$relaunchworker" != "yes" ] && [ "$relaunchworker" != "no" ]; do
      read -p "Do you want to relauch stopped worker? [yes/no] " relaunchworker
    done

    if [ "$relaunchworker" == "yes" ]; then
        message "INFO" "Relaunching stopped worker."
          docker start $(echo $STOPPEDWORKERS)
        message "INFO" "Worker was sucessfully started."

        attachworker=yes #Set to yes to skip user inputs
        # Attach to worker container
        while [ "$attachworker" != "yes" ] && [ "$attachworker" != "no" ]; do
          read -p "Do you want to see logs of your worker? [yes/no] " attachworker
        done

        if [ "$attachworker" == "yes" ]; then
          message "INFO" "Showing logs of worker container."
          docker container logs -f $(echo $STOPPEDWORKERS)
        fi
    fi

else

    # Pulling iexec sdk
    message "INFO" "Pulling iexec sdk..."
    docker pull iexechub/iexec-sdk:$IEXEC_SDK_VERSION
    checkExitStatus $? "Failed to pull image. Check docker service state or if user has rights to launch docker commands."

    # Looping over wallet files in inverse order (from the most recent to older one)
    WALLET_SELECTED=0

    if [ "$DISTRO" == "darwin" ]; then
        files=(/Users/$(whoami)/Library/Ethereum/keystore/*)
        mkdir -p /Users/$(whoami)/Library/Ethereum/keystore/
	KEYSTORE_DIR=/Users/$(whoami)/Library/Ethereum/keystore/
    else
        files=(/home/$(whoami)/.ethereum/keystore/*)
        mkdir -p /home/$(whoami)/.ethereum/keystore/
        KEYSTORE_DIR=/home/$(whoami)/.ethereum/keystore/
    fi

    for ((i=${#files[@]}-1; i>=0; i--)); do

        if [ "$(cat ${files[$i]})" = "PASTE_YOUR_WALLET_HERE" ]; then
           echo "[INFO] Skipping wallet.json"
           continue
        fi

        # If a wallet was found
        if [[ -f ${files[$i]} ]]; then
            message "INFO" "Found wallet in ${files[$i]}"
            # Extracting wallet address
            WALLET_ADDR=$(cat ${files[$i]} | awk -v RS= '{$1=$1}1' | tr -d "[:space:]" | sed -E "s/.*\"address\":\"([a-zA-Z0-9]+)\".*/\1/g")

             #Set to yes to skip user inputs and always continue with recently added wallet.
            answerwalletuse=yes
            while [ "$answerwalletuse" != "yes" ] && [ "$answerwalletuse" != "no" ]; do
                read -p "Do you want to use wallet 0x$WALLET_ADDR? [yes/no] " answerwalletuse
            done

            # If user selects a wallet
            if [ "$answerwalletuse" == "yes" ]; then

                # Get wallet password and check it with iExec SDK
                #read -p "Please provide the password of wallet $WALLET_ADDR: " WORKERWALLETPASSWORD
                WALLET_FILE=${files[$i]}
                WALLET_SELECTED=1

                rm -fr /tmp/iexec
                mkdir /tmp/iexec
                cd /tmp/iexec

                message "INFO" "Initializing SDK."
                iexec init --skip-wallet --force
                checkExitStatus $? "Can't init iexec sdk."

                message "INFO" "Checking wallet password."
                iexec wallet show --wallet-file $(basename $WALLET_FILE) --password "$WORKERWALLETPASSWORD" --chain $CHAIN
                checkExitStatus $? "Invalid wallet password."
                break;
            fi

            unset answerwalletuse
        fi
    done

    # If no wallet was selected
    if [ "$WALLET_SELECTED" == 0 ]; then       
	    
		answerwalletcreate=$CREATE_NEW_WALLET
		
        # If user accepts to create a wallet
        if [ "$answerwalletcreate" = "yes" ]; then
            message "INFO" "No wallet was selected."			
			message "INFO" "Creating new wallet with wallet password: $WORKERWALLETPASSWORD"
			
            rm -fr /tmp/iexec
            mkdir /tmp/iexec
            cd /tmp/iexec

            message "INFO" "Getting created wallet info."
	   
	    IEXEC_INIT_RESULT=$(iexec init --force --raw --password "$WORKERWALLETPASSWORD")
            checkExitStatus $? "Can't create a wallet. Failed init."


            # Get wallet address and wallet file path
            WALLET_ADDR=$(echo $IEXEC_INIT_RESULT | sed -E "s/.*\"address\":\"([0-9a-zA-Z]+)\".*/\1/g")
            WALLET_FILE=$(echo $IEXEC_INIT_RESULT | sed -E "s/.*\"fileName\":\"([0-9a-zA-Z\/.-]+)\".*/\1/g")
            # Replacing node home with current user home
            if [ "$DISTRO" == "darwin" ]; then
                WALLET_FILE=$(echo $WALLET_FILE | sed "s/home\/node\/\.ethereum/Users\/$(whoami)\/Library\/Ethereum/g")
            else
                WALLET_FILE=$(echo $WALLET_FILE | sed "s/node/$(whoami)/g")
            fi

            message "INFO" "A wallet with address $WALLET_ADDR was created in $WALLET_FILE."

            message "INFO" "Please fill your wallet with minimum $MINETHEREUM ETH and $DEPOSIT nRLC. Then relaunch the script."
            bash launch-worker.sh
            #read -p "Press [Enter] to exit..."
            exit 1            
            
        elif [ "$IMPORT_WALLET" == "yes" ]; then
		
			WORKERWALLETPRIVATEKEY=$WALLET_PRIVATE_KEY
			rm -fr /tmp/iexec
			mkdir /tmp/iexec
			cd /tmp/iexec
			message "INFO" "Importing wallet for private key : $WORKERWALLETPRIVATEKEY"
			message "INFO" "Getting wallet info."
                   # IEXEC_INIT_RESULT=$(iexec wallet create --keystoredir $PWD  --force --raw --password "$WORKERWALLETPASSWORD")
		   IEXEC_INIT_RESULT=$(iexec wallet import "$WORKERWALLETPRIVATEKEY" --password "$WORKERWALLETPASSWORD" --keystoredir . )  #"$KEYSTORE_DIR")
		    checkExitStatus $? "Can't import a wallet. Failed init, Please provide a valid private key."
			

			message "INFO" "Moving wallet to the kestore $KEYSTORE_DIR."
			 $(mv UTC* $KEYSTORE_DIR )
			 checkExitStatus $? "Can't move a wallet. Failed movement."

			# Get wallet address and wallet file path
			WALLET_ADDR=$(echo $IEXEC_INIT_RESULT | sed -E "s/.*\"address\":\"([0-9a-zA-Z]+)\".*/\1/g")
			WALLET_FILE=$(echo $IEXEC_INIT_RESULT | sed -E "s/.*\"fileName\":\"([0-9a-zA-Z\/.-]+)\".*/\1/g")
			# Replacing node home with current user home
			if [ "$DISTRO" == "darwin" ]; then
				WALLET_FILE=$(echo $WALLET_FILE | sed "s/home\/node\/\.ethereum/Users\/$(whoami)\/Library\/Ethereum/g")
			else
				WALLET_FILE=$(echo $WALLET_FILE | sed "s/node/$(whoami)/g")
			fi

			message "INFO" "A wallet with address $WALLET_ADDR was imported in $WALLET_FILE."
			message "INFO" "To start the worker please relaunch the worker."

                        bash launch-worker.sh
			#read -p "Press [Enter] to exit..."
			exit 1          
        else
		    message "INFO" "Required values are not set in worker_config.properties file. Please set them all and relaunch the script."
            message "ERROR" "You cannot launch a worker without a wallet. Exiting..."			
            read -p "Press [Enter] to exit..."
            exit 1
        fi
    fi    

    message "INFO" "The wallet $WALLET_ADDR with password $WORKERWALLETPASSWORD and path $WALLET_FILE will be used..."

    message "INFO" "Init iExec SDK."
    iexec init --force --skip-wallet
    checkExitStatus $? "Can't init iexec sdk."

    message "INFO" "chain.json created in $PWD"
    #Set defailt chain to bellecour
    sed -i '/default/c\   \"default\": \"bellecour\"' chain.json
	checkExitStatus $? "Can't set default chain to $CHAIN ."
	
    message "INFO" "Updated default chain to $CHAIN "
    cat chain.json

    message "INFO" "Adding Hub Contract address."
    sed -i'.temp' -E "s/(\"id\": \"42\")/\1\,\ \"hub\":\"$HUBCONTRACT\"/g" chain.json
    checkExitStatus $? "Can't place hub address."

    # Getting necessary values
    ETHEREUM=$(echo $WALLETINFO | sed -E "s/.*\"ETH\":\"([0-9.]+)\".*/\1/g")
    NRLC=$(echo $WALLETINFO | sed -E "s/.*\"nRLC\":\"([0-9.]+)\".*/\1/g")
    STAKE=$(echo $ACCOUNTINFO | sed -E "s/.*\"stake\":\"([0-9.]+)\".*/\1/g")

    # Showing balances
    message "INFO" "Ethereum balance is $ETHEREUM ETH."
    message "INFO" "Stake amount is $STAKE nRLC."

    # Checking minimum ethereum
   # if [ $(echo $ETHEREUM'<'$MINETHEREUM | bc -l) -ne 0 ]; then
    #  message "ERROR" "You need to have $MINETHEREUM ETH to launch iExec worker. Your balance is $ETHEREUM ETH."
    #fi

    # Calculate amount to deposit
   # TODEPOSIT=$(($DEPOSIT - $STAKE))

    # Checking if wallet has enough nRLC to deposit
   # if [ $NRLC -lt $TODEPOSIT ]; then
    #  message "ERROR" "You need to have $TODEPOSIT nRLC to make a deposit. But you have only $NRLC nRLC."
   # fi

    # Checking deposit
   # if [ $STAKE -lt $DEPOSIT ]; then

      # Ask for deposit agreement
    #  while [ "$answer" != "yes" ] && [ "$answer" != "no" ]; do
     #   read -p "To participate you need to deposit $TODEPOSIT nRLC. Do you agree? [yes/no] " answer
     # done

     # if [ "$answer" == "no" ]; then
     #   message "ERROR" "You can't participate without deposit."
     # fi

      # Deposit
     # iexec account deposit $TODEPOSIT --wallet-file $(basename $WALLET_FILE) --password "$WORKERWALLETPASSWORD" --chain $CHAIN
     # checkExitStatus $? "Failed to depoit."
   # else
    #  message "OK" "You don't need to stake. Your stake is $STAKE."
   # fi

    # Get worker name
    #while [[ ! "$WORKER_NAME" =~ ^[-_A-Za-z0-9]+$ ]]; do
      #read -p "Enter worker name [only letters, numbers, - and _ symbols]: " WORKER_NAME
    #done

    # Get last version and run worker
    message "INFO" "Creating iExec $WORKER_POOLNAME worker..."
    docker pull iexechub/iexec-worker:$WORKER_DOCKER_IMAGE_VERSION
    checkExitStatus $? "Can't pull docker image."
    docker create --name "$WORKER_POOLNAME-worker" \
             --hostname "$WORKER_NAME" \
             --env "IEXEC_CORE_HOST=$IEXEC_CORE_HOST" \
             --env "IEXEC_CORE_PORT=$IEXEC_CORE_PORT" \
             --env "IEXEC_WORKER_NAME=$WORKER_NAME" \
             --env "IEXEC_WORKER_WALLET_PATH=/iexec-wallet/encrypted-wallet.json" \
             --env "IEXEC_WORKER_WALLET_PASSWORD=$WORKERWALLETPASSWORD" \
             --env "IEXEC_WORKER_SSL_TRUSTSTORE=$IEXEC_WORKER_SSL_TRUSTSTORE" \
             --env "IEXEC_WORKER_SSL_TRUSTSTORE_PASSWORD=$IEXEC_WORKER_SSL_TRUSTSTORE_PASSWORD" \
             --env "IEXEC_CORE_PROTOCOL=$IEXEC_CORE_PROTOCOL" \
             --env "IEXEC_TEE_ENABLED=$IEXEC_TEE_ENABLED" \
             --env "IEXEC_WORKER_BASE_DIR=$RESULTS_DIR" \
	     --env "IEXEC_WORKER_OVERRIDE_BLOCKCHAIN_NODE_ADDRESS=$CHAIN_URL" \
	     --env "IEXEC_WORKER_OVERRIDE_AVAILABLE_CPU_COUNT=${WORKER_AVAILABLE_CPU:-}" \
	     --env "IEXEC_WORKER_GPU_ENABLED=False" \
	     --env " IEXEC_GAS_PRICE_MULTIPLIER=$GAS_PRICE_MULTIPLIER" \
	     --env " IEXEC_GAS_PRICE_CAP=$GAS_PRICE_CAP" \
	     --env " IEXEC_WORKER_SGX_DRIVER_MODE=NONE" \
	     --env " IEXEC_WORKER_DOCKER_REGISTRY_ADDRESS_1=${REGISTRY_ADDRESS:-}" \
	     --env " IEXEC_WORKER_DOCKER_REGISTRY_USERNAME_1=${REGISTRY_USERNAME:-}" \
	     --env " IEXEC_WORKER_DOCKER_REGISTRY_PASSWORD_1=${REGISTRY_PASSWORD:-}" \
	     --env " IEXEC_DEVELOPER_LOGGER_ENABLED=False" \
             -v $WALLET_FILE:/iexec-wallet/encrypted-wallet.json \
             -v /tmp/iexec-worker/${WORKER_NAME}:/tmp/iexec-worker/${WORKER_NAME} \
             -v /var/run/docker.sock:/var/run/docker.sock \
             iexechub/iexec-worker:$WORKER_DOCKER_IMAGE_VERSION
    checkExitStatus $? "Can't start docker container."

    message "INFO" "Created worker $WORKER_POOLNAME-worker."

    #Set to yes to skip user inputs
    startworker=yes
    # Attach to worker container
    while [ "$startworker" != "yes" ] && [ "$startworker" != "no" ]; do
      read -p "Do you want to start worker? [yes/no] " startworker
    done

    if [ "$startworker" == "yes" ]; then
      message "INFO" "Starting worker."
      docker start $WORKER_POOLNAME-worker
      message "INFO" "Worker was successfully started."
	  message "INFO" "If you want to see logs of your worker please relaunch the worker."
    else
      message "INFO" "You can start the worker later with \"docker start $WORKER_POOLNAME-worker\"."
    fi

fi
exit 1
#read -p "Press [Enter] to exit..."
