#!/bin/bash
INSTANCE=$1
PROFILE=$2
STACK=$(aws ec2 describe-tags --filters "Name=resource-id,Values=${INSTANCE}" --profile $PROFILE | jq -r '.Tags[] | select(.Key | index("StackId")) | .Value' | tr [a-z] [A-Z])
printf "${STACK}"
