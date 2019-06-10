#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

###############################################################################
### PRE-FLIGHT CHECK

if aws cloudformation describe-stacks --stack-name eksp > /dev/null 2>&1
then
    EKSPHEMERAL_URL=$(aws cloudformation describe-stacks --stack-name eksp | jq '.Stacks[].Outputs[] | select(.OutputKey=="EKSphemeralAPIEndpoint").OutputValue' -r)
    printf "Pre-flight check failed: the control plane is already up and available at %s\n... are you trying to install it again?" $EKSPHEMERAL_URL >&2
    exit 1
fi

printf "Installing the EKSphemeral control plane, this might take a few minutes ...\n"

###############################################################################
### S3 BUCKET OPERATIONS

if [[ -z $(aws s3api head-bucket --bucket $EKSPHEMERAL_SVC_BUCKET) ]]; then
    echo "Using $EKSPHEMERAL_SVC_BUCKET as the control plane service code bucket"
else
    aws s3api create-bucket \
      --bucket $EKSPHEMERAL_SVC_BUCKET \
      --create-bucket-configuration LocationConstraint=$(aws configure get region) \
      --region $(aws configure get region)
    echo "Created $EKSPHEMERAL_SVC_BUCKET and using it as the control plane service code bucket"
fi

if [[ -z $(aws s3api head-bucket --bucket $EKSPHEMERAL_CLUSTERMETA_BUCKET) ]]; then
    echo "Using $EKSPHEMERAL_CLUSTERMETA_BUCKET as the bucket to store cluster 
metadata"
else
    aws s3api create-bucket \
      --bucket $EKSPHEMERAL_CLUSTERMETA_BUCKET \
      --create-bucket-configuration LocationConstraint=$(aws configure get region) \
      --region $(aws configure get region)
    echo "Created $EKSPHEMERAL_CLUSTERMETA_BUCKET and using it as the bucket to store cluster metadata"
fi

###############################################################################
### INSTALL CONTROL PLANE

cd svc
make install
cd ..

printf "\nControl plane should be up now, let us verify that:\n"

EKSPHEMERAL_URL=$(aws cloudformation describe-stacks --stack-name eksp | jq '.Stacks[].Outputs[] | select(.OutputKey=="EKSphemeralAPIEndpoint").OutputValue' -r)

CONTROLPLANE_STATUS=$(curl -sL -w "%{http_code}" -o /dev/null "$EKSPHEMERAL_URL/status/*")

if [ $CONTROLPLANE_STATUS == "200" ]
then
    printf "\nAll good, ready to launch ephemeral clusters now using the 'eksp-create.sh' script or 'eksp-list.sh' to view them\n"
else 
    printf "\nThere was an issue setting up the EKSphemeral control plane, check the CloudFormation logs :(\n"
    exit 1
fi
