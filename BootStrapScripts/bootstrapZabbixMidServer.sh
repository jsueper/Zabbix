#!/bin/bash -e
# Zabbix Install Bootstraping
# author: jsueper@amazon.com
# NOTE: This requires GNU getopt.  On Mac OS X and FreeBSD you must install GNU getopt

# Configuration
PROGRAM='Zabbix Install'

##################################### Functions
function checkos() {
    platform='unknown'
    unamestr=`uname`
    if [[ "${unamestr}" == 'Linux' ]]; then
        platform='linux'
    else
        echo "[WARNING] This script is not supported on MacOS or freebsd"
        exit 1
    fi
}

function usage() {
echo "$0 <usage>"
echo " "
echo "options:"
echo -e "-h, --help \t show options for this script"
echo -e "-v, --verbose \t specify to print out verbose bootstrap info"
echo -e "--params_file \t specify the params_file to read (--params_file /tmp/zabbix-setup.txt)"
}

function chkstatus() {
    if [ $? -eq 0 ]
    then
        echo "Script [PASS]"
    else
        echo "Script [FAILED]" >&2
        exit 1
    fi
}

function configRHEL72HVM() {
    sed -i 's/4096/16384/g' /etc/security/limits.d/20-nproc.conf
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
    yum-config-manager --enable rhui-REGION-rhel-server-extras rhui-REGION-rhel-server-optional
    setenforce Permissive
}

function install_packages() {
    echo "[INFO] Calling: yum install -y $@"
    yum install -y $@ > /dev/null
}


##################################### Functions

# Call checkos to ensure platform is Linux
checkos

ARGS=`getopt -o hv -l help,verbose,params_file: -n $0 -- "$@"`
eval set -- "${ARGS}"

if [ $# == 1 ]; then
    echo "No input provided! type ($0 --help) to see usage help" >&2
    exit 2
fi

# extract options and their arguments into variables.
while true; do
    case "$1" in
        -v|--verbose)
            echo "[] DEBUG = ON"
            VERBOSE=true;
            shift
            ;;
        --params_file)
            echo "[] PARAMS_FILE = $2"
            PARAMS_FILE="$2";
            shift 2
            ;;
        --)
            break
            ;;
        *)
            break
            ;;
    esac
done


## Set an initial value
QS_S3_URL='NONE'
QS_S3_BUCKET='NONE'
QS_S3_KEY_PREFIX='NONE'
QS_S3_SCRIPTS_PATH='NONE'
ZABBIX_SERVER='NONE'



