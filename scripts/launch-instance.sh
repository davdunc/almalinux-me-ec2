#!/usr/bin/env bash
#
# launch-instance.sh — launch an EC2 instance from the latest official
# AlmaLinux OS 10 AMI, ready for bootstrap.sh.
#
# Usage:
#   ./scripts/launch-instance.sh -k <key-pair-name> [-r region] [-t type] [-p profile]
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

while getopts "k:r:t:p:s:h" opt; do
  case "$opt" in
    k) KEY_NAME="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    t) INSTANCE_TYPE="$OPTARG" ;;
    p) PROFILE="$OPTARG" ;;
    s) VOLUME_SIZE="$OPTARG" ;;
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

echo "==> Ensuring security group '${SG_NAME}' exists..."
SG_ID=$("${AWS[@]}" ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  SG_ID=$("${AWS[@]}" ec2 create-security-group \
    --group-name "$SG_NAME" \
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

echo "==> Launching ${INSTANCE_TYPE} with ${VOLUME_SIZE} GB root volume..."
INSTANCE_ID=$("${AWS[@]}" ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${VOLUME_SIZE},\"VolumeType\":\"gp3\"}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_TAG}}]" \
  --query 'Instances[0].InstanceId' --output text)
echo "    Instance: ${INSTANCE_ID}"

echo "==> Waiting for the instance to be running..."
"${AWS[@]}" ec2 wait instance-running --instance-ids "$INSTANCE_ID"

read -r PUBLIC_DNS PUBLIC_IP <<<"$("${AWS[@]}" ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[PublicDnsName,PublicIpAddress]' \
  --output text)"

cat <<EOF

════════════════════════════════════════════════════════════
 Instance ready.

   ID:   ${INSTANCE_ID}
   DNS:  ${PUBLIC_DNS}
   IP:   ${PUBLIC_IP}

 Next:
   ssh -i <your-key.pem> ec2-user@${PUBLIC_DNS}
   sudo dnf -y install git
   git clone <this-repo-url> && cd almalinux-me-ec2
   ./bootstrap.sh

 When it finishes, reboot and open https://${PUBLIC_DNS}:8443
 in a browser for the Amazon DCV desktop.
════════════════════════════════════════════════════════════
EOF
