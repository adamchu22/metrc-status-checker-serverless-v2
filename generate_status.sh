#!/bin/bash
set -e # Exit on error

# --- CONFIGURATION ---
# REPLACE THIS URL with your published Google Sheet CSV link
# Example: "https://docs.google.com/spreadsheets/d/e/2PACX-1vQ.../pub?output=csv"
REPORTS_CSV_URL="https://docs.google.com/spreadsheets/d/e/2PACX-1vRAXDZS9_Y7v6gfKvjq7FLRWKTtbv0wxQoDZ364sVwwTem31vJKD6qFosyFQx9CQVuMsoOrbEq4FZdS/pub?output=csv" 

# Define the states to monitor
states=(
    "ak" "al" "ca" "co" "dc" "gu" 
    "il" "ky" "la" "ma" "md" "me" "mi" 
    "mn" "mo" "ms" "mt" "nv" "ny" "oh" 
    "ok" "or" "ri" "sd" "va" "wv"
)

# Function to check a URL
check_endpoint() {
    local url=$1
    local type=$2 
    code=$(curl -s -H "User-Agent: StatusBot" -o /dev/null -w '%{http_code}' --connect-timeout 5 "$url")
    
    if [[ "$code" == "200" ]]; then status="ONLINE";
    elif [[ "$code" == "401" || "$code" == "403" ]]; then status="SECURED";
    elif [[ "$code" == "000" ]]; then status="UNREACHABLE";
    else status="ERROR"; fi
    
    echo ""${type}_code": ""$code"", ""${type}_status": ""$status"""
}

# --- 1. Fetch User Reports (Google Sheets) ---
echo "Fetching user reports..."
reports_json="{ \"count\": 0, \"states\": [] }"

if [ -n "$REPORTS_CSV_URL" ]; then
    curl -s -o reports.csv "$REPORTS_CSV_URL" || true
    
    if [ -f reports.csv ]; then
        # Parse CSV with Node.js to count last 3 hours
        reports_json=$(node -e '
            const fs = require("fs");
            try {
                const content = fs.readFileSync("reports.csv", "utf8");
                const lines = content.split("\n").slice(1); // Skip header
                const now = new Date();
                const threeHoursAgo = new Date(now - 3 * 60 * 60 * 1000);
                
                let count = 0;
                let states = new Set();

                lines.forEach(line => {
                    const cols = line.split(","); // Basic CSV split
                    if (cols.length < 2) return;
                    
                    const tsStr = cols[0].replace(/"/g, ""); // Timestamp
                    const reportDate = new Date(tsStr);
                    
                    if (!isNaN(reportDate) && reportDate > threeHoursAgo) {
                        count++;
                        // Add states (cols[1] might be "CA, NY")
                        const stateStr = cols[1] ? cols[1].replace(/"/g, "") : "";
                        stateStr.split(",").forEach(s => states.add(s.trim()));
                    }
                });
                
                console.log(JSON.stringify({ count, states: Array.from(states) }));
            } catch (e) {
                console.log(JSON.stringify({ count: 0, states: [], error: e.message }));
            }
        ')
        rm reports.csv
    fi
fi

# --- 2. Generate Snapshot ---
echo "Generating snapshot..."
timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
snapshot_file="snapshot.tmp.json"

echo "{"
echo "  \"timestamp\": \"$timestamp\"," >> $snapshot_file
echo "  \"user_reports\": $reports_json," >> $snapshot_file
echo "  \"data\": [" >> $snapshot_file

first=true
for state in "${states[@]}"; do
    if [ "$first" = true ]; then first=false; else echo "," >> $snapshot_file; fi
    prod_url="https://api-${state}.metrc.com"
    prod_data=$(check_endpoint "$prod_url" "prod")
    state_upper=$(echo "$state" | tr '[:lower:]' '[:upper:]')
    echo "    { \"state\": \"$state_upper\", $prod_data }" >> $snapshot_file
    echo "Checked $state_upper..."
done

echo "  ]" >> $snapshot_file
echo "}" >> $snapshot_file

# --- 3. Append to History ---
HISTORY_FILE="status.json"

if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
    echo "Creating new history file..."
    jq -s '.' $snapshot_file > $HISTORY_FILE
else
    echo "Appending to history..."
    # Robustly append and keep last 672 (7 days)
    jq --slurpfile new $snapshot_file 'if type == "array" then . else [] end + $new | .[-672:]' $HISTORY_FILE > status.tmp && mv status.tmp $HISTORY_FILE
fi

rm -f $snapshot_file
echo "✅ status.json updated successfully."