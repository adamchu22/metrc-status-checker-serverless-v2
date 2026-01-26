#!/bin/bash
set -e # Exit on error

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
    
    # 5 second timeout, capture HTTP code, use User-Agent
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

# 1. Generate the NEW Snapshot
echo "Generating snapshot..."
timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
snapshot_file="snapshot.tmp.json"

echo "{" > $snapshot_file
echo "  \"timestamp\": \"$timestamp\"," >> $snapshot_file
echo "  \"data\": [" >> $snapshot_file

first=true
for state in "${states[@]}"; do
    if [ "$first" = true ]; then first=false; else echo "," >> $snapshot_file; fi
    
    prod_url="https://api-${state}.metrc.com"
    prod_data=$(check_endpoint "$prod_url" "prod")
    
    # Use tr for uppercase to avoid "bad substitution" in some shells
    state_upper=$(echo "$state" | tr '[:lower:]' '[:upper:]')
    echo "    { \"state\": \"$state_upper\", $prod_data }" >> $snapshot_file
    echo "Checked $state_upper..."
done

echo "  ]" >> $snapshot_file
echo "}" >> $snapshot_file

# 2. Append to History (status.json)
HISTORY_FILE="status.json"

if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
    echo "Creating new history file..."
    jq -s '.' $snapshot_file > $HISTORY_FILE
else
    echo "Appending to history..."
    # Robustly append and keep last 240
    jq --slurpfile new $snapshot_file 'if type == "array" then . else [] end + $new | .[-240:]' $HISTORY_FILE > status.tmp && mv status.tmp $HISTORY_FILE
fi

rm -f $snapshot_file
echo "✅ status.json updated successfully."
