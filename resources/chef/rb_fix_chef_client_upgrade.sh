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

    # Check if both files exist before making changes
    if [[ -f "$GEM_PATH/default/$GEM_NAME" ]]; then
        if [[ -f "$NEW_GEM" && -s "$NEW_GEM" ]]; then
            # Backup the original gem specification file before removing it
            cp -a "$GEM_PATH/default/$GEM_NAME" "$BACKUP_DIR/$GEM_NAME"
            echo "INFO: Backed up $GEM_NAME to $BACKUP_DIR"

            # Remove the original gem specification file
            rm -f "$GEM_PATH/default/$GEM_NAME"
            echo "INFO: Removed $GEM_NAME from $GEM_PATH/default/"

        else
            echo "ERROR: New gemspec file ($NEW_GEM) is missing or empty. Aborting."
            exit 1
        fi
    else
        echo "ERROR: Original gemspec file ($GEM_NAME) not found. Cannot proceed."
        exit 1
    fi
else
    echo "INFO: Chef Workstation version $CHEF_VERSION does not match target ($TARGET_VERSION). No changes made."
fi
