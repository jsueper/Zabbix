#!/bin/bash -e
# Grafana Install Bootstraping
# author: jsueper@amazon.com
# NOTE: This requires GNU getopt.  On Mac OS X and FreeBSD you must install GNU getopt

# Configuration
PROGRAM='Grafana Install'

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
echo -e "--params_file \t specify the params_file to read (--params_file /tmp/Grafana-setup.txt)"
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


if [[ ${DATABASE_CONN_STRING} != '' ]]; then
    echo "DATABASE_CONN_STRING = ${DATABASE_CONN_STRING}"

fi

#############################################################
# Start Grafana Install and Database Setup
#############################################################




groupadd -g 54321 ginstall
groupadd -g 54322 dba
groupadd -g 54323 oper
useradd -u 54321 -g ginstall -G dba,oper grafana
echo QS_Grafana_user_created

mkdir -p /home/grafana/.ssh
cp /home/ec2-user/.ssh/authorized_keys /home/grafana/.ssh/.
chown grafana:dba /home/Grafana/.ssh /home/grafana/.ssh/authorized_keys
chmod 600 /home/Grafana/.ssh/authorized_keys
echo 'grafana ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
sed -i 's/requiretty/!requiretty/g' /etc/sudoers
echo QS_Grafana_user_sudo_perms_finished

sudo yum update -y
sudo yum install -y awslogs https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo service awslogs start && sudo chkconfig awslogs on

#Since we are using RHEL7.x we need to enable optional repos for the below packages to install
echo QS_Grafana_Enabling_Optional_RHEL_Repos
configRHEL72HVM

# Install packages needed to run Grafana
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


sudo wget http://dev.mysql.com/get/mysql57-community-release-el7-7.noarch.rpm

sudo yum -y localinstall mysql57-community-release-el7-7.noarch.rpm

sudo yum repolist enabled | grep "mysql.*-community.*" 

sudo yum -y install mysql-community-server 


sudo service httpd start 
echo ""
echo ""
echo "###############################"
sleep 30

sudo service mysqld start
echo ""
echo ""
echo "###############################"
sleep 30

sudo service mysqld status 
echo ""
echo ""
echo "###############################"

sudo mysql --version 
echo ""
echo ""
echo "###############################"


#Get Temporary DB Password from mysqld.log
echo QS_BEGIN_Get_Temp_MySql_Password
DBPASS=$(sudo awk '/temporary password/ {print $11}' /var/log/mysqld.log)

echo ""
echo ""
echo ""
echo "###############################"


#Setup Mysql Security - Change Temp Password with Password set from cloud formation
echo QS_BEGIN_Setup_MySql_Secure_Process
mysql -u root --connect-expired-password --password="${DBPASS}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DATABASE_PASS}';"
mysql -u root --password="${DATABASE_PASS}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root --password="${DATABASE_PASS}" -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root --password="${DATABASE_PASS}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';"
mysql -u root --password="${DATABASE_PASS}" -e "FLUSH PRIVILEGES;"

#Go get the RPM for Grafana
echo QS_BEGIN_Install_Grafana_Repo
sudo wget https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-4.3.1-1.x86_64.rpm
echo QS_END_Install_Grafana_Repo

#Install Packages from Grafana RPM for Grafana Server Setup
Grafana_PACKAGES=(
  initscripts
  fontconfig
)


echo QS_BEGIN_Install_Grafana_Packages
install_packages ${Grafana_PACKAGES[@]}
echo QS_END_Install_Grafana_Packages

sudo rpm -Uvh grafana-4.3.1-1.x86_64.rpm

sudo krafana-cli plugins install alexanderzobnin-zabbix-app


#Creating Web Conf So User Doesn't have to go through web setup
if [[ ${DATABASE_CONN_STRING} == 'NA' ]]; then

echo QS_BEGIN_Create_Grafana_MySql_Web_Conf_File



#Create the Grafana database
echo QS_BEGIN_Create_Grafana_MySql_Database
mysql -u root --password="${DATABASE_PASS}" -e "CREATE DATABASE grafana CHARACTER SET UTF8;"
mysql -u root --password="${DATABASE_PASS}" -e "GRANT ALL PRIVILEGES on grafana.* to ${DATABASE_USER}@localhost IDENTIFIED BY '${DATABASE_PASS}';"
mysql -u root --password="${DATABASE_PASS}" -e "FLUSH PRIVILEGES;"
echo QS_END_Create_Grafana_MySql_Database



fi

if [[ ${DATABASE_CONN_STRING} != 'NA' ]]; then

echo QS_BEGIN_Create_Grafana_Aurora_Web_Conf_File

sudo echo 'DBHost='${DATABASE_CONN_STRING} >>/etc/Grafana/Grafana_server.conf
sudo echo 'DBPort=3306' >>/etc/Grafana/Grafana_server.conf



#Create the Grafana database
echo QS_BEGIN_Create_Grafana_Aurora_Database

mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" -e "CREATE DATABASE grafana CHARACTER SET UTF8;"
echo QS_END_Create_Grafana_Aurora_Database


cd /tmp

sudo touch create_grafana_session.sql

chown grafana:dba create_grafana_session.sql

sudo echo "create table 'session' ('key' char(16) not null, 'data' blob, 'expiry' init(11) unsigned not null, primary key ('key'))  ENGINE=MyISAM default charset=uf8;" >> create_grafana_session.sql

#Unzip Create.sql.gz file
#Run create.sql file against Grafanadb we created above to create user session schema.
echo QS_BEGIN_Apply_Grafana_Aurora_Schema
mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" grafana < create_grafana_session.sql
echo QS_END_Apply_Grafana_Aurora_Schema

fi

echo QS_END_Create_Grafana_Web_Conf_File

sudo service httpd restart

sudo service Grafana-server restart

# Remove passwords from files
sed -i s/${DATABASE_PASS}/xxxxx/g  /var/log/cloud-init.log

echo "QS_END_OF_SETUP_Grafana"
# END SETUP script

# Remove files used in bootstrapping
rm ${PARAMS_FILE}

#Ensure all services survive reboot
sudo systemctl enable mysqld.service
sudo systemctl enable httpd.service
sudo systemctl enable grafana-server.service

echo "Finished AWS Grafana Quick Start Bootstrapping"
