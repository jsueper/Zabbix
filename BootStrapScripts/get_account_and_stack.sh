#!/bin/bash
export HOME="/root"

CURRENTIP=`ifconfig eth0 | grep netmask | awk '{print $2}'`
HOST=$1
HOSTIP=$2

OSTYPE=`python /etc/zabbix/midscripts/zabbix-gnomes/zhtmplfinder.py $HOST | grep -i windows`
  if [[ $OSTYPE ]]; then
   INSTANCEDATA=`zabbix_get -I $CURRENTIP -s $HOSTIP -k system.run['powershell.exe "Invoke-WebRequest -UseBasicParsing -Uri http://169.254.169.254/latest/dynamic/instance-identity/document | Select-Object -Expand Content"']`
  else 
   INSTANCEDATA=`zabbix_get -I $CURRENTIP -s $HOSTIP -k system.run["curl -s http://169.254.169.254/latest/dynamic/instance-identity/document"]`
  fi

 # Gather Data
  INSTANCEID=`echo $INSTANCEDATA | grep -oP '(?<="instanceId" : ")[^"]*(?=")'`
  INSTANCEPROFILE=`echo $INSTANCEDATA | grep -oP '(?<="accountId" : ")[^"]*(?=")'`
  INSTANCEREGION=`echo $INSTANCEDATA | grep -oP '(?<="region" : ")[^"]*(?=")'`
  INSTANCEAZ=`echo $INSTANCEDATA | grep -oP '(?<="availabilityZone" : ")[^"]*(?=")'`
  INSTANCEAMI=`echo $INSTANCEDATA | grep -oP '(?<="imageId" : ")[^"]*(?=")'`
  INSTANCETYPE=`echo $INSTANCEDATA | grep -oP '(?<="instanceType" : ")[^"]*(?=")'`
  #ACCOUNTALIAS=`sh /usr/lib/zabbix/scripts/get_account_alias.sh $INSTANCEPROFILE`
  #INSTANCESTACKID=`sh /usr/lib/zabbix/scripts/get_instance_stack.sh $INSTANCEID $INSTANCEPROFILE`
 # Push Data
   # INSTANCE ID
    python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -M INSTANCEID=$INSTANCEID;
    python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -V $INSTANCEID
   # INSTANCE PROFILE
    python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -M PROFILE=$INSTANCEPROFILE;
   # INSTANCE REGION
    python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -M REGION=$INSTANCEREGION;
   # INSTANCE AZ
    python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -M AVAILIBILITYZONE=$INSTANCEAZ;
   # INSTANCE AMI
    python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -M AMI=$INSTANCEAMI;
   # INSTANCE TYPE
    python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -M INSTANCETYPE=$INSTANCETYPE;
   # INSTANCE ALIAS
   # python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -M ACCOUNTALIAS=$ACCOUNTALIAS;
   # INSTANCE STACK
   # python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -M STACKID=$INSTANCESTACKID;
 # Add To Groups
    #python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -G account-$ACCOUNTALIAS
    #python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py	$HOST -G $INSTANCESTACKID
    python /etc/zabbix/midscripts/zabbix-gnomes/zhostupdater.py $HOST -r "Discovered hosts"
