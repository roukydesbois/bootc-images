#!/bin/bash
# Adapted from https://download.argon40.com/scripts/argon-shutdown.sh
# Upstream only signals the case MCU when the IR config script exists, which we
# don't ship, so on poweroff/halt we always arm the RTC and cut power.

pythonbin=/usr/bin/python3
argononefanscript=/usr/share/argon/argononed.py
argoneonrtcscript=/usr/share/argon/argoneond.py

if [ -n "$1" ]; then
	$pythonbin $argononefanscript FANOFF
	if [ "$1" = "poweroff" ] || [ "$1" = "halt" ]; then
		$pythonbin $argoneonrtcscript SHUTDOWN
		$pythonbin $argononefanscript SHUTDOWN
	fi
fi
