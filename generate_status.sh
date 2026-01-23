#!/bin/bash

# Define the states to monitor
states=(
    "ak" "al" "ca" "co" "dc" "gu" 
    "il" "ky" "la" "ma" "md" "me" "mi" 
    "mn" "mo" "ms" "mt" "nv" "ny" "oh" 
    "ok" "or" "ri" "sd" "va" "wv"
)

# Function to check a URL and return a JSON snippet
check_endpoint() {
    local url=$1
    local type=$2 # "prod"
    
    # 5 second timeout, capture HTTP code, use User-Agent to avoid bot blocking
    code=$(curl -s -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -o /dev/null -w '%{http_code}' --connect-timeout 5 "$url")
    
    # Determine status string
    if [[ "$code" == "200" ]]; then
        status="ONLINE"
    elif [[ "$code" == "401" || "$code" == "403" ]]; then
        status="SECURED"
    elif [[ "$code" == "000" ]]; then
        status="UNREACHABLE"
    else
        status="ERROR"
    fi
    
    echo "\"${type}_code\": \"$code\", \"${type}_status\": \"$status\""
}

# Start JSON Output
echo "[" > status.json
timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
first=true

# Loop through states
for state in "${states[@]}"; do
    if [ "$first" = true ]; then first=false; else echo "," >> status.json; fi
    
    # Define URL
    prod_url="https://api-${state}.metrc.com"

    # Check environment
    prod_data=$(check_endpoint "$prod_url" "prod")

    # Write JSON Object
    echo "  { \"state\": \"${state^^}\", $prod_data, \"timestamp\": \"$timestamp\" }" >> status.json
    
    echo "Checked ${state^^}..."
done

echo "]" >> status.json
echo "✅ status.json generated successfully."
