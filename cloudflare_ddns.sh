#!/bin/bash

## Cloudflare DDNS Script
## Author: https://github.com/antoniosarro
## Github: https://github.com/antoniosarro/cloudflare-ddns
## Version: 1.1.0
## Date: 2025-05-03
## Usage: ./cloudflare_ddns.sh

##########################################
## Variables
##########################################

# Email used to login into Cloudflare account
auth_email="${AUTH_EMAIL:?AUTH_EMAIL not set}"
# Authentication Method - Can be set "global" for Global API Key or "token" for Scoped API token
auth_method="${AUTH_METHOD:?AUTH_METHOD not set}"
# Global API Key or Scoped API Token
auth_key="${AUTH_KEY:?AUTH_KEY not set}"
# Cloudflare Zone ID
zone_id="${ZONE_ID:?ZONE_ID not set}"
# Cloudflare Records Name to update (can be a single record or multiple records separated by comma)
records_name="${RECORDS_NAME:?RECORDS_NAME not set}"
# DNS TTL - Setting to 1 means 'automatic'. Value must be between 60 and 86400
ttl="${TTL:-1}" # Default to 1 if not set
# Whether the record is receiving the performance and security benefits of Cloudflare. Can be true or false.  Can be a comma-separated list.
proxies="${PROXIES:-true}" # Default to true
# Gotify url for notification
gotify_url="${GOTIFY_URL:-}" # Optional
# Gotify token for notification
gotify_token="${GOTIFY_TOKEN:-}" # Optional

# Function to send Gotify notification
send_gotify_notification() {
  local title="$1"
  local message="$2"
  if [[ -n "$gotify_url" && -n "$gotify_token" ]]; then
    curl -s -X POST "$gotify_url"/message?token="$gotify_token" \
      -F "title=$title" -F "message=$message" -F "priority=5"
  fi
}

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
if [[ $auth_method == "global" ]]; then
  auth_header="X-Auth-Key:"
elif [[ $auth_method == "token" ]]; then
  auth_header="Authorization: Bearer"
else
  echo "Cloudflare DDNS: Invalid AUTH_METHOD.  Must be 'global' or 'token'."
  exit 1
fi

##########################################
## Check if records exist
##########################################
echo "Cloudflare DDNS: Checking if records exist"

IFS=',' read -r -a records_name_array <<< "$records_name"
IFS=',' read -r -a proxies_array <<< "$proxies"

for i in "${!records_name_array[@]}"; do
  record_name="${records_name_array[$i]}"

  # Determine the proxy setting for this record.
  if [[ ${#proxies_array[@]} -gt "$i" ]]; then
    proxy="${proxies_array[$i]}"
  else
    # If not enough proxies are provided, use the first one.
    proxy="${proxies_array[0]}"
  fi

  # Ensure proxy is lower case
  proxy_lc=$(echo "$proxy" | tr '[:upper:]' '[:lower:]')

  if [[ "$proxy_lc" != "true" && "$proxy_lc" != "false" ]]; then
     echo "Cloudflare DDNS: Invalid proxy value '$proxy' for record '$record_name'.  Must be 'true' or 'false'."
     exit 1
  fi

  records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$record_name" \
    -H "X-Auth-Email: $auth_email" \
    -H "Content-Type: application/json" \
    -H "$auth_header $auth_key")

  echo "$records"

  if [[ $(echo "$records" | jq -r '.result | length') == 0 ]]; then
    echo "Cloudflare DDNS: Record $record_name does not exist. Please create the record and try again."
    send_gotify_notification "Error: Record Not Found" "Record $record_name does not exist."
    exit 1
  fi

  echo "Cloudflare DDNS: Record $record_name found"

  ##########################################
  # Get old record IP
  # ########################################
  old_ip=$(echo "$records" | jq -r '.result[0].content')
  if [[ $old_ip == "$ip" ]]; then
    echo "Cloudflare DDNS: IP has not changed for record $record_name"
    continue # Move to the next record
  fi

  echo "Cloudflare DDNS: IP changed from $old_ip to $ip for record $record_name"

  ##########################################
  # Update record IP
  # ########################################
  echo "Cloudflare DDNS: Updating record $record_name"

  record_id=$(echo "$records" | jq -r '.result[0].id')
  update_result=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
    -H "X-Auth-Email: $auth_email" \
    -H "Content-Type: application/json" \
    -H "$auth_header $auth_key" \
    -d "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy_lc}")
  
  case $(echo "$update_result" | jq -r '.success') in
    true)
      message="Record $record_name updated successfully. Old IP: $old_ip. New IP: $ip"
      echo "Cloudflare DDNS: $message"
      send_gotify_notification "Record Updated" "$message"
      ;;
    false)
      message="Failed to update record $record_name. Old IP: $old_ip. New IP: $ip.  Details: $(echo "$update_result" | jq -r '.errors')"
      echo "Cloudflare DDNS: $message"
      send_gotify_notification "Update Failed" "$message"
      exit 1
      ;;
  esac
done