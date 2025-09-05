#!/bin/sh

# File to watch
CONFIG_FILE="/app/config.yaml"

# Initialize the last modified time
LAST_MODIFIED=$(stat -c %Y "$CONFIG_FILE")

while true; do
  # Get the current modified time
  CURRENT_MODIFIED=$(stat -c %Y "$CONFIG_FILE")

  # Check if the file has been modified
  if [ "$CURRENT_MODIFIED" -ne "$LAST_MODIFIED" ]; then
    echo "File has been modified."

    echo "Restarting llamaswap container..."
    docker restart llama-swap
    echo "Restarted llamaswap container..."

    # Update the last modified time
    LAST_MODIFIED=$CURRENT_MODIFIED
  fi

  # Wait for a while before checking again
  sleep 5
done