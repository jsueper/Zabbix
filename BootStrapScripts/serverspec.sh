#!/bin/bash -e

cd /home/ec2-user/AWS-QS-TESTING/

rm -rf spec/Reports

rake spec && python serverspec_output_reformater.py

cd /home/ec2-user/AWS-QS-TESTING/spec/Reports

zabbix_sender -c /etc/zabbix/zabbix_agentd.conf -vv -i reformatted_test_results.json