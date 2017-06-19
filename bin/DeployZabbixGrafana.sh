#!/bin/bash

set -o errexit -o xtrace

bucket=zabbixquickstart
key=zabbixgrafana/setup/latest


aws s3api create-bucket --bucket ${bucket} --region us-east-1 --acl public-read


aws s3 cp ../bootstrapZabbix.sh "s3://${bucket}/${key}/Scripts/bootstrapZabbix.sh" --acl public-read
aws s3 cp ../bootstrapGrafana.sh "s3://${bucket}/${key}/Scripts/bootstrapGrafana.sh" --acl public-read

aws s3 cp ../GrafanaInstallTemplate.json "s3://${bucket}/${key}/GrafanaInstallTemplate.json" --acl public-read
aws s3 cp ../ZabbixInstallTemplate.json "s3://${bucket}/${key}/ZabbixInstallTemplate.json" --acl public-read



aws cloudformation create-stack --template-url https://s3.amazonaws.com/"${bucket}/${key}"/MasterInstallTemplate.json --stack-name ZABBIX-GRAFANA-DEPLOY --parameters file://paramsZabbixGrafana.json --disable-rollback --capabilities CAPABILITY_IAM
