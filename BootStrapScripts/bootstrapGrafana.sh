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
ZABBIX_URL='NONE'


if [ -f ${PARAMS_FILE} ]; then
    QS_S3_URL=`grep 'QuickStartS3URL' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    QS_S3_BUCKET=`grep 'QSS3Bucket' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    QS_S3_KEY_PREFIX=`grep 'QSS3KeyPrefix' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    DATABASE_PASS=`grep 'DatabasePass' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    DATABASE_USER=`grep 'DatabaseUser' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    DATABASE_CONN_STRING=`grep 'DBConnString' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    ZABBIX_URL=`grep 'ZabbixURL' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`


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
    echo "ZABBIX_URL = ${ZABBIX_URL}"

 
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
chown grafana:dba /home/grafana/.ssh /home/grafana/.ssh/authorized_keys
chmod 600 /home/grafana/.ssh/authorized_keys
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

echo QS_BEGIN_Install_Grafana_Zabbix_Plugin
sudo grafana-cli plugins install alexanderzobnin-zabbix-app

sudo grafana-cli plugins install vonage-status-panel

grafana-cli plugins install briangann-datatable-panel

echo QS_END_Install_Grafana_Zabbix_Plugin

#Creating Web Conf So User Doesn't have to go through web setup
if [[ ${DATABASE_CONN_STRING} == 'NA' ]]; then


#Create the Grafana Mysql database
echo QS_BEGIN_Create_Grafana_MySql_Database
mysql -u root --password="${DATABASE_PASS}" -e "CREATE DATABASE grafana CHARACTER SET UTF8;"
mysql -u root --password="${DATABASE_PASS}" -e "GRANT ALL PRIVILEGES on grafana.* to ${DATABASE_USER}@localhost IDENTIFIED BY '${DATABASE_PASS}';"
mysql -u root --password="${DATABASE_PASS}" -e "FLUSH PRIVILEGES;"
echo QS_END_Create_Grafana_MySql_Database


cd /etc/grafana/

sudo grep -A21 "\[database\]" grafana.ini | sed -i 's/;type = sqlite3/type = mysql/' grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i "s/;host = 127.*/host = 127.0.0.1:3306/" grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i "s/;user = root/user = ${DATABASE_USER}/" grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i "s/;password =/password = ${DATABASE_PASS}/" grafana.ini

sudo grep -A21 "\[session\]" grafana.ini | sed -i 's/;provider = file/provider = mysql/' grafana.ini
sudo grep -A21 "\[session\]" grafana.ini | sed -i "s/;provider_config = sessions/provider_config = ${DATABASE_USER}:${DATABASE_PASS}@tcp(127.0.0.1:3306)\/grafana/" grafana.ini


cd /tmp

sudo touch create_grafana_session.sql

chown root:grafana create_grafana_session.sql

echo QS_BEGIN_Create_Grafana_Aurora_Sessions_Table
sudo echo "create table session("  >> create_grafana_session.sql
sudo echo "\`key\` char(16) not null,"  >> create_grafana_session.sql
sudo echo "data blob,"  >> create_grafana_session.sql
sudo echo "expiry int(11) unsigned not null,"  >> create_grafana_session.sql
sudo echo "primary key (\`key\`))"  >> create_grafana_session.sql
sudo echo "ENGINE=MyISAM default charset=UTF8;" >> create_grafana_session.sql

#Run create.sql file against Grafanadb we created above to create user session schema.

mysql --user=${DATABASE_USER} --password="${DATABASE_PASS}" grafana < create_grafana_session.sql




sudo service grafana-server restart

sudo touch enable_zabbix_plugin.sql

chown root:grafana enable_zabbix_plugin.sql
if [[ ${ZABBIX_URL} != 'NA' ]]; then

sudo echo "INSERT INTO \`data_source\` (\`id\`,\`org_id\`,\`version\`,\`type\`,\`name\`,\`access\`,\`url\`,\`password\`,\`user\`,\`database\`,\`basic_auth\`,\`basic_auth_user\`,\`basic_auth_password\`,\`is_default\`,\`json_data\`,\`created\`,\`updated\`,\`with_credentials\`,\`secure_json_data\`) values ('1','1','1','alexanderzobnin-zabbix-datasource','ZabbixDS','proxy','${ZABBIX_URL}','','','','0','${DATABASE_USER}','api_jsonrpc.php','1','{\"addThresholds\":true,\"alerting\":true,\"alertingMinSeverity\":1,\"cacheTTL\":\"1h\",\"password\":\"${DATABASE_PASS}\",\"trends\":true,\"trendsFrom\":\"7d\",\"trendsRange\":\"4d\",\"username\":\"${DATABASE_USER}\"}',CURDATE(),CURDATE(),'0','{}');"  >> enable_zabbix_plugin.sql

fi

sudo echo "INSERT INTO \`plugin_setting\` (\`id\`,\`org_id\`,\`plugin_id\`,\`enabled\`,\`pinned\`,\`json_data\`,\`secure_json_data\`,\`created\`,\`updated\`,\`plugin_version\`) values ('1','1','alexanderzobnin-zabbix-app','1','1','null','{}',CURDATE(),CURDATE(), '3.4.0');"  >> enable_zabbix_plugin.sql


