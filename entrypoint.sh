#!/bin/bash
set -e

# Sync models from bind mount to named volume if the source exists and is not empty
if [ -d "/host-models" ] && [ "$(ls -A /host-models 2>/dev/null)" ]; then
    echo "Source models found. Starting synchronization..."

    # Use rsync to efficiently sync files.
    # -a: archive mode (preserves permissions, timestamps, etc.)
    # -v: verbose (shows which files are being transferred)
    # --ignore-existing: This option can be used if you only want to copy new files
    # and not update existing ones. For a true sync, it's better to omit it.
    rsync -av /host-models/ /models/

    echo "Models synchronized successfully."
else
    echo "No host models found or the host-models directory is empty; skipping sync."
fi

# Start llama-swap with the original entrypoint
exec /app/llama-swap -config /app/config.yaml "$@"