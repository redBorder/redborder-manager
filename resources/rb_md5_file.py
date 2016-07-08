#!/usr/bin/python

import sys

ignored=18
count=0

if len(sys.argv) > 1:
  for arg in sys.argv[1:]:
    f = open(arg, "rb")
    try:
        byte = f.read(1)
        while byte != "":
            byte = f.read(1)
            count+=1
            if count>=ignored:
              sys.stdout.write(byte)
    finally: 
      f.close()
else:
  sys.stdout.write("Usage: rb_md5_file.py [ file ]\n")
