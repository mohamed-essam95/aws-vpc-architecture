#!/bin/bash

check_vpc=$(aws ec2 describe-vpcs --region us-east-1 --filters Name=tag:Name,Values=devops90-vpc | grep -oP '(?<="VpcId": ")[^"]*')

if [ "$check_vpc" == "" ]; then
    vpc_result=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specification ResourceType=vpc,Tags="[{Key=Name,Value=devops90-vpc}]" \
        --region us-east-1 \
        --output json)
    echo $vpc_result

    vpc_id=$(echo $vpc_result | grep -oP '(?<="VpcId": ")[^"]*')
    echo $vpc_id


    if [ "$vpc_id" == "" ]; then
        echo "Error in creating the vpc"
        exit 1
    fi

    echo "VPC created."
else
    echo "VPC already exist"

fi

# Describe resource
# if resource not exist
# try to create resource
# if there is error 
# stop the script