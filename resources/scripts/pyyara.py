#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with this
# work for additional information regarding copyright ownership. The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.
#
#  Copyright 2013 Endgame Inc.

import sys
import os
import glob
import yara
import json
import datetime

def log(msg: str):
    """Log messages to stderr with timestamps."""
    sys.stderr.write(f"[{datetime.datetime.now()}] {msg}\n")
    sys.stderr.flush()

def output(msg: str):
    """Write messages to stdout."""
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()

def die():
    """Graceful failure handler."""
    log("Process timed out, about to exit ...")
    print(json.dumps({"_error": "timed out"}))
    sys.exit(1)

# Logging basic process information
log(f"PID={os.getpid()}")
log(f"PARENT PID={os.getppid()}")
log(f"CWD={os.getcwd()}")

# Get paths from command-line arguments
if len(sys.argv) > 2:
    path_yara_rules = sys.argv[2]
else:
    path_yara_rules = "yara_rules/"

# Load YARA rules
start = datetime.datetime.now()
sigs = {
    os.path.basename(name).replace(".yara", "").replace(".yar", ""): name
    for name in glob.glob(os.path.join(path_yara_rules, "*.yar*"))
}
rules = yara.compile(filepaths=sigs)
end = datetime.datetime.now()

log(f"Loaded yara rules in {end - start}: {json.dumps(sigs, indent=4)}")

matches = {}

def match_callback(data):
    """Callback function for YARA matches."""
    if data.get("matches", False):
        data.pop("matches", None)
        data.pop("strings", None)
        # Convert rule and description to safe strings
        if "rule" in data:
            val = data["rule"]
            if isinstance(val, bytes):
                val = val.decode("utf-8", errors="ignore")
            data["rule"] = str(val)

        if "tags" in data and not data["tags"]:
            data.pop("tags", None)

        if "meta" in data and "description" in data["meta"]:
            desc = data["meta"]["description"]
            if isinstance(desc, bytes):
                desc = desc.decode("utf-8", errors="ignore")
            data["meta"]["description"] = str(desc)

        matches["matches"].append(data)
    return yara.CALLBACK_CONTINUE

# Open and read target file
if len(sys.argv) < 2:
    log("Usage: python3 script.py <file_to_scan> [yara_rules_path]")
    sys.exit(1)

target_file = sys.argv[1]
log(f"Opening {target_file} for reading ...")

with open(target_file, "rb") as f:
    data = f.read()

log(f"Performing matching on {len(data)} bytes of data ...")
matches = {"filename": os.path.basename(target_file), "matches": []}

# Run YARA matching
start = datetime.datetime.now()
rules.match(data=data, callback=match_callback)
end = datetime.datetime.now()

log(f"Done matching {len(data)} bytes in {end - start}, printing results ...")
output(json.dumps(matches, ensure_ascii=False, indent=2))
log("Process Exiting")
