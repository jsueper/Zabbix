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
QS_S3_SERVERSPEC_BUCKET='NONE'
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
    QS_S3_SERVERSPEC_BUCKET=`grep 'QSServerSpecBucketName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`

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

# Increase Ulimits
ulimit -n 300000


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
    MySQL-python

)

echo QS_BEGIN_Install_YUM_Packages
install_packages ${YUM_PACKAGES[@]}
echo QS_COMPLETE_Install_YUM_Packages

pip install boto3
pip install pyzabbix

sudo wget http://dev.mysql.com/get/mysql57-community-release-el7-7.noarch.rpm

sudo yum -y localinstall mysql57-community-release-el7-7.noarch.rpm

sudo yum repolist enabled | grep "mysql.*-community.*" 

sudo yum -y install mysql-community-server 


sudo service httpd start 
echo ""
echo ""
echo "###############################"


sudo service mysqld start
echo ""
echo ""
echo "###############################"


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

#Go get the RPM for Zabbix
echo QS_BEGIN_Install_Zabbix_Repo
sudo rpm -Uvh https://repo.zabbix.com/zabbix/3.2/rhel/7/x86_64/zabbix-release-3.2-1.el7.noarch
echo QS_END_Install_Zabbix_Repo

#Install Packages from Zabbix RPM for Zabbix Server Setup
ZABBIX_PACKAGES=(
  zabbix-server-mysql
  zabbix-web-mysql
  zabbix-agent
  zabbix-java-gateway
  zabbix-sender
  zabbix-get

)
echo QS_BEGIN_Install_Zabbix_Packages
install_packages ${ZABBIX_PACKAGES[@]}
echo QS_END_Install_Zabbix_Packages

sudo wget -O jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
sudo chmod +x ./jq
sudo cp jq /usr/bin

#Need to set timezone as Zabbix install depends on it.

sed -e 's/# php_value date.timezone Europe\/Riga/php_value date.timezone America\/Denver/g' /etc/httpd/conf.d/zabbix.conf > /etc/httpd/conf.d/zabbix_new.conf
sudo mv /etc/httpd/conf.d/zabbix_new.conf /etc/httpd/conf.d/zabbix.conf

echo QS_BEGIN_Update_Zabbix_Server_Conf
sudo echo 'DBPassword='${DATABASE_PASS} >>/etc/zabbix/zabbix_server.conf

sed -e 's/DBUser=zabbix/DBUser='${DATABASE_USER}'/g' /etc/zabbix/zabbix_server.conf > /etc/zabbix/zabbix_server_new.conf
sudo mv /etc/zabbix/zabbix_server_new.conf /etc/zabbix/zabbix_server.conf



#Creating Web Conf So User Doesn't have to go through web setup
if [[ ${DATABASE_CONN_STRING} == 'NA' ]]; then

echo QS_BEGIN_Create_Zabbix_MySql_Web_Conf_File

sudo touch /etc/zabbix/web/zabbix.conf.php
sudo chown root:zabbix /etc/zabbix/web/zabbix.conf.php

sudo echo '<?php' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '// Zabbix GUI configuration file.' >>/etc/zabbix/web/zabbix.conf.php
sudo echo 'global $DB;' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '' >>/etc/zabbix/web/zabbix.conf.php

sudo echo '$DB['\'TYPE\'']     = '\'MYSQL\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'SERVER\'']   = '\'localhost\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'PORT\'']     = '\'0\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'DATABASE\''] = '\'zabbix\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'USER\'']     = '\'${DATABASE_USER}\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'PASSWORD\''] = '\'${DATABASE_PASS}\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '' >>/etc/zabbix/web/zabbix.conf.php

sudo echo '// Schema name. Used for IBM DB2 and PostgreSQL.' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'SCHEMA\''] = '\'\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$ZBX_SERVER      = '\'localhost\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$ZBX_SERVER_PORT = '\'10051\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$ZBX_SERVER_NAME = '\'ZABBIX\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;' >>/etc/zabbix/web/zabbix.conf.php



