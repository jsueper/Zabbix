#!/bin/bash

set -o errexit -o xtrace

bucket=zabbixquickstart
key=zabbix/setup/latest


#aws s3api create-bucket --bucket ${bucket} --region us-east-1 --acl public-read


#aws s3 cp ../bootstrapZabbix.sh "s3://${bucket}/${key}/Scripts/bootstrapZabbix.sh" --acl public-read

#aws s3 cp ../ZabbixInstallTemplate.json "s3://${bucket}/${key}/ZabbixInstallTemplate.json" --acl public-read



aws cloudformation create-stack --template-url https://s3.amazonaws.com/"${bucket}/${key}"/ZabbixInstallTemplate.json --stack-name ZABBIX-DEPLOY1 --parameters file://params.json --disable-rollback --capabilities CAPABILITY_IAM