sudo echo "INSERT INTO \`dashboard\` (\`id\`,\`version\`,\`slug\`,\`title\`,\`data\`,\`org_id\`,\`created\`,\`updated\`,\`updated_by\`,\`created_by\`,\`gnet_id\`,\`plugin_id\`) values ('1', '0', 'zabbix-server-dashboard', 'Zabbix Server Dashboard', '{\"annotations\":{\"list\":[]},\"editable\":true,\"hideControls\":false,\"id\":null,\"links\":[],\"originalTitle\":\"Zabbix Server Dashboard\",\"rows\":[{\"collapse\":false,\"editable\":true,\"height\":\"100px\",\"panels\":[{\"cacheTimeout\":null,\"colorBackground\":false,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"editable\":true,\"error\":false,\"format\":\"none\",\"id\":3,\"interval\":null,\"isNew\":true,\"links\":[],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"span\":4,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"targets\":[{\"application\":{\"filter\":\"General\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"Host name\"},\"mode\":2,\"refId\":\"A\"}],\"thresholds\":\"\",\"title\":\"Host name\",\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"N/A\",\"value\":\"null\"}],\"valueName\":\"avg\"},{\"cacheTimeout\":null,\"colorBackground\":false,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"decimals\":0,\"editable\":true,\"error\":false,\"format\":\"s\",\"id\":4,\"interval\":null,\"isNew\":true,\"links\":[],\"maxDataPoints\":\"\",\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"span\":4,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"targets\":[{\"application\":{\"filter\":\"General\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"System uptime\"},\"mode\":0,\"refId\":\"A\"}],\"thresholds\":\"\",\"title\":\"Uptime\",\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"N/A\",\"value\":\"null\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":false,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"editable\":true,\"error\":false,\"format\":\"none\",\"id\":5,\"interval\":null,\"isNew\":true,\"links\":[],\"maxDataPoints\":\"\",\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"span\":4,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"targets\":[{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/Required performance of Zabbix server/\"},\"mode\":0,\"refId\":\"A\"}],\"thresholds\":\"\",\"title\":\"Required performance, NVPS\",\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"N/A\",\"value\":\"null\"}],\"valueName\":\"current\"}],\"title\":\"General\"},{\"collapse\":false,\"editable\":true,\"height\":\"300px\",\"panels\":[{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":1,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":1,\"isNew\":true,\"legend\":{\"alignAsTable\":true,\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"rightSide\":true,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[{\"alias\":\"/user/\",\"color\":\"#1F78C1\"},{\"alias\":\"/system/\",\"color\":\"#BF1B00\"},{\"alias\":\"/iowait/\",\"color\":\"#E5AC0E\"}],\"span\":7,\"stack\":true,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"CPU\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/CPU (?!idle)/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"CPU\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"individual\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"percent\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]},{\"columns\":[{\"text\":\"Current\",\"value\":\"current\"},{\"text\":\"Avg\",\"value\":\"avg\"}],\"editable\":true,\"error\":false,\"fontSize\":\"100%\",\"id\":2,\"isNew\":true,\"links\":[],\"pageSize\":null,\"scroll\":true,\"showHeader\":true,\"sort\":{\"col\":2,\"desc\":true},\"span\":5,\"styles\":[{\"dateFormat\":\"YYYY-MM-DD HH:mm:ss\",\"pattern\":\"Time\",\"type\":\"date\"},{\"colorMode\":\"cell\",\"colors\":[\"rgb(41, 170, 106)\",\"rgba(239, 148, 21, 0.89)\",\"rgba(239, 10, 10, 0.9)\"],\"decimals\":1,\"pattern\":\"/.*/\",\"thresholds\":[\"50\",\"80\"],\"type\":\"number\",\"unit\":\"percent\"}],\"targets\":[{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/Zabbix busy/\"},\"mode\":0,\"refId\":\"A\"}],\"title\":\"Zabbix processes\",\"transform\":\"timeseries_aggregations\",\"type\":\"table\"}],\"title\":\"Row\"},{\"collapse\":false,\"editable\":true,\"height\":\"380\",\"panels\":[{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":0,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":6,\"isNew\":true,\"legend\":{\"alignAsTable\":true,\"avg\":false,\"current\":false,\"hideEmpty\":true,\"hideZero\":true,\"max\":false,\"min\":false,\"rightSide\":true,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[],\"span\":7.069277691711851,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/Zabbix busy/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"Zabbix busy processes\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"percent\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]},{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":0,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":7,\"isNew\":true,\"legend\":{\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[],\"span\":4.930722308288148,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"Zabbix queue\"},\"mode\":0,\"refId\":\"A\"},{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/Values processed/\"},\"mode\":0,\"refId\":\"B\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"Zabbix Queue\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"short\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]}],\"title\":\"New row\"}],\"schemaVersion\":12,\"sharedCrosshair\":false,\"style\":\"dark\",\"tags\":[\"zabbix\",\"example\"],\"templating\":{\"list\":[]},\"time\":{\"from\":\"now-6h\",\"to\":\"now\"},\"timepicker\":{\"refresh_intervals\":[\"5s\",\"10s\",\"30s\",\"1m\",\"5m\",\"15m\",\"30m\",\"1h\",\"2h\",\"1d\"],\"time_options\":[\"5m\",\"15m\",\"1h\",\"6h\",\"12h\",\"24h\",\"2d\",\"7d\",\"30d\"]},\"timezone\":\"browser\",\"title\":\"Zabbix Server Dashboard\",\"version\":0}', '1', CURDATE(), CURDATE(), '1', '1', '0', 'alexanderzobnin-zabbix-app');" >> enable_zabbix_plugin.sql


