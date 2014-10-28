#!/usr/bin/python2 -u

import re
import os
import glob
import subprocess
import time
import snmp_passpersist as snmp

def update():

  pp.add_str('0.1', 'vg_values')
  pp.add_str('0.1.1', 'vg_name')

  result = subprocess.Popen('/sbin/vgs  --separator ":" --units b', shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

  lines = result.stdout.readlines()
  headers = lines.pop(0).strip().split(':')

  j = 1
  dev = headers.pop(0)
  for header in headers:
    pp.add_str('0.1.2.{0}'.format(j), header.replace('#', 'num_').replace('VG', 'dev').lower())
    j += 1

  i = 1  
  for line in lines:
    values = line.strip().split(':')
    dev = values.pop(0)
    pp.add_str('1.{0}.1'.format(i), dev)
    j = 1
    for value in values:
      pp.add_str('1.{0}.2.{1}'.format(i, j), value)
      j += 1
      
    i += 1
    
pp = snmp.PassPersist('.1.3.6.1.4.1.32473.103')
pp.start(update, 60)