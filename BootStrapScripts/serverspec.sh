#!/bin/bash -e

cd /home/ec2-user/AWS-QS-TESTING

#cat /dev/null > /tmp/rake.log

rake spec >> /tmp/rake.log 2>&1

python serverspec_output_reformater.py

jq . reformatted_test_results.json

cat /dev/null > /tmp/zdata.txt

jq -r --arg foo $(hostname) '.data[] | $foo + " \"" + "test" + "[" + .["{#TEST}"] + "]" + "\" "  + .["{#TEST_RESULT}"]' reformatted_test_results.json | sed 's|"|\\"|g' | sed 's|\\"test|"test|g' | sed 's|]\\"|]"|g'  | sed 's|passed|1|g'  | sed 's|failed|0|g' > /tmp/zdata.txt

#cat /dev/null > /tmp/zsender.log

zabbix_sender -c /etc/zabbix/zabbix_agentd.conf -vv -i /tmp/zdata.txt >> /tmp/zsender.log 2>&1