sudo echo "INSERT INTO \`dashboard\` (\`id\`,\`version\`,\`slug\`,\`title\`,\`data\`,\`org_id\`,\`created\`,\`updated\`,\`updated_by\`,\`created_by\`,\`gnet_id\`,\`plugin_id\`) values ('2', '0', 'template-linux-server', 'Template Linux Server', '{\"annotations\":{\"list\":[]},\"editable\":true,\"hideControls\":false,\"id\":null,\"links\":[],\"originalTitle\":\"Template Linux Server\",\"rows\":[{\"collapse\":false,\"editable\":true,\"height\":\"250px\",\"panels\":[{\"aliasColors\":{\"CPU iowait time\":\"#B7DBAB\",\"CPU system time\":\"#BF1B00\",\"CPU user time\":\"#EAB839\"},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":3,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":1,\"legend\":{\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":1,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":2,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[],\"span\":6,\"stack\":true,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"CPU\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"/CPU/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"CPU\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"individual\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"percent\",\"logBase\":1,\"max\":100,\"min\":0,\"show\":true},{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]},{\"aliasColors\":{\"Processor load (1 min average per core)\":\"#1F78C1\"},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":1,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":2,\"legend\":{\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[],\"span\":6,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"CPU\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Processor load (15 min average per core)\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"System load\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":0,\"show\":true},{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]}],\"showTitle\":true,\"title\":\"CPU\"},{\"collapse\":false,\"editable\":true,\"height\":\"250px\",\"panels\":[{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":3,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":3,\"legend\":{\"alignAsTable\":false,\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"rightSide\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"minSpan\":4,\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"repeat\":\"netif\",\"scopedVars\":{\"netif\":{\"selected\":false,\"text\":\"eth0\",\"value\":\"eth0\"}},\"seriesOverrides\":[{\"alias\":\"/Incoming/\",\"transform\":\"negative-Y\"}],\"span\":6,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"/\$netif/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"Network traffic on \$netif\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"bps\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]},{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":3,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":4,\"legend\":{\"alignAsTable\":false,\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"rightSide\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"minSpan\":4,\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"repeat\":null,\"repeatIteration\":1460635040618,\"repeatPanelId\":3,\"scopedVars\":{\"netif\":{\"selected\":false,\"text\":\"eth1\",\"value\":\"eth1\"}},\"seriesOverrides\":[{\"alias\":\"/Incoming/\",\"transform\":\"negative-Y\"}],\"span\":6,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"/\$netif/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"Network traffic on \$netif\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"bps\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]}],\"showTitle\":true,\"title\":\"Network\"}],\"schemaVersion\":12,\"sharedCrosshair\":false,\"style\":\"dark\",\"tags\":[\"zabbix\",\"example\"],\"templating\":{\"list\":[{\"allFormat\":\"regex values\",\"current\":{\"text\":\"Frontend\",\"value\":\"Frontend\"},\"datasource\":null,\"hide\":0,\"includeAll\":false,\"label\":\"Group\",\"multi\":false,\"multiFormat\":\"glob\",\"name\":\"group\",\"options\":[{\"selected\":false,\"text\":\"Backend\",\"value\":\"Backend\"},{\"selected\":false,\"text\":\"Database servers\",\"value\":\"Database servers\"},{\"selected\":true,\"text\":\"Frontend\",\"value\":\"Frontend\"},{\"selected\":false,\"text\":\"Linux servers\",\"value\":\"Linux servers\"},{\"selected\":false,\"text\":\"Network\",\"value\":\"Network\"},{\"selected\":false,\"text\":\"Workstations\",\"value\":\"Workstations\"},{\"selected\":false,\"text\":\"Zabbix servers\",\"value\":\"Zabbix servers\"}],\"query\":\"*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"\",\"type\":\"query\"},{\"allFormat\":\"glob\",\"current\":{\"text\":\"frontend01\",\"value\":\"frontend01\"},\"datasource\":null,\"hide\":0,\"includeAll\":false,\"label\":\"Host\",\"multi\":false,\"multiFormat\":\"glob\",\"name\":\"host\",\"options\":[{\"selected\":true,\"text\":\"frontend01\",\"value\":\"frontend01\"},{\"selected\":false,\"text\":\"frontend02\",\"value\":\"frontend02\"}],\"query\":\"\$group.*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"\",\"type\":\"query\"},{\"allFormat\":\"regex values\",\"current\":{\"text\":\"All\",\"value\":\"\$__all\"},\"datasource\":null,\"hide\":0,\"hideLabel\":false,\"includeAll\":true,\"label\":\"Network interface\",\"multi\":true,\"multiFormat\":\"regex values\",\"name\":\"netif\",\"options\":[{\"selected\":true,\"text\":\"All\",\"value\":\"\$__all\"},{\"selected\":false,\"text\":\"eth0\",\"value\":\"eth0\"},{\"selected\":false,\"text\":\"eth1\",\"value\":\"eth1\"}],\"query\":\"*.\$host.Network interfaces.*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"/(?:Incoming|Outgoing) network traffic on (.*)/\",\"type\":\"query\"}]},\"time\":{\"from\":\"now-3h\",\"to\":\"now\"},\"timepicker\":{\"now\":true,\"refresh_intervals\":[\"30s\",\"1m\",\"5m\",\"15m\",\"30m\",\"1h\",\"3h\",\"2h\",\"1d\"],\"time_options\":[\"5m\",\"15m\",\"1h\",\"6h\",\"12h\",\"24h\",\"2d\",\"7d\",\"30d\"]},\"timezone\":\"browser\",\"title\":\"Template Linux Server\",\"version\":0}', '1', CURDATE(), CURDATE(), '1', '1', '0', 'alexanderzobnin-zabbix-app');" >> enable_zabbix_plugin.sql