if [ -f ${PARAMS_FILE} ]; then
    QS_S3_URL=`grep 'QuickStartS3URL' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    QS_S3_BUCKET=`grep 'QSS3Bucket' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    QS_S3_KEY_PREFIX=`grep 'QSS3KeyPrefix' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    ZABBIX_SERVER=`grep 'ZabbixServer' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`


    # Strip leading slash
    if [[ ${QS_S3_KEY_PREFIX} == /* ]];then
          echo "Removing leading slash"
          QS_S3_KEY_PREFIX=$(echo ${QS_S3_KEY_PREFIX} | sed -e 's/^\///')
    fi

    # Format S3 script path
    QS_S3_SCRIPTS_PATH="${QS_S3_URL}/${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/Scripts"
else
    echo "Paramaters file not found or accessible."
    exit 1
fi

if [[ ${VERBOSE} == 'true' ]]; then
    echo "QS_S3_URL = ${QS_S3_URL}"
    echo "QS_S3_BUCKET = ${QS_S3_BUCKET}"
    echo "QS_S3_KEY_PREFIX = ${QS_S3_KEY_PREFIX}"
    echo "QS_S3_SCRIPTS_PATH = ${QS_S3_SCRIPTS_PATH}"
    echo "ZABBIX_SERVER = ${ZABBIX_SERVER}"


 
fi


#############################################################
# Start Zabbix Install and Database Setup
#############################################################


groupadd -g 54321 zinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
useradd -u 54321 -g zinstall -G dba,oper zabbix
echo QS_Zabbix_user_created

mkdir -p /home/zabbix/.ssh
cp /home/ec2-user/.ssh/authorized_keys /home/zabbix/.ssh/.
chown zabbix:dba /home/zabbix/.ssh /home/zabbix/.ssh/authorized_keys
chmod 600 /home/zabbix/.ssh/authorized_keys
echo 'zabbix ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
sed -i 's/requiretty/!requiretty/g' /etc/sudoers
echo QS_Zabbix_user_sudo_perms_finished

sudo yum update -y
sudo yum install -y awslogs https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo service awslogs start && sudo chkconfig awslogs on

#Since we are using RHEL7.x we need to enable optional repos for the below packages to install
echo QS_Zabbix_Enabling_Optional_RHEL_Repos
configRHEL72HVM

# Install packages needed to run Zabbix
YUM_PACKAGES=(
    wget
    git
    gcc
    ruby-devel
    rubygems
    rake
    java-1.8.0
    telnet
    time
)

echo QS_BEGIN_Install_YUM_Packages
install_packages ${YUM_PACKAGES[@]}
echo QS_COMPLETE_Install_YUM_Packages


sudo unlink /etc/alternatives/java
sudo ln -s /usr/lib/jvm/jre-1.8.0-openjdk.x86_64/bin/java /etc/alternatives/java


sudo service httpd start 
echo ""
echo ""
echo "###############################"



#Go get the RPM for Zabbix
echo QS_BEGIN_Install_Zabbix_Repo
sudo rpm -Uvh https://repo.zabbix.com/zabbix/3.2/rhel/7/x86_64/zabbix-release-3.2-1.el7.noarch
echo QS_END_Install_Zabbix_Repo

#Install Packages from Zabbix RPM for Zabbix Server Setup
ZABBIX_PACKAGES=(
  zabbix-agent
  zabbix-sender
  zabbix-get


)
echo QS_BEGIN_Install_Zabbix_Packages
install_packages ${ZABBIX_PACKAGES[@]}


sudo wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
sudo chmod +x ./jq
sudo cp jq /usr/bin

sudo rpm -Uvh http://repo.rundeck.org/latest.rpm

#Install Packages from RunDeck RPM for Mid Server Setup
RUNDECK_PACKAGES=(
  rundeck
)
echo QS_BEGIN_Install_RunDeck_Packages
install_packages ${RUNDECK_PACKAGES[@]}

echo QS_END_Install_RunDeck_Packages



cd /etc/zabbix/

sudo grep -A20 "### Option: ServerActive" zabbix_agentd.conf | sed -i  "s/ServerActive=127.0.0.1/ServerActive=${ZABBIX_SERVER}/" zabbix_agentd.conf
sudo grep -A20 "### Option: Server" zabbix_agentd.conf | sed -i  "s/Server=127.0.0.1/Server=${ZABBIX_SERVER}/" zabbix_agentd.conf
sudo grep -A20 "### Option: Hostname" zabbix_agentd.conf | sed -i  "s/Hostname=Zabbix server/Hostname=MidServer/" zabbix_agentd.conf
sudo grep -A20 "### Option: HostMetadata" zabbix_agentd.conf | sed -i  "s/# HostMetadata=/HostMetadata=$(uname)   AWS-QuickStart/" zabbix_agentd.conf
sudo grep -A20 "### Option: DebugLevel" zabbix_agentd.conf | sed -i  's/# DebugLevel=3/DebugLevel=5/' zabbix_agentd.conf
sudo grep -A20 "### Option: EnableRemoteCommands" zabbix_agentd.conf | sed -i  's/# EnableRemoteCommands=0/EnableRemoteCommands=1/' zabbix_agentd.conf
sudo grep -A20 "### Option: StartAgents" zabbix_agentd.conf | sed -i  's/# StartAgents=3/StartAgents=3/' zabbix_agentd.conf
sudo grep -A20 "### Option: UnsafeUserParameters" zabbix_agentd.conf | sed -i  's/# UnsafeUserParameters=0/UnsafeUserParameters=1/' zabbix_agentd.conf
sudo grep -A20 "### Option: UserParameter" zabbix_agentd.conf | sed -i  's/# UserParameter=/UserParameter=AWS-QS-TEST,\/home\/ec2-user\/AWS-QS-TESTING\/serverspec.sh/' zabbix_agentd.conf
sudo grep -A20 "### Option: AllowRoot" zabbix_agentd.conf | sed -i  's/# AllowRoot=0/AllowRoot=1/' zabbix_agentd.conf


cd /home/ec2-user

sudo gem install io-console serverspec

mkdir AWS-QS-TESTING

cd AWS-QS-TESTING

aws s3 cp s3://serverspec-test . --recursive

aws s3 cp s3://${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/Scripts/serverspec.sh .

chmod +x serverspec.sh

echo "QS_Restart_All_Services"
sudo service zabbix-agent restart
sudo service rundeckd restart
echo "QS_END_OF_SETUP_ZABBIX"




# END SETUP script

# Remove files used in bootstrapping
rm ${PARAMS_FILE}

#Ensure all services survive reboot
sudo systemctl enable zabbix-agent.service
sudo systemctl enable rundeckd.service

echo "Finished AWS Zabbix Mid Server Quick Start Bootstrapping"
