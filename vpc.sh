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
    vpc_id=$check_vpc
    echo $vpc_id

fi

# create public subnet 10.0.1.0/24 in first az
# create public subnet 10.0.2.0/24 in second az
# create private subnet 10.0.3.0/24 in first az
# create private subnet 10.0.4.0/24 in second az

create_subnet()
{
    # $1 subnet number, $2 az, $3 public or private
    check_subnet=$(aws ec2 describe-subnets --region us-east-1 --filters Name=tag:Name,Values=sub-$3-$1-devops90 | grep -oP '(?<="SubnetId": ")[^"]*')
    if [ "$check_subnet" == "" ]; then
        echo "subnet $1 will be created"

        subnet_result=$(aws ec2 create-subnet \
            --vpc-id $vpc_id --availability-zone us-east-1$2 \
            --cidr-block 10.0.$1.0/24 \
            --tag-specifications ResourceType=subnet,Tags="[{Key=Name,Value=sub-$3-$1-devops90}]" --output json)
            
        echo $subnet_result

        subnet_id=$(echo $subnet_result | grep -oP '(?<="SubnetId": ")[^"]*')
        echo $subnet_id

        if [ "$subnet_id" == "" ]; then
            echo "Error in create subnet $1"
            exit 1
        fi
        echo "subnet $1 created."
    else
        echo "subnet $1 already exist"
        subnet_id=$check_subnet
        echo $subnet_id
    fi
}

create_subnet 1 a public
sub1_id=$subnet_id

create_subnet 2 b public
sub2_id=$subnet_id

create_subnet 3 a private
sub3_id=$subnet_id

create_subnet 4 b private
sub4_id=$subnet_id