sudo echo "INSERT INTO \`dashboard\` (\`id\`,\`version\`,\`slug\`,\`title\`,\`data\`,\`org_id\`,\`created\`,\`updated\`,\`updated_by\`,\`created_by\`,\`gnet_id\`,\`plugin_id\`) values ('3', '4', 'aws-qs-testing', 'AWS-QS-TESTING', '{\"annotations\":{\"list\":[]},\"editable\":true,\"gnetId\":null,\"graphTooltip\":0,\"hideControls\":false,\"id\":3,\"links\":[],\"refresh\":\"30s\",\"rows\":[{\"collapse\":false,\"height\":115,\"panels\":[{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":2,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":2,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Port \\\\\"2181\\\\\" should be listening with tcp\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"PORT 2181 should be open\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":3,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":2,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Service \\\\\"kafka\\\\\" should be running\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"Kafka Service should be running\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":4,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":2,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Port \\\\\"8080\\\\\" should be listening with tcp\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"Port 8080 should be open\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":5,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":3,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Host \\\\\"google.com\\\\\" should be reachable\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"Host Google should be reachable\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":6,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":3,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - File \\\\\"/dev/xvda1\\\\\" should be block device\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"/DEV/SDA1 should be a block device\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"}],\"repeat\":null,\"repeatIteration\":null,\"repeatRowId\":null,\"showTitle\":false,\"title\":\"Dashboard Row\",\"titleSize\":\"h6\"},{\"collapse\":false,\"height\":96,\"panels\":[{\"columns\":[],\"compactRowsEnabled\":true,\"datatablePagingType\":\"simple_numbers\",\"datatableTheme\":\"basic_theme\",\"fontSize\":\"100%\",\"hoverEnabled\":true,\"id\":1,\"infoEnabled\":true,\"lengthChangeEnabled\":true,\"links\":[],\"minSpan\":2,\"orderColumnEnabled\":true,\"pagingTypes\":[{\"text\":\"Page number buttons only\",\"value\":\"numbers\"},{\"text\":\"\'Previous\' and \'Next\' buttons only\",\"value\":\"simple\"},{\"text\":\"\'Previous\' and \'Next\' buttons, plus page numbers\",\"value\":\"simple_numbers\"},{\"text\":\"\'First\', \'Previous\', \'Next\' and \'Last\' buttons\",\"value\":\"full\"},{\"text\":\"\'First\', \'Previous\', \'Next\' and \'Last\' buttons, plus page numbers\",\"value\":\"full_numbers\"},{\"text\":\"\'First\' and \'Last\' buttons, plus page numbers\",\"value\":\"first_last_numbers\"}],\"panelHeight\":250,\"rowNumbersEnabled\":true,\"rowsPerPage\":10,\"scroll\":false,\"scrollHeight\":\"default\",\"searchEnabled\":true,\"showCellBorders\":true,\"showHeader\":true,\"showRowBorders\":false,\"sort\":{\"col\":0,\"desc\":true},\"span\":12,\"stripedRowsEnabled\":true,\"styles\":[{\"dateFormat\":\"YYYY-MM-DD HH:mm:ss\",\"pattern\":\"Time\",\"type\":\"date\"},{\"colorMode\":\"cell\",\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"dateFormat\":\"YYYY-MM-DD HH:mm:ss\",\"decimals\":0,\"pattern\":\"Value\",\"sanitize\":false,\"thresholds\":[\"2\",\"1\"],\"type\":\"number\",\"unit\":\"short\"}],\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - File \\\\\"/dev/xvda1\\\\\" should be block device\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"},{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Port \\\\\"2181\\\\\" should be listening with tcp\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"B\"},{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Port \\\\\"8080\\\\\" should be listening with tcp\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"C\"},{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Host \\\\\"google.com\\\\\" should be reachable\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"D\"},{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Service \\\\\"kafka\\\\\" should be running\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"E\"}],\"themeOptions\":{\"dark\":\"./css/datatable-dark.css\",\"light\":\"./css/datatable-light.css\"},\"themes\":[{\"disabled\":false,\"text\":\"Basic\",\"value\":\"basic_theme\"},{\"disabled\":true,\"text\":\"Bootstrap\",\"value\":\"bootstrap_theme\"},{\"disabled\":true,\"text\":\"Foundation\",\"value\":\"foundation_theme\"},{\"disabled\":true,\"text\":\"ThemeRoller\",\"value\":\"themeroller_theme\"}],\"title\":\"Serverspec Tests\",\"transform\":\"timeseries_to_rows\",\"transparent\":false,\"type\":\"briangann-datatable-panel\"}],\"repeat\":null,\"repeatIteration\":null,\"repeatRowId\":null,\"showTitle\":false,\"title\":\"Dashboard Row\",\"titleSize\":\"h6\"}],\"schemaVersion\":14,\"style\":\"dark\",\"tags\":[],\"templating\":{\"list\":[{\"allFormat\":\"regex values\",\"allValue\":null,\"current\":{\"text\":\"AWS-QuickStart\",\"value\":\"AWS-QuickStart\"},\"datasource\":null,\"hide\":0,\"includeAll\":false,\"label\":\"Group\",\"multi\":false,\"multiFormat\":\"glob\",\"name\":\"group\",\"options\":[],\"query\":\"*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"\",\"sort\":0,\"tagValuesQuery\":\"\",\"tags\":[],\"tagsQuery\":\"\",\"type\":\"query\",\"useTags\":false},{\"allFormat\":\"glob\",\"allValue\":null,\"current\":{\"text\":\"ip-10-0-3-113.us-west-2.compute.internal\",\"value\":\"ip-10-0-3-113.us-west-2.compute.internal\"},\"datasource\":null,\"hide\":0,\"includeAll\":false,\"label\":\"Host\",\"multi\":false,\"multiFormat\":\"glob\",\"name\":\"host\",\"options\":[],\"query\":\"\$group.*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"\",\"sort\":0,\"tagValuesQuery\":\"\",\"tags\":[],\"tagsQuery\":\"\",\"type\":\"query\",\"useTags\":false}]},\"time\":{\"from\":\"now-3h\",\"to\":\"now\"},\"timepicker\":{\"now\":true,\"refresh_intervals\":[\"30s\",\"1m\",\"5m\",\"15m\",\"30m\",\"1h\",\"3h\",\"2h\",\"1d\"],\"time_options\":[\"5m\",\"15m\",\"1h\",\"6h\",\"12h\",\"24h\",\"2d\",\"7d\",\"30d\"]},\"timezone\":\"browser\",\"title\":\"AWS-QS-TESTING\",\"version\":4}', '1', '2017-07-09 13:32:21', '2017-07-09 14:04:23', '1', '1', '0', ''
);" >> enable_zabbix_plugin.sql



sudo echo "INSERT INTO \`dashboard_tag\` (\`id\`,\`dashboard_id\`,\`term\`)  values ('1', '3', 'aws-quickstart');" >> enable_zabbix_plugin.sql


sleep 120

echo QS_BEGIN_Enable_Zabbix_Plugin_and_Datasource
mysql --user=${DATABASE_USER} --password="${DATABASE_PASS}" grafana < enable_zabbix_plugin.sql
echo QS_END_Enable_Zabbix_Plugin_and_Datasource




fi

if [[ ${DATABASE_CONN_STRING} != 'NA' ]]; then

echo QS_BEGIN_Create_Grafana_Aurora_Web_Conf_File

#Create the Grafana Aurora database
echo QS_BEGIN_Create_Grafana_Aurora_Database
mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" -e "CREATE DATABASE grafana CHARACTER SET UTF8;"
echo QS_END_Create_Grafana_Aurora_Database


cd /etc/grafana/

sudo grep -A21 "\[database\]" grafana.ini | sed -i  's/;type = sqlite3/type = mysql/' grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i  "s/;host = 127.*/host = ${DATABASE_CONN_STRING}:3306/" grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i  "s/;user = root/user = ${DATABASE_USER}/" grafana.ini
sudo grep -A21 "\[database\]" grafana.ini | sed -i  "s/;password =/password = ${DATABASE_PASS}/" grafana.ini

sudo grep -A21 "\[security\]" grafana.ini | sed -i  "s/;admin_user = admin/admin_user = ${DATABASE_USER}/" grafana.ini
sudo grep -A21 "\[security\]" grafana.ini | sed -i  "s/;admin_password = admin/admin_password = ${DATABASE_PASS}/" grafana.ini