#Create the Zabbix database
echo QS_BEGIN_Create_Zabbix_MySql_Database
mysql -u root --password="${DATABASE_PASS}" -e "CREATE DATABASE zabbix CHARACTER SET UTF8;"
mysql -u root --password="${DATABASE_PASS}" -e "GRANT ALL PRIVILEGES on zabbix.* to ${DATABASE_USER}@localhost IDENTIFIED BY '${DATABASE_PASS}';"
mysql -u root --password="${DATABASE_PASS}" -e "FLUSH PRIVILEGES;"
echo QS_END_Create_Zabbix_MySql_Database

#Move to Directory where Zabbix Mysql Server is
cd /usr/share/doc/zabbix-server-mysql-3.*/

#Unzip Create.sql.gz file
#Run create.sql file against zabbixdb we created above to create schema and data.
echo QS_BEGIN_Apply_Zabbix_MySql_Schema
gunzip *.gz
mysql -u zabbix --password="${DATABASE_PASS}" zabbix < create.sql
echo QS_END_Apply_Zabbix_MySql_Schema

fi

if [[ ${DATABASE_CONN_STRING} != 'NA' ]]; then

echo QS_BEGIN_Create_Zabbix_Aurora_Web_Conf_File

sudo echo 'DBHost='${DATABASE_CONN_STRING} >>/etc/zabbix/zabbix_server.conf
sudo echo 'DBPort=3306' >>/etc/zabbix/zabbix_server.conf

sudo touch /etc/zabbix/web/zabbix.conf.php
sudo chown root:zabbix /etc/zabbix/web/zabbix.conf.php

sudo echo '<?php' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '// Zabbix GUI configuration file.' >>/etc/zabbix/web/zabbix.conf.php
sudo echo 'global $DB;' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '' >>/etc/zabbix/web/zabbix.conf.php

sudo echo '$DB['\'TYPE\'']     = '\'MYSQL\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'SERVER\'']   = '\'${DATABASE_CONN_STRING}\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'PORT\'']     = '\'3306\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'DATABASE\''] = '\'zabbix\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'USER\'']     = '\'${DATABASE_USER}\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'PASSWORD\''] = '\'${DATABASE_PASS}\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '' >>/etc/zabbix/web/zabbix.conf.php

sudo echo '// Schema name. Used for IBM DB2 and PostgreSQL.' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$DB['\'SCHEMA\''] = '\'\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$ZBX_SERVER      = '\'localhost\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$ZBX_SERVER_PORT = '\'10051\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$ZBX_SERVER_NAME = '\'ZABBIX\'';' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '' >>/etc/zabbix/web/zabbix.conf.php
sudo echo '$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;' >>/etc/zabbix/web/zabbix.conf.php

#Create the Zabbix database
echo QS_BEGIN_Create_Zabbix_Aurora_Database

mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" -e "CREATE DATABASE zabbix CHARACTER SET UTF8;"

echo QS_END_Create_Zabbix_Aurora_Database


#Move to Director where Zabbix Mysql Server is
cd /usr/share/doc/zabbix-server-mysql-3.*/

#Unzip Create.sql.gz file
#Run create.sql file against zabbixdb we created above to create schema and data.
echo QS_BEGIN_Apply_Zabbix_Aurora_Schema
gunzip *.gz
mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" zabbix < create.sql
echo QS_END_Apply_Zabbix_Aurora_Schema



echo QS_BEGIN_Apply_Zabbix_Aurora_Default_Password_Update
sudo touch create_grafana_session.sql
chown root:zabbix create_grafana_session.sql

sudo echo "INSERT INTO \`users\` (\`userid\`,\`alias\`,\`name\`,\`surname\`,\`passwd\`,\`url\`,\`autologin\`,\`autologout\`,\`lang\`,\`refresh\`,\`type\`,\`theme\`,\`rows_per_page\`) values ('3','${DATABASE_USER}','AWS','QUICKSTART', md5('${DATABASE_PASS}'),'','1','0','en_GB','30','3','default','50');" >> update_zabbix_password.sql

