#!/bin/bash
# Triggers a refresh on the running Metrc Status Dashboard
# Add this to crontab if you want external scheduling.
# Example: 0 */3 * * * /path/to/cron_refresh.sh

curl -s -X POST http://localhost:3005/api/refresh > /dev/null
if [ $? -eq 0 ]; then
    echo "$(date): Refresh triggered successfully."
else
    echo "$(date): Failed to trigger refresh. Is the server running?"
fi

