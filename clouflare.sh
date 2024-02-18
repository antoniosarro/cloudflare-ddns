#!/bin/bash

## Cloudflare DDNS Script
## Author: https://github.com/asarro99
## Github: https://github.com/asarro99/cloudflare-ddns
## Version: 1.0.0
## Date: 2024-02-18
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
# Telegram bot token for notification
telegram_token=""
# Telegram chat id for notification
telegram_chat_id=""

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
      if [[ $telegram_token != "" ]]; then
        curl -s -X POST https://api.telegram.org/bot"$telegram_token"/sendMessage -d chat_id="$telegram_chat_id" -d text="Record $record_name updated successfully. Old IP: $old_ip. New IP: $ip"
      fi
      ;;
    false)
      echo "Cloudflare DDNS: Failed to update record $record_name. Old IP: $old_ip. New IP: $ip"
      if [[ $telegram_token != "" ]]; then
        curl -s -X POST https://api.telegram.org/bot"$telegram_token"/sendMessage -d chat_id="$telegram_chat_id" -d text="Failed to update record $record_name. Old IP: $old_ip. New IP: $ip"
      fi
      exit 1
      ;;
  esac
done


