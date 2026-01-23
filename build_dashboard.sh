#!/bin/bash

# ==========================================
# Metrc Status Dashboard Generator
# ==========================================
# This script generates all necessary files for a Serverless
# Metrc Status Page (HTML + Bash + GitHub Actions).
#
# Usage:
#   chmod +x build_dashboard.sh
#   ./build_dashboard.sh
# ==========================================

echo "📂 Initializing project structure..."

# 1. Create the Data Generation Script (The Logic)
# ------------------------------------------------
cat << 'EOF' > generate_status.sh
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

echo "{"
echo "  \"timestamp\": \"$timestamp\"," >> $snapshot_file
echo "  \"data\": [" >> $snapshot_file

first=true
for state in "${states[@]}"; do
    if [ "$first" = true ]; then first=false; else echo "," >> $snapshot_file; fi
    
    prod_url="https://api-${state}.metrc.com"
    prod_data=$(check_endpoint "$prod_url" "prod")
    
    echo "    { \"state\": \"${state^^}\", $prod_data }" >> $snapshot_file
    echo "Checked ${state^^}..."
done

echo "  ]" >> $snapshot_file
echo "}" >> $snapshot_file

# 2. Append to History (status.json)
# We use jq to append the new snapshot to the list and keep only the last 240 records (30 days of 3-hour checks)
HISTORY_FILE="status.json"

if [ ! -f "$HISTORY_FILE" ]; then
    echo "Creating new history file..."
    jq -n --slurpfile new $snapshot_file '[$new[0]]' > $HISTORY_FILE
else
    echo "Appending to history..."
    # . + $new adds the new snapshot array to the existing one. 
    # .[-240:] takes the last 240 items.
    jq --slurpfile new $snapshot_file '. + $new | .[-240:]' $HISTORY_FILE > status.tmp && mv status.tmp $HISTORY_FILE
fi

rm $snapshot_file
echo "✅ status.json updated successfully."
EOF

chmod +x generate_status.sh
echo "   - Created generate_status.sh (History Enabled)"


# 2. Create the Frontend (The UI)
# ------------------------------------------------
cat << 'EOF' > index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Metrc API Status</title>
    <style>
        :root {
            --bg-color: #1a1b1e;
            --card-bg: #25262b;
            --text-main: #e9ecef;
            --text-muted: #909296;
            --success: #40c057;
            --warning: #fab005;
            --error: #fa5252;
            --border: #2c2e33;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-main);
            margin: 0;
            padding: 40px 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
        }

        header {
            text-align: center;
            margin-bottom: 50px;
        }

        h1 { margin: 0; font-size: 2.5rem; letter-spacing: -1px; }
        .timestamp { color: var(--text-muted); font-size: 0.9rem; margin-top: 10px; }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 20px;
        }

        .card {
            background: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            transition: transform 0.2s;
        }
        
        .card:hover { transform: translateY(-5px); }

        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border);
            padding-bottom: 10px;
            margin-bottom: 15px;
        }

        .state-badge {
            font-size: 1.5rem;
            font-weight: 800;
            color: white;
            background: #339af0;
            padding: 5px 12px;
            border-radius: 8px;
        }

        .env-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 12px;
            font-size: 0.95rem;
        }

        .env-label { color: var(--text-muted); font-weight: 500; }

        .status-pill {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: bold;
            text-transform: uppercase;
            color: #1a1b1e;
        }
        
        .history-row {
            margin-top: 15px;
            padding-top: 10px;
            border-top: 1px solid var(--border);
        }
        .history-label { font-size: 0.75rem; color: var(--text-muted); margin-bottom: 5px; }
        .history-dots { display: flex; gap: 2px; height: 8px; }
        .dot { flex: 1; border-radius: 1px; opacity: 0.8; }

        /* Status Colors */
        .s-ONLINE { background-color: var(--success); }
        .s-SECURED { background-color: var(--warning); }
        .s-UNREACHABLE { background-color: var(--error); color: white; }
        .s-ERROR { background-color: var(--error); color: white; }
        
        .bg-ONLINE { background-color: var(--success); }
        .bg-SECURED { background-color: var(--warning); }
        .bg-UNREACHABLE { background-color: var(--error); }
        .bg-ERROR { background-color: var(--error); }

    </style>
</head>
<body>

<div class="container">
    <header>
        <h1>Metrc System Status</h1>
        <div class="timestamp" id="last-updated">Checking status...</div>
    </header>

    <div class="grid" id="dashboard">
        </div>
</div>

<script>
    async function loadStatus() {
        try {
            const response = await fetch('status.json');
            const history = await response.json();
            
            const latest = history[history.length - 1];
            const grid = document.getElementById('dashboard');
            
            if (latest) {
                const date = new Date(latest.timestamp);
                document.getElementById('last-updated').innerText = `Last Updated: ${date.toLocaleString()}`;
                
                latest.data.forEach(item => {
                    const card = document.createElement('div');
                    card.className = 'card';
                    
                    const stateHistoryDots = history.map(snapshot => {
                        const stateRecord = snapshot.data.find(r => r.state === item.state);
                        const status = stateRecord ? stateRecord.prod_status : 'UNKNOWN';
                        return `<div class="dot bg-${status}" title="${new Date(snapshot.timestamp).toLocaleString()}: ${status}"></div>`;
                    }).join('');

                    card.innerHTML = `
                        <div class="card-header">
                            <div class="state-badge">${item.state}</div>
                        </div>
                        
                        <div class="env-row">
                            <span class="env-label">Production Status</span>
                            <span class="status-pill s-${item.prod_status}">${item.prod_status}</span>
                        </div>
                        
                        <div class="history-row">
                            <div class="history-label">30-Day History (8x Daily)</div>
                            <div class="history-dots">${stateHistoryDots}</div>
                        </div>
                    `;
                    grid.appendChild(card);
                });
            }

        } catch (error) {
            document.getElementById('last-updated').innerText = "Failed to load status.json";
            console.error(error);
        }
    }

    loadStatus();
</script>

</body>
</html>
EOF
echo "   - Created index.html (History Supported)"


# 3. Create GitHub Actions Workflow
# ------------------------------------------------
mkdir -p .github/workflows
cat << 'EOF' > .github/workflows/update_status.yml
name: Update Metrc Status

on:
  schedule:
    - cron: '0 */3 * * *' # Run every 3 hours (8 times a day)
  workflow_dispatch:       # Button to run manually

permissions:
  contents: write

jobs:
  check-status:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v3

      - name: Run Status Script
        run: |
          chmod +x generate_status.sh
          ./generate_status.sh

      - name: Commit Results
        run: |
          git config --global user.name "StatusBot"
          git config --global user.email "bot@noreply.github.com"
          git add status.json
          git diff --quiet && git diff --staged --quiet || (git commit -m "Update status [skip ci]"; git push)
EOF
echo "   - Created .github/workflows/update_status.yml"

echo " "
echo "🎉 Build Complete!"
echo "---------------------------------------------------"
echo "To test locally run: ./generate_status.sh"
echo "Then open index.html in your browser."
echo "---------------------------------------------------"
