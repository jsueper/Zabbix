#!/bin/bash

set -o errexit -o xtrace

bucket=quickstart-reference-as
key=zabbixgrafana/setup/latest


aws s3api create-bucket --bucket ${bucket} --region us-east-1 --acl public-read


aws s3 cp ../BootStrapScripts/bootstrapGrafana.sh "s3://${bucket}/${key}/Scripts/bootstrapGrafana.sh" --acl public-read

aws s3 cp ../IndividualTemplates/GrafanaInstallTemplateOrig.json "s3://${bucket}/${key}/GrafanaInstallTemplate.template" --acl public-read



aws cloudformation create-stack --template-url https://s3.amazonaws.com/"${bucket}/${key}"/GrafanaInstallTemplateOrig.json --stack-name GRAFANA-DEPLOY --parameters file://paramsGrafana.json --disable-rollback --capabilities CAPABILITY_IAM
