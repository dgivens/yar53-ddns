#!/usr/bin/env bash

set -o errexit
set -o errtrace
set -o pipefail

function get_current_ip() {
	curl -s https://checkip.amazonaws.com/
}

function r53:get_zone_id() {
	local name="${1}"

	aws route53 list-hosted-zones \
	  --query 'HostedZones[?(Name==`'${name}'` && Config.PrivateZone==`false`)].Id' \
	  --output text | cut -f3 -d/
}

function r53:get_current_record() {
	local name
	local zone_id
	local rrtype

	name="${1}"
	zone_id="${2}"
	rrtype="${3:-A}"

	aws route53 list-resource-record-sets \
	  --hosted-zone-id "${zone_id}" \
	  --query 'ResourceRecordSets[?(Name==`'${name}'` && Type==`'${rrtype}'`)].ResourceRecords[0].Value' \
	  --output text
}

function r53:create_request_body() {
	local name
	local value
	local rrtype
	local ttl
	local tmpfile
	local host

	name="${1}"
	value="${2}"
	rrtype="${3:-A}"
	ttl="${4:-60}"
	tmpfile="${5:-$TMP}"
	host="$( hostname -f )"


	cat > ${TMP} << EOF
{
  "Comment": "Updated by ddns script on ${host}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "ResourceRecords": [
          {
            "Value": "${value}"
          }
        ],
        "Name": "${name}",
        "Type": "${rrtype}",
        "TTL": ${ttl}
      }
    }
  ]
}
EOF
}

function r53:update_record() {
	local zone_id
	local tmpfile

	zone_id="${1}"
	tmpfile="${2:-$TMP}"

	aws route53 change-resource-record-sets \
		--hosted-zone-id "${zone_id}" \
		--change-batch "file://${tmpfile}"
}

trap 'rm -f ${TMP}' EXIT

TMP=$( mktemp )

if [[ -n "${1}" ]]; then
	rr_name="${1}."
	[[ -n "${2}" ]] && zone_name="${2}." || zone_name="${rr_name#*.}"
else
	rr_name="$( hostname -f )."
	zone_name="$( hostname -d )."
fi

echo "Checking if dns needs to be updated for ${rr_name}"

echo "Getting current IP address"
current_ip="$( get_current_ip )"

if [[ ! $current_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
	echo "Malformed output from get_current_ip()"
	exit 1
fi

echo "Current IP Address is ${current_ip}"

echo "Getting Route53 hosted zone id for ${zone_name}"
zone_id="$( r53:get_zone_id "${zone_name}" )"

if [[ -z "${zone_id}" ]]; then
	echo "No public hosted zone found for ${zone_name}"
	exit 1
fi

echo "Found hosted zone id ${zone_id}"

echo "Getting IP address from Route53 for ${rr_name}"
r53_ip="$( r53:get_current_record "${rr_name}" "${zone_id}" )"
[[ -z "${r53_ip}" ]] && r53_ip="null"

if [[ "${current_ip}" == "${r53_ip}" ]]; then
	echo "Route53 record value for ${rr_name} matches current ip ${current_ip}"
else
	echo "Updating Route53 record for ${rr_name} from ${r53_ip} to ${current_ip}"
	echo "Creating resource record change request"
	r53:create_request_body "${rr_name}" "${current_ip}"
	echo "Updating resource record"
	if [[ -n "${DRYRUN}" ]]; then
		echo "DRYRUN set. Not making changes. Here is the request that would have been sent"
		cat "${TMP}"
	else
		r53:update_record "${zone_id}"
		echo "Success"
	fi
fi
