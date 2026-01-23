console.log("Starting server script...");
const express = require('express');
const axios = require('axios');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3005;
const HISTORY_FILE = path.join(__dirname, 'history.json');
const CHECK_INTERVAL_MS = 3 * 60 * 60 * 1000; // Check every 3 hours

// States list
const states = [
    "ak", "al", "ca", "co", "dc", "gu", 
    "il", "ky", "la", "ma", "md", "me", "mi", 
    "mn", "mo", "ms", "mt", "nv", "ny", "oh", 
    "ok", "or", "ri", "sd", "va", "wv"
];

// In-memory cache of history to reduce file reads
let historyCache = [];

// --- Helper Functions ---

// Load history from disk on startup
function loadHistory() {
    try {
        if (fs.existsSync(HISTORY_FILE)) {
            const data = fs.readFileSync(HISTORY_FILE, 'utf8');
            historyCache = JSON.parse(data);
            console.log(`Loaded ${historyCache.length} historical records.`);
        }
    } catch (err) {
        console.error("Failed to load history file:", err);
        historyCache = [];
    }
}

// Save history to disk
function saveHistory() {
    try {
        fs.writeFileSync(HISTORY_FILE, JSON.stringify(historyCache, null, 2));
    } catch (err) {
        console.error("Failed to save history file:", err);
    }
}

// Prune records older than 30 days
function pruneHistory() {
    const thirtyDaysAgo = Date.now() - (30 * 24 * 60 * 60 * 1000);
    const initialLength = historyCache.length;
    historyCache = historyCache.filter(record => new Date(record.timestamp).getTime() > thirtyDaysAgo);
    
    if (historyCache.length < initialLength) {
        console.log(`Pruned ${initialLength - historyCache.length} old records.`);
        saveHistory();
    }
}

// Perform the checks
async function performChecks() {
    console.log("Starting scheduled status check...");
    const checks = [];
    const timestamp = new Date().toISOString();

    states.forEach(state => {
        checks.push(checkUrl(`https://api-${state}.metrc.com`, state, 'Main'));
    });

    try {
        const results = await Promise.all(checks);
        
        // Group by state for this specific timestamp
        const snapshot = {
            timestamp: timestamp,
            states: {}
        };

        results.forEach(result => {
            if (!snapshot.states[result.state]) {
                snapshot.states[result.state] = { main: null };
            }
            if (result.type === 'Main') {
                snapshot.states[result.state].main = result;
            }
        });

        // Add to history
        historyCache.push(snapshot);
        
        // Cleanup
        pruneHistory();
        saveHistory();
        console.log("Status check complete and saved.");

    } catch (error) {
        console.error("Error during scheduled check:", error);
    }
}

async function checkUrl(url, state, type) {
    const start = Date.now();
    try {
        const response = await axios.get(url, { 
            validateStatus: () => true, 
            timeout: 5000 
        });
        
        const duration = Date.now() - start;
        const code = response.status;
        let status = "UNKNOWN";
        let statusClass = "unknown";

        if (code === 200) {
            status = "ONLINE";
            statusClass = "success";
        } else if (code === 401 || code === 403) {
            status = "SECURED (UP)";
            statusClass = "warning";
        } else if (code === 404) {
            status = "NOT FOUND";
            statusClass = "info";
        } else if (code >= 500) {
            status = "SERVER ERROR";
            statusClass = "danger";
        } else {
            status = `CODE: ${code}`;
            statusClass = "secondary";
        }

        // Minify stored data to save space
        return { state, type, code, statusClass, duration }; 

    } catch (error) {
        const duration = Date.now() - start;
        return { 
            state, 
            type, 
            code: 0, 
            statusClass: "danger", 
            duration,
            error: "Unreachable" 
        };
    }
}

// --- Server Setup ---

app.use(express.static(path.join(__dirname, 'public')));

// API: Get latest status (derived from history or fresh check if empty)
app.get('/api/status', async (req, res) => {
    if (historyCache.length > 0) {
        // Return the most recent snapshot
        const latest = historyCache[historyCache.length - 1];
        
        // Convert map back to array for frontend compatibility
        const responseData = Object.keys(latest.states).map(stateCode => {
            return {
                state: stateCode,
                main: latest.states[stateCode].main
            };
        }).sort((a, b) => a.state.localeCompare(b.state));
        
        res.json({
            timestamp: latest.timestamp,
            data: responseData
        });
    } else {
        // If server just started and hasn't run a check yet, trigger one
        await performChecks();
        res.redirect('/api/status');
    }
});

// API: Get full history
app.get('/api/history', (req, res) => {
    res.json(historyCache);
});

// API: Force a refresh (for debugging or manual button)
app.post('/api/refresh', async (req, res) => {
    await performChecks();
    res.json({ message: "Checks performed" });
});

// Start Server & Scheduler
app.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}`);
    
    loadHistory();
    
    // Run an immediate check if history is empty
    if (historyCache.length === 0) {
        performChecks();
    }

    // Schedule periodic checks
    setInterval(performChecks, CHECK_INTERVAL_MS);
});