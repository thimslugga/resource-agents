#!/bin/sh

#
#   AWS Helper Scripts
#

: ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
. ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs

# Defaults
OCF_RESKEY_curl_retries_default="5"
OCF_RESKEY_curl_sleep_default="3"

: ${OCF_RESKEY_curl_retries=${OCF_RESKEY_curl_retries_default}}
: ${OCF_RESKEY_curl_sleep=${OCF_RESKEY_curl_sleep_default}}

# Functions to enable reusable IMDS token retrieval for efficient repeated access.

TOKEN_FILE="${HA_RSCTMP}/.aws_imds_token" # File to store the token and timestamp
TOKEN_LIFETIME=600                        # IMDS session token lifetime in seconds 10 minutes)
TOKEN_EXPIRY_THRESHOLD=120                # Renew token if there is less than 120 seconds remaining
EC2_IMDS_V4="169.254.169.254"             # EC2 IMDS IPv4 address
EC2_IMDS_V6="[fd00:ec2::254]"             # EC2 IMDS IPv6 address, only supported on Nitro-based instances.

# Function to fetch a new token
fetch_new_token() {
  TOKEN=$(curl_retry "$OCF_RESKEY_curl_retries" "$OCF_RESKEY_curl_sleep" "--show-error -sX PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: $TOKEN_LIFETIME'" "http://$EC2_IMDS_V4/latest/api/token")
  if [ $? -ne 0 ] || [ -z "$TOKEN" ]; then
    ocf_log err "Failed to get session token from IMDS."
    return 1
  fi
  old_umask="$(umask)" # backup current umask
  umask 077            # Only owner should be able to read/write token file.
  echo "$TOKEN $(date +%s)" >"$TOKEN_FILE"
  umask "$old_umask" # revert to old umask after writing token
  echo "$TOKEN"
}

# Function to retrieve or renew the token
get_token() {
  if [ -r "$TOKEN_FILE" ]; then
    read -r STORED_TOKEN STORED_TIMESTAMP <"$TOKEN_FILE"
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - STORED_TIMESTAMP))

    if [ "$ELAPSED_TIME" -lt "$((TOKEN_LIFETIME - TOKEN_EXPIRY_THRESHOLD))" ]; then
      # Token is still valid
      echo "$STORED_TOKEN"
      return
    fi
  fi

  # Fetch a new token if not valid
  fetch_new_token
}
