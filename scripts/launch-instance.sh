#!/usr/bin/env bash
#
# launch-instance.sh — launch an EC2 instance from the latest official
# AlmaLinux OS 10 AMI, ready for bootstrap.sh.
#
# Usage:
#   ./scripts/launch-instance.sh -k <key-pair-name> [-r region] [-t type] [-p profile]
#                                [-V vpc-id] [-n subnet-id]
#
# The VPC and subnet are auto-discovered (default VPC first, otherwise
# the first available VPC and a public subnet in it); use -V/-n to pick
# explicitly.
#
# Defaults: region us-west-2, type t3.xlarge (KDE + creative apps want
# RAM), 60 GB gp3 root volume.
set -euo pipefail

REGION="us-west-2"
INSTANCE_TYPE="t3.xlarge"
KEY_NAME=""
PROFILE="${AWS_PROFILE:-default}"
VOLUME_SIZE=60
WORKSHOP_NAME="almalinux-me-workshop"
SG_NAME="$WORKSHOP_NAME"
NAME_TAG="$WORKSHOP_NAME"
# Official AlmaLinux OS Foundation AWS publishing account.
ALMA_OWNER_ID="764336703387"

VPC_ID=""
SUBNET_ID=""

while getopts "k:r:t:p:s:V:n:h" opt; do
  case "$opt" in
    k) KEY_NAME="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    t) INSTANCE_TYPE="$OPTARG" ;;
    p) PROFILE="$OPTARG" ;;
    s) VOLUME_SIZE="$OPTARG" ;;
    V) VPC_ID="$OPTARG" ;;
    n) SUBNET_ID="$OPTARG" ;;
    h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) exit 1 ;;
  esac
done

if [[ -z "$KEY_NAME" ]]; then
  echo "ERROR: an EC2 key pair name is required: -k <key-pair-name>" >&2
  exit 1
fi

AWS=(aws --region "$REGION" --profile "$PROFILE")

echo "==> Finding the latest AlmaLinux OS 10 x86_64 AMI in ${REGION}..."
AMI_ID=$("${AWS[@]}" ec2 describe-images \
  --owners "$ALMA_OWNER_ID" \
  --filters "Name=name,Values=AlmaLinux OS 10*x86_64*" \
            "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
  --output text)

if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
  echo "ERROR: no AlmaLinux OS 10 AMI found in ${REGION}" >&2
  exit 1
fi
echo "    AMI: ${AMI_ID}"

if [[ -z "$VPC_ID" ]]; then
  echo "==> Discovering VPC (default VPC preferred)..."
  VPC_ID=$("${AWS[@]}" ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)
  if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
    VPC_ID=$("${AWS[@]}" ec2 describe-vpcs \
      --filters "Name=state,Values=available" \
      --query 'Vpcs[0].VpcId' --output text)
  fi
fi
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "ERROR: no VPC found in ${REGION}; create one or pass -V <vpc-id>" >&2
  exit 1
fi
echo "    VPC: ${VPC_ID}"

if [[ -z "$SUBNET_ID" ]]; then
  # Prefer a subnet that assigns public IPs automatically.
  SUBNET_ID=$("${AWS[@]}" ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
              "Name=map-public-ip-on-launch,Values=true" \
    --query 'Subnets[0].SubnetId' --output text)
  if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
    SUBNET_ID=$("${AWS[@]}" ec2 describe-subnets \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query 'Subnets[0].SubnetId' --output text)
  fi
fi
if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
  echo "ERROR: no subnet found in ${VPC_ID}; pass -n <subnet-id>" >&2
  exit 1
fi
echo "    Subnet: ${SUBNET_ID}"

