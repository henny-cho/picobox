#!/bin/sh
echo "--- PicoBox Container Started ---"
echo "Hostname: $(hostname)"
echo "PID: $$"
echo "Environment:"
env
echo "Sleeping for 60 seconds..."
sleep 60
