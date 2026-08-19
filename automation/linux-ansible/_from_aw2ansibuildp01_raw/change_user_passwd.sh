#!/bin/bash
#
# change_user_passwd.sh
# Change password for 1-3 users on a Linux host (RedHat/Debian)
#

set -euo pipefail

# Show help
if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 user1 [user2] [user3]"
    echo "Example: $0 millershuxadmin"
    echo "Example: $0 user1 user2 user3"
    exit 0
fi

# Validate number of users
if [[ $# -lt 1 || $# -gt 3 ]]; then
    echo "ERROR: You must provide between 1 and 3 usernames."
    echo "Usage: $0 user1 [user2] [user3]"
    exit 1
fi

# Visible password prompt
read -p "Enter the NEW password (will be set for all users): " password
echo

# Process each user
for user in "$@"; do
    if ! id "$user" &>/dev/null; then
        echo "WARNING: User '$user' does not exist on this host. Skipping."
        continue
    fi

    echo "$user:$password" | sudo chpasswd
    if [[ $? -eq 0 ]]; then
        echo "SUCCESS: Password changed for user '$user'"
    else
        echo "FAILED: Could not change password for user '$user'"
    fi
done

echo "Done."