sudo grep -A21 "\[session\]" grafana.ini | sed -i  's/;provider = file/provider = mysql/' grafana.ini
sudo grep -A21 "\[session\]" grafana.ini | sed -i  "s/;provider_config = sessions/provider_config = ${DATABASE_USER}:${DATABASE_PASS}@tcp(${DATABASE_CONN_STRING}:3306)\/grafana/" grafana.ini

cd /tmp

sudo touch create_grafana_session.sql

chown root:grafana create_grafana_session.sql

echo QS_BEGIN_Create_Grafana_Aurora_Sessions_Table
sudo echo "create table session("  >> create_grafana_session.sql
sudo echo "\`key\` char(16) not null,"  >> create_grafana_session.sql
sudo echo "data blob,"  >> create_grafana_session.sql
sudo echo "expiry int(11) unsigned not null,"  >> create_grafana_session.sql
sudo echo "primary key (\`key\`))"  >> create_grafana_session.sql
sudo echo "ENGINE=MyISAM default charset=UTF8;" >> create_grafana_session.sql




#Run create.sql file against Grafanadb we created above to create user session schema.
echo QS_BEGIN_Apply_Grafana_Aurora_Sessions_Schema
mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" grafana < create_grafana_session.sql
echo QS_END_Apply_Grafana_Aurora_Schema

sudo service grafana-server restart

sudo touch enable_zabbix_plugin.sql

chown root:grafana enable_zabbix_plugin.sql

if [[ ${ZABBIX_URL} != 'NA' ]]; then

sudo echo "INSERT INTO \`data_source\` (\`id\`,\`org_id\`,\`version\`,\`type\`,\`name\`,\`access\`,\`url\`,\`password\`,\`user\`,\`database\`,\`basic_auth\`,\`basic_auth_user\`,\`basic_auth_password\`,\`is_default\`,\`json_data\`,\`created\`,\`updated\`,\`with_credentials\`,\`secure_json_data\`) values ('1','1','1','alexanderzobnin-zabbix-datasource','ZabbixDS','proxy','${ZABBIX_URL}','','','','0','${DATABASE_USER}','api_jsonrpc.php','1','{\"addThresholds\":true,\"alerting\":true,\"alertingMinSeverity\":1,\"cacheTTL\":\"1h\",\"password\":\"${DATABASE_PASS}\",\"trends\":true,\"trendsFrom\":\"7d\",\"trendsRange\":\"4d\",\"username\":\"${DATABASE_USER}\"}',CURDATE(),CURDATE(),'0','{}');"  >> enable_zabbix_plugin.sql

fi

sudo echo "INSERT INTO \`plugin_setting\` (\`id\`,\`org_id\`,\`plugin_id\`,\`enabled\`,\`pinned\`,\`json_data\`,\`secure_json_data\`,\`created\`,\`updated\`,\`plugin_version\`) values ('1','1','alexanderzobnin-zabbix-app','1','1','null','{}',CURDATE(),CURDATE(), '3.4.0');"  >> enable_zabbix_plugin.sql


sudo echo "INSERT INTO \`dashboard\` (\`id\`,\`version\`,\`slug\`,\`title\`,\`data\`,\`org_id\`,\`created\`,\`updated\`,\`updated_by\`,\`created_by\`,\`gnet_id\`,\`plugin_id\`) values ('1', '0', 'zabbix-server-dashboard', 'Zabbix Server Dashboard', '{\"annotations\":{\"list\":[]},\"editable\":true,\"hideControls\":false,\"id\":null,\"links\":[],\"originalTitle\":\"Zabbix Server Dashboard\",\"rows\":[{\"collapse\":false,\"editable\":true,\"height\":\"100px\",\"panels\":[{\"cacheTimeout\":null,\"colorBackground\":false,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"editable\":true,\"error\":false,\"format\":\"none\",\"id\":3,\"interval\":null,\"isNew\":true,\"links\":[],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"span\":4,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"targets\":[{\"application\":{\"filter\":\"General\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"Host name\"},\"mode\":2,\"refId\":\"A\"}],\"thresholds\":\"\",\"title\":\"Host name\",\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"N/A\",\"value\":\"null\"}],\"valueName\":\"avg\"},{\"cacheTimeout\":null,\"colorBackground\":false,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"decimals\":0,\"editable\":true,\"error\":false,\"format\":\"s\",\"id\":4,\"interval\":null,\"isNew\":true,\"links\":[],\"maxDataPoints\":\"\",\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"span\":4,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"targets\":[{\"application\":{\"filter\":\"General\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"System uptime\"},\"mode\":0,\"refId\":\"A\"}],\"thresholds\":\"\",\"title\":\"Uptime\",\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"N/A\",\"value\":\"null\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":false,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"editable\":true,\"error\":false,\"format\":\"none\",\"id\":5,\"interval\":null,\"isNew\":true,\"links\":[],\"maxDataPoints\":\"\",\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"span\":4,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"targets\":[{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/Required performance of Zabbix server/\"},\"mode\":0,\"refId\":\"A\"}],\"thresholds\":\"\",\"title\":\"Required performance, NVPS\",\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"N/A\",\"value\":\"null\"}],\"valueName\":\"current\"}],\"title\":\"General\"},{\"collapse\":false,\"editable\":true,\"height\":\"300px\",\"panels\":[{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":1,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":1,\"isNew\":true,\"legend\":{\"alignAsTable\":true,\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"rightSide\":true,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[{\"alias\":\"/user/\",\"color\":\"#1F78C1\"},{\"alias\":\"/system/\",\"color\":\"#BF1B00\"},{\"alias\":\"/iowait/\",\"color\":\"#E5AC0E\"}],\"span\":7,\"stack\":true,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"CPU\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/CPU (?!idle)/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"CPU\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"individual\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"percent\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]},{\"columns\":[{\"text\":\"Current\",\"value\":\"current\"},{\"text\":\"Avg\",\"value\":\"avg\"}],\"editable\":true,\"error\":false,\"fontSize\":\"100%\",\"id\":2,\"isNew\":true,\"links\":[],\"pageSize\":null,\"scroll\":true,\"showHeader\":true,\"sort\":{\"col\":2,\"desc\":true},\"span\":5,\"styles\":[{\"dateFormat\":\"YYYY-MM-DD HH:mm:ss\",\"pattern\":\"Time\",\"type\":\"date\"},{\"colorMode\":\"cell\",\"colors\":[\"rgb(41, 170, 106)\",\"rgba(239, 148, 21, 0.89)\",\"rgba(239, 10, 10, 0.9)\"],\"decimals\":1,\"pattern\":\"/.*/\",\"thresholds\":[\"50\",\"80\"],\"type\":\"number\",\"unit\":\"percent\"}],\"targets\":[{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/Zabbix busy/\"},\"mode\":0,\"refId\":\"A\"}],\"title\":\"Zabbix processes\",\"transform\":\"timeseries_aggregations\",\"type\":\"table\"}],\"title\":\"Row\"},{\"collapse\":false,\"editable\":true,\"height\":\"380\",\"panels\":[{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":0,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":6,\"isNew\":true,\"legend\":{\"alignAsTable\":true,\"avg\":false,\"current\":false,\"hideEmpty\":true,\"hideZero\":true,\"max\":false,\"min\":false,\"rightSide\":true,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[],\"span\":7.069277691711851,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/Zabbix busy/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"Zabbix busy processes\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"percent\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]},{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":0,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":7,\"isNew\":true,\"legend\":{\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[],\"span\":4.930722308288148,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"Zabbix queue\"},\"mode\":0,\"refId\":\"A\"},{\"application\":{\"filter\":\"Zabbix server\"},\"functions\":[],\"group\":{\"filter\":\"Zabbix servers\"},\"host\":{\"filter\":\"Zabbix server\"},\"item\":{\"filter\":\"/Values processed/\"},\"mode\":0,\"refId\":\"B\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"Zabbix Queue\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"short\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"label\":null,\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]}],\"title\":\"New row\"}],\"schemaVersion\":12,\"sharedCrosshair\":false,\"style\":\"dark\",\"tags\":[\"zabbix\",\"example\"],\"templating\":{\"list\":[]},\"time\":{\"from\":\"now-6h\",\"to\":\"now\"},\"timepicker\":{\"refresh_intervals\":[\"5s\",\"10s\",\"30s\",\"1m\",\"5m\",\"15m\",\"30m\",\"1h\",\"2h\",\"1d\"],\"time_options\":[\"5m\",\"15m\",\"1h\",\"6h\",\"12h\",\"24h\",\"2d\",\"7d\",\"30d\"]},\"timezone\":\"browser\",\"title\":\"Zabbix Server Dashboard\",\"version\":0}', '1', CURDATE(), CURDATE(), '1', '1', '0', 'alexanderzobnin-zabbix-app');" >> enable_zabbix_plugin.sql