echo "==> Ensuring security group '${SG_NAME}' exists..."
SG_ID=$("${AWS[@]}" ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  SG_ID=$("${AWS[@]}" ec2 create-security-group \
    --group-name "$SG_NAME" \
    --vpc-id "$VPC_ID" \
    --description "AlmaLinux M&E workshop: SSH + Amazon DCV" \
    --query 'GroupId' --output text)
  # SSH and DCV (8443). Tighten the CIDRs for anything longer-lived
  # than a workshop instance.
  "${AWS[@]}" ec2 authorize-security-group-ingress --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
  "${AWS[@]}" ec2 authorize-security-group-ingress --group-id "$SG_ID" \
    --protocol tcp --port 8443 --cidr 0.0.0.0/0 >/dev/null
fi
echo "    Security group: ${SG_ID}"

# Amazon DCV is free on EC2, but the server must be able to read the
# regional dcv-license S3 bucket or it falls back to a time-limited
# demo license. A minimal read-only role provides that.
IAM_PROFILE_NAME="${WORKSHOP_NAME}-dcv-license"
IAM_PROFILE_ARGS=(--iam-instance-profile "Name=${IAM_PROFILE_NAME}")

echo "==> Ensuring IAM instance profile '${IAM_PROFILE_NAME}' (DCV licensing)..."
if ! "${AWS[@]}" iam get-instance-profile \
    --instance-profile-name "$IAM_PROFILE_NAME" >/dev/null 2>&1; then
  if "${AWS[@]}" iam create-role --role-name "$IAM_PROFILE_NAME" \
      --description "Read-only access to Amazon DCV license S3 buckets" \
      --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null \
    && "${AWS[@]}" iam put-role-policy --role-name "$IAM_PROFILE_NAME" \
      --policy-name DcvLicenseS3Read \
      --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::dcv-license*/*"}]}' \
    && "${AWS[@]}" iam create-instance-profile \
      --instance-profile-name "$IAM_PROFILE_NAME" >/dev/null \
    && "${AWS[@]}" iam add-role-to-instance-profile \
      --instance-profile-name "$IAM_PROFILE_NAME" --role-name "$IAM_PROFILE_NAME"; then
    echo "    Created (waiting for IAM propagation)..."
    sleep 12
  else
    echo "    WARNING: could not create the IAM profile (missing IAM"
    echo "    permissions?). Launching without it — DCV will run on a"
    echo "    time-limited demo license." >&2
    IAM_PROFILE_ARGS=()
  fi
fi

echo "==> Launching ${INSTANCE_TYPE} with ${VOLUME_SIZE} GB root volume..."
INSTANCE_ID=$("${AWS[@]}" ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  ${IAM_PROFILE_ARGS[@]+"${IAM_PROFILE_ARGS[@]}"} \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${VOLUME_SIZE},\"VolumeType\":\"gp3\"}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_TAG}}]" \
  --query 'Instances[0].InstanceId' --output text)
echo "    Instance: ${INSTANCE_ID}"

echo "==> Waiting for the instance to be running..."
"${AWS[@]}" ec2 wait instance-running --instance-ids "$INSTANCE_ID"

read -r PUBLIC_IP PUBLIC_DNS <<<"$("${AWS[@]}" ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[PublicIpAddress,PublicDnsName]' \
  --output text)"
# Non-default VPCs may not assign a public DNS name.
if [[ -z "${PUBLIC_DNS:-}" || "$PUBLIC_DNS" == "None" ]]; then
  PUBLIC_DNS="$PUBLIC_IP"
fi

cat <<EOF

════════════════════════════════════════════════════════════
 Instance ready.

   ID:   ${INSTANCE_ID}
   DNS:  ${PUBLIC_DNS}
   IP:   ${PUBLIC_IP}

 Next:
   ssh -i <your-key.pem> ec2-user@${PUBLIC_DNS}
   sudo dnf -y install git
   git clone https://github.com/davdunc/almalinux-me-ec2.git && cd almalinux-me-ec2
   ./bootstrap.sh

 When it finishes, reboot and open https://${PUBLIC_DNS}:8443
 in a browser for the Amazon DCV desktop.
════════════════════════════════════════════════════════════
EOF
