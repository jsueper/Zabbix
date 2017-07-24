#!/bin/bash

set -o errexit -o xtrace

bucket=quickstart-reference-as
key=zabbixgrafana/setup/latest


aws s3api create-bucket --bucket ${bucket} --region us-east-1 --acl public-read


aws s3 cp ../BootStrapScripts/bootstrapZabbix.sh "s3://${bucket}/${key}/Scripts/bootstrapZabbix.sh" --acl public-read
aws s3 cp ../BootStrapScripts/bootstrapGrafana.sh "s3://${bucket}/${key}/Scripts/bootstrapGrafana.sh" --acl public-read

aws s3 cp ../SinglemasterTemplate/ZabbixGrafanaInstallTemplate.json "s3://${bucket}/${key}/ZabbixGrafanaInstallTemplate.json" --acl public-read



#aws cloudformation create-stack --template-url https://s3.amazonaws.com/"${bucket}/${key}"/ZabbixGrafanaInstallTemplate.json --stack-name ZABBIX-GRAFANA-DEPLOY --parameters file://paramsZabbixGrafana.json --disable-rollback --capabilities CAPABILITY_IAM