sudo echo "INSERT INTO \`users_groups\` (\`id\`,\`usrgrpid\`,\`userid\`) values ('6','7','3');"  >> update_zabbix_password.sql
sudo echo "update zabbix.users set passwd=md5('${DATABASE_PASS}') where alias='Admin';"  >> update_zabbix_password.sql
sudo echo "update zabbix.users set passwd=md5('${DATABASE_PASS}') where alias='Guest';"  >> update_zabbix_password.sql

echo QS_Enable_Zabbix_Agent_UI
sudo echo "update zabbix.hosts set status='0' where host='Zabbix server';"  >> update_zabbix_password.sql


mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" zabbix < update_zabbix_password.sql

echo QS_END_Apply_Zabbix_Aurora_Default_Password_Update



sudo echo "INSERT INTO \`groups\`  (\`groupid\`,\`name\`,\`internal\`,\`flags\`) values ('8', 'AWS-QuickStart', '0','1');"  >> create_aws_quickstart.sql

sudo echo "update zabbix.ids set nextid='8' where table_name='groups';"  >> create_aws_quickstart.sql




sudo echo "INSERT INTO \`actions\`  (\`actionid\`,\`name\`,\`eventsource\`,\`evaltype\`,\`status\`,\`esc_period\`,\`def_shortdata\`,\`def_longdata\`,\`r_shortdata\`,\`r_longdata\`,\`formula\`,\`maintenance_mode\`) values ('7', 'AWSQS Register Agent - Linux', '2', '1', '0', '0', 'Auto registration: {HOST.HOST}', 'Host name: {HOST.HOST}\r\nHost IP: {HOST.IP}\r\nAgent port: {HOST.PORT}', '', '', '', '1');"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`actions\`  (\`actionid\`,\`name\`,\`eventsource\`,\`evaltype\`,\`status\`,\`esc_period\`,\`def_shortdata\`,\`def_longdata\`,\`r_shortdata\`,\`r_longdata\`,\`formula\`,\`maintenance_mode\`) values ('8', 'AWSQS Register Agent - Windows', '2', '1', '0', '0', 'Auto registration: {HOST.HOST}', 'Host name: {HOST.HOST}\r\nHost IP: {HOST.IP}\r\nAgent port: {HOST.PORT}', '', '', '', '1');"  >> create_aws_quickstart.sql

sudo echo "update zabbix.ids set nextid='8' where table_name='actions';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`hosts\`  (\`hostid\`,\`proxy_hostid\`,\`host\`,\`status\`,\`disable_until\`,\`error\`,\`available\`,\`errors_from\`,\`lastaccess\`,\`ipmi_authtype\`,\`ipmi_privilege\`,\`ipmi_username\`,\`ipmi_password\`,\`ipmi_disable_until\`,\`ipmi_available\`,\`snmp_disable_until\`,\`snmp_available\`,\`maintenanceid\`,\`maintenance_status\`,\`maintenance_type\`,\`maintenance_from\`,\`ipmi_errors_from\`,\`snmp_errors_from\`,\`ipmi_error\`,\`snmp_error\`,\`jmx_disable_until\`,\`jmx_available\`,\`jmx_errors_from\`,\`jmx_error\`,\`name\`,\`flags\`,\`templateid\`,\`description\`,\`tls_connect\`,\`tls_accept\`,\`tls_issuer\`,\`tls_subject\`,\`tls_psk_identity\`,\`tls_psk\`) values ('10106', NULL, 'AWSQS-Linux-Template', '3', '0', '', '0', '0', '0', '0', '2', '', '', '0', '0', '0', '0', NULL, '0', '0', '0', '0', '0', '', '', '0', '0', '0', '', 'AWSQS-Template', '0', NULL, '', '1', '1', '', '', '', '');"  >> create_aws_quickstart.sql


sudo echo "update zabbix.ids set nextid='10106' where table_name='hosts';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`hosts_groups\`  (\`hostgroupid\`,\`hostid\`,\`groupid\`) values ('113', '10106', '1');"  >> create_aws_quickstart.sql

#sudo echo "INSERT INTO \`hosts_groups\`  (\`hostgroupid\`,\`hostid\`,\`groupid\`) values ('114', '10107', '5');"  >> create_aws_quickstart.sql

sudo echo "update zabbix.ids set nextid='113' where table_name='hosts_groups';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`operations\`  (\`operationid\`,\`actionid\`,\`operationtype\`,\`esc_period\`,\`esc_step_from\`,\`esc_step_to\`,\`evaltype\`,\`recovery\`) values ('12', '7', '6', '0', '1', '1', '0', '0');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`operations\`  (\`operationid\`,\`actionid\`,\`operationtype\`,\`esc_period\`,\`esc_step_from\`,\`esc_step_to\`,\`evaltype\`,\`recovery\`) values ('13', '8', '6', '0', '1', '1', '0', '0');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`operations\`  (\`operationid\`,\`actionid\`,\`operationtype\`,\`esc_period\`,\`esc_step_from\`,\`esc_step_to\`,\`evaltype\`,\`recovery\`) values ('14', '8', '4', '0', '1', '1', '0', '0');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`operations\`  (\`operationid\`,\`actionid\`,\`operationtype\`,\`esc_period\`,\`esc_step_from\`,\`esc_step_to\`,\`evaltype\`,\`recovery\`) values ('15', '7', '4', '0', '1', '1', '0', '0');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`operations\`  (\`operationid\`,\`actionid\`,\`operationtype\`,\`esc_period\`,\`esc_step_from\`,\`esc_step_to\`,\`evaltype\`,\`recovery\`) values ('16', '7', '6', '0', '1', '1', '0', '0');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`operations\`  (\`operationid\`,\`actionid\`,\`operationtype\`,\`esc_period\`,\`esc_step_from\`,\`esc_step_to\`,\`evaltype\`,\`recovery\`) values ('17', '7', '1', '0', '1', '1', '0', '0');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`operations\`  (\`operationid\`,\`actionid\`,\`operationtype\`,\`esc_period\`,\`esc_step_from\`,\`esc_step_to\`,\`evaltype\`,\`recovery\`) values ('18', '8', '1', '0', '1', '1', '0', '0');"  >> create_aws_quickstart.sql

sudo echo "update zabbix.ids set nextid='18' where table_name='operations';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`opcommand\`  (\`operationid\`,\`type\`,\`scriptid\`,\`execute_on\`,\`port\`,\`authtype\`,\`username\`,\`password\`,\`publickey\`,\`privatekey\`,\`command\`) values ('17', '0', NULL, '1', '', '0', '', '', '', '', 'sudo /usr/lib/zabbix/externalscripts/get_account_and_stack.sh {HOST.HOST}  {HOST.IP}');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`opcommand\`  (\`operationid\`,\`type\`,\`scriptid\`,\`execute_on\`,\`port\`,\`authtype\`,\`username\`,\`password\`,\`publickey\`,\`privatekey\`,\`command\`) values ('18', '0', NULL, '1', '', '0', '', '', '', '', 'sudo /usr/lib/zabbix/externalscripts/get_account_and_stack.sh {HOST.HOST}  {HOST.IP}');"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`opcommand_hst\`  (\`opcommand_hstid\`,\`operationid\`,\`hostid\`) values ('1', '17', NULL);"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`opcommand_hst\`  (\`opcommand_hstid\`,\`operationid\`,\`hostid\`) values ('2', '18', NULL);"  >> create_aws_quickstart.sql

sudo echo "update zabbix.ids set nextid='2' where table_name='opcommand_hst';"  >> create_aws_quickstart.sql



sudo echo "INSERT INTO \`opgroup\`  (\`opgroupid\`,\`operationid\`,\`groupid\`) values ('3', '14', '8');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`opgroup\`  (\`opgroupid\`,\`operationid\`,\`groupid\`) values ('4', '15', '8');"  >> create_aws_quickstart.sql


sudo echo "update zabbix.ids set nextid='4' where table_name='opgroup';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`optemplate\`  (\`optemplateid\`,\`operationid\`,\`templateid\`) values ('2', '12', '10001');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`optemplate\`  (\`optemplateid\`,\`operationid\`,\`templateid\`) values ('3', '13', '10081');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`optemplate\`  (\`optemplateid\`,\`operationid\`,\`templateid\`) values ('4', '16', '10106');"  >> create_aws_quickstart.sql


sudo echo "update zabbix.ids set nextid='4' where table_name='optemplate';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`conditions\`  (\`conditionid\`,\`actionid\`,\`conditiontype\`,\`operator\`,\`value\`,\`value2\`) values ('9', '7', '24', '2', 'AWS-QuickStart', '');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`conditions\`  (\`conditionid\`,\`actionid\`,\`conditiontype\`,\`operator\`,\`value\`,\`value2\`) values ('10', '7', '24', '2', 'Linux', '');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`conditions\`  (\`conditionid\`,\`actionid\`,\`conditiontype\`,\`operator\`,\`value\`,\`value2\`) values ('11', '8', '24', '2', 'Windows', '');"  >> create_aws_quickstart.sql

sudo echo "INSERT INTO \`conditions\`  (\`conditionid\`,\`actionid\`,\`conditiontype\`,\`operator\`,\`value\`,\`value2\`) values ('12', '8', '24', '2', 'AWS-QuickStart', '');"  >> create_aws_quickstart.sql


sudo echo "update zabbix.ids set nextid='12' where table_name='conditions';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`applications\`  (\`applicationid\`,\`hostid\`,\`name\`,\`flags\`) values ('469', '10106', 'AWSQuickStart', '0');"  >> create_aws_quickstart.sql


sudo echo "update zabbix.ids set nextid='469' where table_name='applications';"  >> create_aws_quickstart.sql



sudo echo "INSERT INTO \`items\`  (\`itemid\`,\`type\`,\`snmp_community\`,\`snmp_oid\`,\`hostid\`,\`name\`,\`key_\`,\`delay\`,\`history\`,\`trends\`,\`status\`,\`value_type\`,\`trapper_hosts\`,\`units\`,\`multiplier\`,\`delta\`,\`snmpv3_securityname\`,\`snmpv3_securitylevel\`,\`snmpv3_authpassphrase\`,\`snmpv3_privpassphrase\`,\`formula\`,\`error\`,\`lastlogsize\`,\`logtimefmt\`,\`templateid\`,\`valuemapid\`,\`delay_flex\`,\`params\`,\`ipmi_sensor\`,\`data_type\`,\`authtype\`,\`username\`,\`password\`,\`publickey\`,\`privatekey\`,\`mtime\`,\`flags\`,\`interfaceid\`,\`port\`,\`description\`,\`inventory_link\`,\`lifetime\`,\`snmpv3_authprotocol\`,\`snmpv3_privprotocol\`,\`state\`,\`snmpv3_contextname\`,\`evaltype\`) values ('25531', '0', '', '', '10106', 'AWS-QS-TEST', 'AWS-QS-TEST', '30', '90', '0', '0', '4', '', '', '0', '0', '', '0', '', '', '', '', '0', '', NULL, NULL, '', '', '', '0', '0', '', '', '', '', '0', '1', NULL, '', '', '0', '30', '0', '0', '0', '', '0');"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`items\`  (\`itemid\`,\`type\`,\`snmp_community\`,\`snmp_oid\`,\`hostid\`,\`name\`,\`key_\`,\`delay\`,\`history\`,\`trends\`,\`status\`,\`value_type\`,\`trapper_hosts\`,\`units\`,\`multiplier\`,\`delta\`,\`snmpv3_securityname\`,\`snmpv3_securitylevel\`,\`snmpv3_authpassphrase\`,\`snmpv3_privpassphrase\`,\`formula\`,\`error\`,\`lastlogsize\`,\`logtimefmt\`,\`templateid\`,\`valuemapid\`,\`delay_flex\`,\`params\`,\`ipmi_sensor\`,\`data_type\`,\`authtype\`,\`username\`,\`password\`,\`publickey\`,\`privatekey\`,\`mtime\`,\`flags\`,\`interfaceid\`,\`port\`,\`description\`,\`inventory_link\`,\`lifetime\`,\`snmpv3_authprotocol\`,\`snmpv3_privprotocol\`,\`state\`,\`snmpv3_contextname\`,\`evaltype\`) values ('25552', '2', '', '', '10106', 'Test - {#TEST}', 'test[{#TEST}]', '0', '90', '0', '0', '3', '', '', '0', '0', '', '0', '', '', '1', '', '0', '', NULL, NULL, '', '', '', '0', '0', '', '', '', '', '0', '2', NULL, '', '', '0', '30', '0', '0', '0', '', '0');"  >> create_aws_quickstart.sql


sudo echo "update zabbix.ids set nextid='25552' where table_name='items';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`items_applications\`  (\`itemappid\`,\`applicationid\`,\`itemid\`) values ('5965', '469', '25552');"  >> create_aws_quickstart.sql

sudo echo "update zabbix.ids set nextid='5965' where table_name='items_applications';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`item_discovery\`  (\`itemdiscoveryid\`,\`itemid\`,\`parent_itemid\`,\`key_\`,\`lastcheck\`,\`ts_delete\`) values ('312', '25552', '25531', '', '0', '0');"  >> create_aws_quickstart.sql

sudo echo "update zabbix.ids set nextid='312' where table_name='item_discovery';"  >> create_aws_quickstart.sql


sudo echo "INSERT INTO \`scripts\`  (\`scriptid\`,\`name\`,\`command\`,\`host_access\`,\`usrgrpid\`,\`groupid\`,\`description\`,\`confirmation\`,\`type\`,\`execute_on\`) values ('4', 'Update ServerSpec Test', 'cd /home/ec2-user/AWS-QS-TESTING && sudo aws s3 cp s3://${QS_S3_SERVERSPEC_BUCKET} . --recursive', '3', NULL, '8', '', 'Are you sure?', '0', '0');"  >> create_aws_quickstart.sql


mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" zabbix < create_aws_quickstart.sql

fi

echo QS_END_Create_Zabbix_Web_Conf_File



cd /etc/zabbix/

sudo grep -A20 "### Option: DebugLevel" zabbix_agentd.conf | sed -i  's/# DebugLevel=3/DebugLevel=5/' zabbix_agentd.conf
sudo grep -A20 "### Option: EnableRemoteCommands" zabbix_agentd.conf | sed -i  's/# EnableRemoteCommands=0/EnableRemoteCommands=1/' zabbix_agentd.conf
sudo grep -A20 "### Option: StartAgents" zabbix_agentd.conf | sed -i  's/# StartAgents=3/StartAgents=3/' zabbix_agentd.conf
sudo grep -A20 "### Option: UnsafeUserParameters" zabbix_agentd.conf | sed -i  's/# UnsafeUserParameters=0/UnsafeUserParameters=1/' zabbix_agentd.conf
sudo grep -A20 "### Option: AllowRoot" zabbix_agentd.conf | sed -i  's/# AllowRoot=0/AllowRoot=1/' zabbix_agentd.conf


echo "QS_Restart_All_Services"
sudo service httpd restart
sudo service zabbix-server restart
sudo service zabbix-agent restart



mkdir -p /etc/zabbix/midscripts/zabbix-gnomes

cd /etc/zabbix/midscripts/zabbix-gnomes

aws s3 cp s3://${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/Scripts/zhostupdater.py .

aws s3 cp s3://${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/Scripts/zhtmplfinder.py .

cd /usr/lib/zabbix/externalscripts

aws s3 cp s3://${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/Scripts/get_account_and_stack.sh .

chmod +x get_account_and_stack.sh

mkdir -p /usr/lib/zabbix/scripts

cd /usr/lib/zabbix/scripts

aws s3 cp s3://${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/Scripts/get_account_alias.sh  .

chmod +x get_account_alias.sh

aws s3 cp s3://${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/Scripts/get_instance_stack.sh .

chmod +x get_instance_stack.sh


#create zabbix conf dir
sudo mkdir -p /root
cd /root

cat <<EOF > .zbx.conf
[Zabbix API]
username=${DATABASE_USER}
password=${DATABASE_PASS}
api=http://localhost/zabbix
no_verify=true
EOF

#midscript api config
ln -s /root/.zbx.conf /etc/zabbix/midscripts/zabbix-gnomes/zbx.conf


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
