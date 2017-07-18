#!/bin/bash
PROFILE=$1
aws iam list-account-aliases --profile $PROFILE | jq -r .AccountAliases[]