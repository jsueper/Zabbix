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
DATABASE_PASS='NONE'
DATABASE_USER='NONE'
DATABASE_CONN_STRING='NONE'


if [ -f ${PARAMS_FILE} ]; then
    QS_S3_URL=`grep 'QuickStartS3URL' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    QS_S3_BUCKET=`grep 'QSS3Bucket' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    QS_S3_KEY_PREFIX=`grep 'QSS3KeyPrefix' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    DATABASE_PASS=`grep 'DatabasePass' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    DATABASE_USER=`grep 'DatabaseUser' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    DATABASE_CONN_STRING=`grep 'DBConnString' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`


    # Strip leading slash
    if [[ ${QS_S3_KEY_PREFIX} == /* ]];then
          echo "Removing leading slash"
          QS_S3_KEY_PREFIX=$(echo ${QS_S3_KEY_PREFIX} | sed -e 's/^\///')
    fi

    # Format S3 script path
    QS_S3_SCRIPTS_PATH="${QS_S3_URL}/${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/scripts"
else
    echo "Paramaters file not found or accessible."
    exit 1
fi

if [[ ${VERBOSE} == 'true' ]]; then
    echo "QS_S3_URL = ${QS_S3_URL}"
    echo "QS_S3_BUCKET = ${QS_S3_BUCKET}"
    echo "QS_S3_KEY_PREFIX = ${QS_S3_KEY_PREFIX}"
    echo "QS_S3_SCRIPTS_PATH = ${QS_S3_SCRIPTS_PATH}"
    echo "DATABASE_PASS = ${DATABASE_PASS}"
    echo "DATABASE_USER = ${DATABASE_USER}"
    echo "DATABASE_CONN_STRING = ${DATABASE_CONN_STRING}"

 
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
    httpd
    httpd-devel 
    wget
    php
    php-cli
    php-common
    php-devel
    php-pear
    php-gd
    php-mbstring
    php-bcmath
    php-mysql
    php-xml
)

echo QS_BEGIN_Install_YUM_Packages
install_packages ${YUM_PACKAGES[@]}
echo QS_COMPLETE_Install_YUM_Packages


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
  zabbix-java-gateway
  zabbix-sender

)
echo QS_BEGIN_Install_Zabbix_Packages
install_packages ${ZABBIX_PACKAGES[@]}
echo QS_END_Install_Zabbix_Packages


sudo grep -A21 "\[database\]" grafana.ini | sed -i  's/;type = sqlite3/type = mysql/' grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i  "s/;host = 127.*/host = ${DATABASE_CONN_STRING}:3306/" grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i  "s/;user = root/user = ${DATABASE_USER}/" grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i  "s/;password =/password = ${DATABASE_PASS}/" grafana.ini

sudo grep -A21 "\[security\]" grafana.ini | sed -i  "s/;admin_user = admin/admin_user = ${DATABASE_USER}/" grafana.ini
sudo grep -A21 "\[security\]" grafana.ini | sed -i  "s/;admin_password = admin/admin_password = ${DATABASE_PASS}/" grafana.ini


sudo echo "HostMetadata=ServerSpecTest    21df83bf21bf0be663090bb8d4128558ab9b95fba66a6dbf834f8b91ae5e08ae"  >> /etc/zabbix/zabbix-agents.conf

sudo echo "HostMetadataItem=system.uname"  >> /etc/zabbix/zabbix-agentd.conf



echo "QS_Restart_All_Services"
sudo service httpd restart
sudo service zabbix-sender restart
sudo service zabbix-agent restart

# Remove passwords from files
sed -i s/${DATABASE_PASS}/xxxxx/g  /var/log/cloud-init.log

echo "QS_END_OF_SETUP_ZABBIX"
# END SETUP script

# Remove files used in bootstrapping
rm ${PARAMS_FILE}

#Ensure all services survive reboot
sudo systemctl enable mysqld.service
sudo systemctl enable httpd.service
sudo systemctl enable zabbix-server.service
sudo systemctl enable zabbix-agent.service

echo "Finished AWS Zabbix Quick Start Bootstrapping"
