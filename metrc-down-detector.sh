#!/bin/bash

# --- Configuration ---
# Set to "true" to include Sandbox environments in the check
CHECK_SANDBOX=false

# List of State Codes for Metrc
# (AK AL CA CO CT DC FL GA GU HI IA IL KY LA MA MD ME MI MN MO MS MT NC ND NJ NM NV NY OH OK OR PA RI SD TN TX UT VA VT WA WV USVI)
# Note: Not all states use Metrc. This list represents known Metrc jurisdictions.
declare -a states=(
    "ak" "al" "ca" "co" "dc" "gu" 
    "il" "ky" "la" "ma" "md" "me" "mi" 
    "mn" "mo" "ms" "mt" "nv" "ny" "oh" 
    "ok" "or" "ri" "sd" "va" "wv"
)

# Base domains
metrc_urls=()

# Build the URL list
for state in "${states[@]}"; do
    metrc_urls+=("https://api-${state}.metrc.com")
    if [ "$CHECK_SANDBOX" = true ]; then
        metrc_urls+=("https://sandbox-api-${state}.metrc.com")
    fi
done

echo "Starting Metrc Status Check..."
echo "------------------------------"
printf "%-40s %-10s %-20s\n" "Endpoint" "Code" "Status"
echo "------------------------------"

for url in "${metrc_urls[@]}"
do
  # Capture HTTP status code. 
  # -s: Silent (no progress bar)
  # -o /dev/null: discard body
  # -w '%{http_code}': print only status code
  # --connect-timeout 3: fail fast if hung
  CODE=$(curl -s -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -o /dev/null -w '%{http_code}' --connect-timeout 3 "$url")

  case $CODE in
    200)
      STATUS="✔️  ONLINE"
      COLOR="\033[0;32m" # Green
      ;;
    401|403)
      # Server is reachable, but you need an API key. This counts as "UP".
      STATUS="🔒 SECURED (UP)" 
      COLOR="\033[0;33m" # Yellow
      ;;
    404)
      STATUS="❓ NOT FOUND"
      COLOR="\033[0;34m" # Blue
      ;;
    500|502|503|504)
      STATUS="❌ SERVER ERROR"
      COLOR="\033[0;31m" # Red
      ;;
    000)
      STATUS="💀 UNREACHABLE"
      COLOR="\033[0;31m" # Red
      ;;
    *)
      STATUS="⚠️  $CODE"
      COLOR="\033[0;37m" # White
      ;;
  esac

  # Reset color after printing
  NC="\033[0m" 
  
  printf "${COLOR}%-40s %-10s %-20s${NC}\n" "$url" "$CODE" "$STATUS"
done