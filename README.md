# AWS VPC Architecture

This project presents a visual breakdown of a typical AWS VPC architecture and its core networking building blocks.

## Project Overview

The diagrams in this repository help explain how network components are organized and connected inside AWS:

- VPC layout
- Subnet segmentation
- Route table behavior
- Internet gateway connectivity
- End-to-end architecture view

## Architecture Diagrams

### 1) Full Architecture

![AWS VPC Full Architecture](./project-arch.png)

This diagram provides a complete view of the VPC design and how all networking resources relate to each other.

### 2) VPCs

![VPC Diagram](./vpcs.png)

This diagram highlights VPC boundaries and high-level network isolation.

### 3) Subnets

![Subnets Diagram](./subnets.png)

This diagram shows subnet structure, usually including public/private segmentation across availability zones.

### 4) Route Tables

![Route Tables Diagram](./route-tables.png)

This diagram demonstrates routing behavior between subnets and external destinations.

### 5) Internet Gateways

![Internet Gateways Diagram](./internet-gateways.png)

This diagram explains how internet access is enabled through internet gateways.

## Repository Contents

- `project-arch.png` - Full architecture diagram
- `vpcs.png` - VPC-focused view
- `subnets.png` - Subnet-focused view
- `route-tables.png` - Route table-focused view
- `internet-gateways.png` - Internet gateway-focused view

## VPC Provisioning Script (`vpc.sh`)

`vpc.sh` is a bash script that uses the AWS CLI to create a basic VPC networking setup:

- One VPC (`10.0.0.0/16`)
- Two public subnets in different AZs (`10.0.1.0/24` and `10.0.2.0/24`)
- Two private subnets in different AZs (`10.0.3.0/24` and `10.0.4.0/24`)
- One Internet Gateway (IGW)
- A public route table with a default route (`0.0.0.0/0`) pointing to the IGW
- A private route table (this script does not create NAT for outbound internet)
- Route table associations to the appropriate subnets

The script is mostly idempotent: it checks for existing resources by the `Name` tag and only creates missing ones.

### Script

The full contents of `vpc.sh` are:

```bash
#!/bin/bash

# create vpc 10.0.0.0/16

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

# ----------------------------------------------------------------------------

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

# ----------------------------------------------------------------------------

#  create internet gateway
check_igw=$(aws ec2 describe-internet-gateways  --filters Name=tag:Name,Values=devops90-igw | grep -oP '(?<="InternetGatewayId": ")[^"]*')

if [ "$check_igw" == "" ]; then
    echo "internet gateway will be created"

    igw_id=$(aws ec2 create-internet-gateway --region us-east-1 \
        --tag-specifications ResourceType=internet-gateway,Tags="[{Key=Name,Value=devops90-igw}]" --output json | grep -oP '(?<="InternetGatewayId": ")[^"]*')

    if [ "$igw_id" == "" ]; then
        echo "Error in create internet gateway"
        exit 1
    fi
    echo "internet gateway created."
    
  else
    echo "internet gateway already exist"
    igw_id=$check_igw
    echo $igw_id
fi

echo $igw_id

# Attach the internet gateway to vpc (no output)

igw_attach=$(aws ec2 describe-internet-gateways --internet-gateway-ids $igw_id | grep -oP '(?<="VpcId": ")[^"]*')
if [ "$igw_attach" != "$vpc_id" ]; then
    attach_result=$(aws ec2 attach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id 2>&1)
    if [[ "$attach_result" == *"Error"* ]]; then
        echo "Error in attaching internet gateway to the vpc"
        exit 1
    else 
        echo "internet gateway attached to the vpc"
    fi
else
    echo "Internet gateway already attached to this vpc"
fi

# # ----------------------------------------------------------------------------

# create public rout table
check_rtb=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values=public-devops90-rtb | grep -oP '(?<="RouteTableId": ")[^"]*' | uniq)

if [ "$check_rtb" == "" ]; then
    echo "public route table will be created"
    public_rtb_id=$(aws ec2 create-route-table --vpc-id $vpc_id --tag-specifications ResourceType=route-table,Tags="[{Key=Name,Value=public-devops90-rtb}]"  --output json | grep -oP '(?<="RouteTableId": ")[^"]*'  | uniq)
    if [ "$public_rtb_id" == "" ]; then
        echo "Error in create public route table"
        exit 1
    fi
    echo "public route table created."

    # create public route 
    route_result=$(aws ec2 create-route --route-table-id $public_rtb_id \
        --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id | grep -oP '(?<="Return": ")[^"]*')
    echo $route_result
    if [ "$route_result" != "true" ]; then
        echo "public route creation faild"
        exit 1
    fi
    echo "public route created"

else 
    echo "public route table already exist"
    public_rtb_id=$check_rtb
fi

echo $public_rtb_id


# associate public route table to the public subnets
aws ec2 associate-route-table --route-table-id $public_rtb_id --subnet-id $sub1_id
aws ec2 associate-route-table --route-table-id $public_rtb_id --subnet-id $sub2_id

# ----------------------------------------------------------------------------

# create private route table
check_rtb=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values=private-devops90-rtb | grep -oP '(?<="RouteTableId": ")[^"]*'  | uniq)
if [ "$check_rtb" == "" ]; then
    echo "private route table will be created"
    private_rtb_id=$(aws ec2 create-route-table --vpc-id $vpc_id --tag-specifications ResourceType=route-table,Tags="[{Key=Name,Value=private-devops90-rtb}]"  --output json | grep -oP '(?<="RouteTableId": ")[^"]*'  | uniq)
    
    if [ "$private_rtb_id" == "" ]; then
        echo "Error in create private route table"
        exit 1
    fi
    echo "private route table created."

else 
    echo "private route table already exist"
    private_rtb_id=$check_rtb
fi

echo $private_rtb_id

# associate public route table to the public subnets
aws ec2 associate-route-table --route-table-id $private_rtb_id --subnet-id $sub3_id
aws ec2 associate-route-table --route-table-id $private_rtb_id --subnet-id $sub4_id
# ----------------------------------------------------------------------------
```

## Usage

Open this repository in your editor or GitHub to view the diagrams and use them as reference material for AWS networking discussions, documentation, or learning.
