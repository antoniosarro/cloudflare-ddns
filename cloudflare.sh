#!/bin/bash

## Cloudflare DDNS Script
## Author: https://github.com/antoniosarro
## Github: https://github.com/asantoniosarroarro99/cloudflare-ddns
## Version: 1.0.1
## Date: 2024-11-08
## Usage: ./clouflare.sh

##########################################
## Variables
##########################################

# Email used to login into Cloudflare account
auth_email=""
# Authentication Method - Can be set "global" for Global API Key or "token" for Scoped API token
auth_mehtod=""
# Global API Key or Scoped API Token
auth_key=""
# Cloudflare Zone ID
zone_id=""
# Cloudflare Records Name to update (can be a single record or multiple records separated by comma)
records_name=""
# DNS TTL - Setting to 1 means 'automatic'. Value must be between 60 and 86400
ttl=""
# Whether the record is receiving the performance and security benefits of Cloudflare. Can be true or false
proxy=""
# Gotify url for notification
gotify_url=""
# Gotify token for notification
gotify_token=""

##########################################
# Check if the dependencies are installed
##########################################
dependencies=(jq curl)
for dependency in "${dependencies[@]}"; do
  if ! command -v "$dependency" &> /dev/null; then
    echo "Cloudflare DDNS: $dependency is not installed. Please install $dependency and try again."
    exit 1
  fi
done

##########################################
## Check if the IP is public or not
##########################################
ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret=$?
if [[ ! $ret == 0 ]]; then
  # If clouflare is not available use other site
  ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
else
  ip=$(echo "$ip" | awk -F= '{print $2}')
fi

##########################################
## Set Auth Header
##########################################
if [[ $auth_mehtod == "global" ]]; then
  auth_header="X-Auth-Key:"
elif [[ $auth_mehtod == "token" ]]; then
  auth_header="Authorization: Bearer"
fi

##########################################
## Check if records exist
##########################################
echo "Cloudflare DDNS: Checking if records exist"

IFS=',' read -r -a records_name <<< "$records_name"
for record_name in "${records_name[@]}"; do
  records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$record_name" \
    -H "X-Auth-Email: $auth_email" \
    -H "Content-Type: application/json" \
    -H "$auth_header $auth_key")

  if [[ $(echo "$records" | jq -r '.result | length') == 0 ]]; then
    echo "Cloudflare DDNS: Record $record_name does not exist. Please create the record and try again."
    exit 1
  fi

  echo "Cloudflare DDNS: Record $record_name found"

  ##########################################
  # Get old record IP
  # ########################################
  old_ip=$(echo "$records" | jq -r '.result[0].content')
  if [[ $old_ip == "$ip" ]]; then
    echo "Cloudflare DDNS: IP has not changed"
    exit 0
  fi

  echo "Cloudflare DDNS: IP changed from $old_ip to $ip"

  ##########################################
  # Update record IP
  # ########################################
  echo "Cloudflare DDNS: Updating record $record_name"
  
  record_id=$(echo "$records" | jq -r '.result[0].id')
  update_result=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
    -H "X-Auth-Email: $auth_email" \
    -H "Content-Type: application/json" \
    -H "$auth_header $auth_key" \
    --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")
  
  case $(echo "$update_result" | jq -r '.success') in
    true)
      echo "Cloudflare DDNS: Record $record_name updated successfully. Old IP: $old_ip. New IP: $ip"
      if [[ $gotify_url != "" ]]; then
        curl -s -X POST "$gotify_url"/message?token="$gotify_token" -F "title=Record $record_name updated successfully" -F "message=Old IP: $old_ip. New IP: $ip" -F "priority=5"
      fi
      ;;
    false)
      echo "Cloudflare DDNS: Failed to update record $record_name. Old IP: $old_ip. New IP: $ip"
      if [[ $gotify_url != "" ]]; then
        curl -s -X POST "$gotify_url"/message?token="$gotify_token" -F "title=Failed to update record $record_name" -F "message=Old IP: $old_ip. New IP: $ip" -F "priority=5"
      fi
      exit 1
      ;;
  esac
done