sudo echo "INSERT INTO \`dashboard\` (\`id\`,\`version\`,\`slug\`,\`title\`,\`data\`,\`org_id\`,\`created\`,\`updated\`,\`updated_by\`,\`created_by\`,\`gnet_id\`,\`plugin_id\`) values ('2', '0', 'template-linux-server', 'Template Linux Server', '{\"annotations\":{\"list\":[]},\"editable\":true,\"hideControls\":false,\"id\":null,\"links\":[],\"originalTitle\":\"Template Linux Server\",\"rows\":[{\"collapse\":false,\"editable\":true,\"height\":\"250px\",\"panels\":[{\"aliasColors\":{\"CPU iowait time\":\"#B7DBAB\",\"CPU system time\":\"#BF1B00\",\"CPU user time\":\"#EAB839\"},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":3,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":1,\"legend\":{\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":1,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":2,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[],\"span\":6,\"stack\":true,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"CPU\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"/CPU/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"CPU\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"individual\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"percent\",\"logBase\":1,\"max\":100,\"min\":0,\"show\":true},{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]},{\"aliasColors\":{\"Processor load (1 min average per core)\":\"#1F78C1\"},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":1,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":2,\"legend\":{\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"seriesOverrides\":[],\"span\":6,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"CPU\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Processor load (15 min average per core)\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"System load\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":0,\"show\":true},{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]}],\"showTitle\":true,\"title\":\"CPU\"},{\"collapse\":false,\"editable\":true,\"height\":\"250px\",\"panels\":[{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":3,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":3,\"legend\":{\"alignAsTable\":false,\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"rightSide\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"minSpan\":4,\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"repeat\":\"netif\",\"scopedVars\":{\"netif\":{\"selected\":false,\"text\":\"eth0\",\"value\":\"eth0\"}},\"seriesOverrides\":[{\"alias\":\"/Incoming/\",\"transform\":\"negative-Y\"}],\"span\":6,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"/\$netif/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"Network traffic on \$netif\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"bps\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]},{\"aliasColors\":{},\"bars\":false,\"datasource\":null,\"editable\":true,\"error\":false,\"fill\":3,\"grid\":{\"threshold1\":null,\"threshold1Color\":\"rgba(216, 200, 27, 0.27)\",\"threshold2\":null,\"threshold2Color\":\"rgba(234, 112, 112, 0.22)\"},\"id\":4,\"legend\":{\"alignAsTable\":false,\"avg\":false,\"current\":false,\"max\":false,\"min\":false,\"rightSide\":false,\"show\":true,\"total\":false,\"values\":false},\"lines\":true,\"linewidth\":2,\"links\":[],\"minSpan\":4,\"nullPointMode\":\"connected\",\"percentage\":false,\"pointradius\":5,\"points\":false,\"renderer\":\"flot\",\"repeat\":null,\"repeatIteration\":1460635040618,\"repeatPanelId\":3,\"scopedVars\":{\"netif\":{\"selected\":false,\"text\":\"eth1\",\"value\":\"eth1\"}},\"seriesOverrides\":[{\"alias\":\"/Incoming/\",\"transform\":\"negative-Y\"}],\"span\":6,\"stack\":false,\"steppedLine\":false,\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"/\$netif/\"},\"mode\":0,\"refId\":\"A\"}],\"timeFrom\":null,\"timeShift\":null,\"title\":\"Network traffic on \$netif\",\"tooltip\":{\"msResolution\":false,\"shared\":true,\"value_type\":\"cumulative\"},\"type\":\"graph\",\"xaxis\":{\"show\":true},\"yaxes\":[{\"format\":\"bps\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true},{\"format\":\"short\",\"logBase\":1,\"max\":null,\"min\":null,\"show\":true}]}],\"showTitle\":true,\"title\":\"Network\"}],\"schemaVersion\":12,\"sharedCrosshair\":false,\"style\":\"dark\",\"tags\":[\"zabbix\",\"example\"],\"templating\":{\"list\":[{\"allFormat\":\"regex values\",\"current\":{\"text\":\"Frontend\",\"value\":\"Frontend\"},\"datasource\":null,\"hide\":0,\"includeAll\":false,\"label\":\"Group\",\"multi\":false,\"multiFormat\":\"glob\",\"name\":\"group\",\"options\":[{\"selected\":false,\"text\":\"Backend\",\"value\":\"Backend\"},{\"selected\":false,\"text\":\"Database servers\",\"value\":\"Database servers\"},{\"selected\":true,\"text\":\"Frontend\",\"value\":\"Frontend\"},{\"selected\":false,\"text\":\"Linux servers\",\"value\":\"Linux servers\"},{\"selected\":false,\"text\":\"Network\",\"value\":\"Network\"},{\"selected\":false,\"text\":\"Workstations\",\"value\":\"Workstations\"},{\"selected\":false,\"text\":\"Zabbix servers\",\"value\":\"Zabbix servers\"}],\"query\":\"*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"\",\"type\":\"query\"},{\"allFormat\":\"glob\",\"current\":{\"text\":\"frontend01\",\"value\":\"frontend01\"},\"datasource\":null,\"hide\":0,\"includeAll\":false,\"label\":\"Host\",\"multi\":false,\"multiFormat\":\"glob\",\"name\":\"host\",\"options\":[{\"selected\":true,\"text\":\"frontend01\",\"value\":\"frontend01\"},{\"selected\":false,\"text\":\"frontend02\",\"value\":\"frontend02\"}],\"query\":\"\$group.*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"\",\"type\":\"query\"},{\"allFormat\":\"regex values\",\"current\":{\"text\":\"All\",\"value\":\"\$__all\"},\"datasource\":null,\"hide\":0,\"hideLabel\":false,\"includeAll\":true,\"label\":\"Network interface\",\"multi\":true,\"multiFormat\":\"regex values\",\"name\":\"netif\",\"options\":[{\"selected\":true,\"text\":\"All\",\"value\":\"\$__all\"},{\"selected\":false,\"text\":\"eth0\",\"value\":\"eth0\"},{\"selected\":false,\"text\":\"eth1\",\"value\":\"eth1\"}],\"query\":\"*.\$host.Network interfaces.*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"/(?:Incoming|Outgoing) network traffic on (.*)/\",\"type\":\"query\"}]},\"time\":{\"from\":\"now-3h\",\"to\":\"now\"},\"timepicker\":{\"now\":true,\"refresh_intervals\":[\"30s\",\"1m\",\"5m\",\"15m\",\"30m\",\"1h\",\"3h\",\"2h\",\"1d\"],\"time_options\":[\"5m\",\"15m\",\"1h\",\"6h\",\"12h\",\"24h\",\"2d\",\"7d\",\"30d\"]},\"timezone\":\"browser\",\"title\":\"Template Linux Server\",\"version\":0}', '1', CURDATE(), CURDATE(), '1', '1', '0', 'alexanderzobnin-zabbix-app');" >> enable_zabbix_plugin.sql



sudo echo "INSERT INTO \`dashboard\` (\`id\`,\`version\`,\`slug\`,\`title\`,\`data\`,\`org_id\`,\`created\`,\`updated\`,\`updated_by\`,\`created_by\`,\`gnet_id\`,\`plugin_id\`) values ('3', '4', 'aws-qs-testing', 'AWS-QS-TESTING', '{\"annotations\":{\"list\":[]},\"editable\":true,\"gnetId\":null,\"graphTooltip\":0,\"hideControls\":false,\"id\":3,\"links\":[],\"refresh\":\"30s\",\"rows\":[{\"collapse\":false,\"height\":115,\"panels\":[{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":2,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":2,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Port \\\\\"2181\\\\\" should be listening with tcp\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"PORT 2181 should be open\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":3,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":2,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Service \\\\\"kafka\\\\\" should be running\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"Kafka Service should be running\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":4,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":2,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Port \\\\\"8080\\\\\" should be listening with tcp\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"Port 8080 should be open\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":5,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":3,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Host \\\\\"google.com\\\\\" should be reachable\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"Host Google should be reachable\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"},{\"cacheTimeout\":null,\"colorBackground\":true,\"colorValue\":false,\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"datasource\":null,\"format\":\"none\",\"gauge\":{\"maxValue\":100,\"minValue\":0,\"show\":false,\"thresholdLabels\":false,\"thresholdMarkers\":true},\"id\":6,\"interval\":null,\"links\":[],\"mappingType\":1,\"mappingTypes\":[{\"name\":\"value to text\",\"value\":1},{\"name\":\"range to text\",\"value\":2}],\"maxDataPoints\":100,\"nullPointMode\":\"connected\",\"nullText\":null,\"postfix\":\"\",\"postfixFontSize\":\"50%\",\"prefix\":\"\",\"prefixFontSize\":\"50%\",\"rangeMaps\":[{\"from\":\"null\",\"text\":\"N/A\",\"to\":\"null\"}],\"span\":3,\"sparkline\":{\"fillColor\":\"rgba(31, 118, 189, 0.18)\",\"full\":false,\"lineColor\":\"rgb(31, 120, 193)\",\"show\":false},\"tableColumn\":\"\",\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"hide\":false,\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - File \\\\\"/dev/xvda1\\\\\" should be block device\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"}],\"thresholds\":\"2,1\",\"title\":\"/DEV/SDA1 should be a block device\",\"transparent\":false,\"type\":\"singlestat\",\"valueFontSize\":\"80%\",\"valueMaps\":[{\"op\":\"=\",\"text\":\"FAILING\",\"value\":\"0\"},{\"op\":\"=\",\"text\":\"PASSING\",\"value\":\"1\"}],\"valueName\":\"current\"}],\"repeat\":null,\"repeatIteration\":null,\"repeatRowId\":null,\"showTitle\":false,\"title\":\"Dashboard Row\",\"titleSize\":\"h6\"},{\"collapse\":false,\"height\":96,\"panels\":[{\"columns\":[],\"compactRowsEnabled\":true,\"datatablePagingType\":\"simple_numbers\",\"datatableTheme\":\"basic_theme\",\"fontSize\":\"100%\",\"hoverEnabled\":true,\"id\":1,\"infoEnabled\":true,\"lengthChangeEnabled\":true,\"links\":[],\"minSpan\":2,\"orderColumnEnabled\":true,\"pagingTypes\":[{\"text\":\"Page number buttons only\",\"value\":\"numbers\"},{\"text\":\"\'Previous\' and \'Next\' buttons only\",\"value\":\"simple\"},{\"text\":\"\'Previous\' and \'Next\' buttons, plus page numbers\",\"value\":\"simple_numbers\"},{\"text\":\"\'First\', \'Previous\', \'Next\' and \'Last\' buttons\",\"value\":\"full\"},{\"text\":\"\'First\', \'Previous\', \'Next\' and \'Last\' buttons, plus page numbers\",\"value\":\"full_numbers\"},{\"text\":\"\'First\' and \'Last\' buttons, plus page numbers\",\"value\":\"first_last_numbers\"}],\"panelHeight\":250,\"rowNumbersEnabled\":true,\"rowsPerPage\":10,\"scroll\":false,\"scrollHeight\":\"default\",\"searchEnabled\":true,\"showCellBorders\":true,\"showHeader\":true,\"showRowBorders\":false,\"sort\":{\"col\":0,\"desc\":true},\"span\":12,\"stripedRowsEnabled\":true,\"styles\":[{\"dateFormat\":\"YYYY-MM-DD HH:mm:ss\",\"pattern\":\"Time\",\"type\":\"date\"},{\"colorMode\":\"cell\",\"colors\":[\"rgba(245, 54, 54, 0.9)\",\"rgba(237, 129, 40, 0.89)\",\"rgba(50, 172, 45, 0.97)\"],\"dateFormat\":\"YYYY-MM-DD HH:mm:ss\",\"decimals\":0,\"pattern\":\"Value\",\"sanitize\":false,\"thresholds\":[\"2\",\"1\"],\"type\":\"number\",\"unit\":\"short\"}],\"targets\":[{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - File \\\\\"/dev/xvda1\\\\\" should be block device\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"A\"},{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Port \\\\\"2181\\\\\" should be listening with tcp\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"B\"},{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Port \\\\\"8080\\\\\" should be listening with tcp\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"C\"},{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Host \\\\\"google.com\\\\\" should be reachable\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"D\"},{\"application\":{\"filter\":\"\"},\"functions\":[],\"group\":{\"filter\":\"\$group\"},\"host\":{\"filter\":\"\$host\"},\"item\":{\"filter\":\"Test - Service \\\\\"kafka\\\\\" should be running\"},\"mode\":0,\"options\":{\"showDisabledItems\":false},\"refId\":\"E\"}],\"themeOptions\":{\"dark\":\"./css/datatable-dark.css\",\"light\":\"./css/datatable-light.css\"},\"themes\":[{\"disabled\":false,\"text\":\"Basic\",\"value\":\"basic_theme\"},{\"disabled\":true,\"text\":\"Bootstrap\",\"value\":\"bootstrap_theme\"},{\"disabled\":true,\"text\":\"Foundation\",\"value\":\"foundation_theme\"},{\"disabled\":true,\"text\":\"ThemeRoller\",\"value\":\"themeroller_theme\"}],\"title\":\"Serverspec Tests\",\"transform\":\"timeseries_to_rows\",\"transparent\":false,\"type\":\"briangann-datatable-panel\"}],\"repeat\":null,\"repeatIteration\":null,\"repeatRowId\":null,\"showTitle\":false,\"title\":\"Dashboard Row\",\"titleSize\":\"h6\"}],\"schemaVersion\":14,\"style\":\"dark\",\"tags\":[],\"templating\":{\"list\":[{\"allFormat\":\"regex values\",\"allValue\":null,\"current\":{\"text\":\"AWS-QuickStart\",\"value\":\"AWS-QuickStart\"},\"datasource\":null,\"hide\":0,\"includeAll\":false,\"label\":\"Group\",\"multi\":false,\"multiFormat\":\"glob\",\"name\":\"group\",\"options\":[],\"query\":\"*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"\",\"sort\":0,\"tagValuesQuery\":\"\",\"tags\":[],\"tagsQuery\":\"\",\"type\":\"query\",\"useTags\":false},{\"allFormat\":\"glob\",\"allValue\":null,\"current\":{\"text\":\"ip-10-0-3-113.us-west-2.compute.internal\",\"value\":\"ip-10-0-3-113.us-west-2.compute.internal\"},\"datasource\":null,\"hide\":0,\"includeAll\":false,\"label\":\"Host\",\"multi\":false,\"multiFormat\":\"glob\",\"name\":\"host\",\"options\":[],\"query\":\"\$group.*\",\"refresh\":1,\"refresh_on_load\":false,\"regex\":\"\",\"sort\":0,\"tagValuesQuery\":\"\",\"tags\":[],\"tagsQuery\":\"\",\"type\":\"query\",\"useTags\":false}]},\"time\":{\"from\":\"now-3h\",\"to\":\"now\"},\"timepicker\":{\"now\":true,\"refresh_intervals\":[\"30s\",\"1m\",\"5m\",\"15m\",\"30m\",\"1h\",\"3h\",\"2h\",\"1d\"],\"time_options\":[\"5m\",\"15m\",\"1h\",\"6h\",\"12h\",\"24h\",\"2d\",\"7d\",\"30d\"]},\"timezone\":\"browser\",\"title\":\"AWS-QS-TESTING\",\"version\":4}', '1', '2017-07-09 13:32:21', '2017-07-09 14:04:23', '1', '1', '0', ''
);" >> enable_zabbix_plugin.sql


sudo echo "INSERT INTO \`dashboard_tag\` (\`id\`,\`dashboard_id\`,\`term\`)  values ('1', '3', 'aws-quickstart');" >> enable_zabbix_plugin.sql




sleep 120

echo QS_BEGIN_Enable_Zabbix_Plugin_and_Datasource
mysql --user=${DATABASE_USER} --host=${DATABASE_CONN_STRING} --port=3306 --password="${DATABASE_PASS}" grafana < enable_zabbix_plugin.sql
echo QS_END_Enable_Zabbix_Plugin_and_Datasource

fi


echo QS_END_Create_Grafana_Web_Conf_File

sudo service httpd restart
sudo /bin/systemctl daemon-reload
sudo service grafana-server restart

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
