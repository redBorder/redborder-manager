#!/usr/bin/python

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

def log(msg):
    sys.stderr.write("[%s] " % datetime.datetime.now())
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()

def output(msg):
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()

def die():
    log("Process timed out, about to exit ...")
    print(json.dumps({"_error":"timed out"}))
    sys.exit(1)

log("PID=%d" % os.getpid())
log("PARENT PID=%d" % os.getppid())
log("CWD=%s" % os.getcwd())

if len(sys.argv) > 2:
    path_yara_rules = sys.argv[2]
else:
    path_yara_rules = "yara_rules/"

start = datetime.datetime.now()
sigs = dict([(name.replace(".yara", "").split("/")[-1], name) for name in glob.glob(path_yara_rules+"*.yar*")])
rules = yara.compile(filepaths=sigs)
end = datetime.datetime.now()
log("Loaded yara rules in %s: %s"%( end - start, json.dumps(sigs, indent=4)))

matches = {}

def match_callback(data):
    if data.get("matches", False):
        data.pop("matches")
        if "strings" in data:
            data.pop("strings")
        if "rule" in data and isinstance(data["rule"], bytes):
            data["rule"] = data["rule"].decode('utf-8', errors='ignore')
        if "tags" in data and not data["tags"]:
            data.pop("tags")
        if "meta" in data and "description" in data["meta"] and isinstance(data["meta"]["description"], bytes):
            data["meta"]["description"] = data["meta"]["description"].decode('utf-8', errors='ignore')
        matches['matches'].append(data)
    return yara.CALLBACK_CONTINUE

# Open and read the target file
target_file = sys.argv[1]

log("Openning %s for reading ..."%(target_file))
data = open(target_file, 'rb').read()

log("Performing matching on %d bytes of data ..."%len(data))
matches = {'filename': os.path.basename(target_file), 'matches':[]}

start = datetime.datetime.now()
rules.match(data=data, callback=match_callback)
end = datetime.datetime.now()

log("Done matching %d bytes in %s, printing results ..."%(len(data), end - start))
output(json.dumps(matches))
log("Process Exiting")
