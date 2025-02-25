#!/bin/bash

# Exit immediately if any command fails
# set -e

# Get the installed version of Chef Workstation using `chef -v`
CHEF_VERSION=$(chef -v 2>/dev/null | grep -oP 'Chef Workstation version: \K[0-9]+\.[0-9]+\.[0-9]+')

# Verify if the version was retrieved successfully
if [[ -z "$CHEF_VERSION" ]]; then
    echo "ERROR: Could not retrieve the Chef Workstation version."
    exit 1
else
    echo "INFO: Chef Workstation version detected: $CHEF_VERSION"
fi

# Define the target version that requires modification
TARGET_VERSION="25.2.1075"

# Check if the installed version matches the target version
if [[ "$CHEF_VERSION" == "$TARGET_VERSION" ]]; then
    echo "Detected Chef Workstation version $CHEF_VERSION, modifying OpenSSL gem..."
    
    # Define the path where Chef Workstation's Ruby gems are located
    GEM_PATH="/opt/chef-workstation/embedded/lib/ruby/gems/3.1.0/specifications"
    
    # Name of the gem specification file to be replaced
    GEM_NAME="openssl-3.0.1.gemspec"
    
    # Backup directory where the original gem specification will be stored
    BACKUP_DIR="$GEM_PATH/backup"
    
    # Path to the new gem specification file that will replace the existing one
    NEW_GEM="$GEM_PATH/openssl-3.2.0.gemspec"

    # Ensure the backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        echo "INFO: Created backup directory: $BACKUP_DIR"
    fi

    # Check if the original gem file exists
    if [[ -f "$GEM_PATH/default/$GEM_NAME" ]]; then
        # Backup the original gem specification file before removing it
        install -D "$GEM_PATH/default/$GEM_NAME" "$BACKUP_DIR/$GEM_NAME"
        rm -f "$GEM_PATH/default/$GEM_NAME"
        echo "INFO: Moved $GEM_NAME to $BACKUP_DIR"
    fi

    # Check if the new gem file exists and is not empty
    if [[ -s "$NEW_GEM" ]]; then
        cp "$NEW_GEM" "$GEM_PATH/default/"
        echo "INFO: Replaced with openssl-3.2.0.gemspec"
    else
        echo "ERROR: The new gem file is empty or not found, cannot replace."
        exit 1
    fi
else
    echo "INFO: Chef Workstation version $CHEF_VERSION does not match target ($TARGET_VERSION). No changes made."
fi
