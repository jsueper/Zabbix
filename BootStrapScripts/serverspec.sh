#!/bin/bash -e

cd /home/ec2-user/AWS-QS-TESTING/

aws s3 cp s3://serverspec-test . --recursive

rake spec && python serverspec_output_reformater.py
cat reformatted_test_results.json

jq -r --arg foo $(hostname) '.data[] | $foo + " \"" + "test" + "[" + .["{#TEST}"] + "]" + "\" "  + .["{#TEST_RESULT}"]' reformatted_test_results.json | sed 's|"|\\"|g' | sed 's|\\"test|"test|g' | sed 's|]\\"|]"|g' > /tmp/zsender.txt

zabbix_sender -c /etc/zabbix/zabbix_agentd.conf -vv -i /tmp/zsender.txt >> /tmp/zsender.log