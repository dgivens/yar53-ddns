# Yet Another Route53 Dynamic DNS Tool

A silly bash script that wraps the aws-cli to update Route53 records based on
current public IP address.

## Requirements

- bash
- aws-cli

The aws-cli must be configured with auth creds in one of the ways it expects
for the user executing the script.

## Usage

When run with no arguments, the record to be updated is the hostname of the
system upon which the script is running and the zone is derived from the
hostname.

You can give the script a hostname as an argument, from which the zone name
will be derived.

Finally, you can specify the zone with a second argument.
