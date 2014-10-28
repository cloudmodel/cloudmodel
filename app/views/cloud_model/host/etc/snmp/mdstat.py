#!/usr/bin/python2 -u

import re
import os
import glob
import subprocess
import time
import snmp_passpersist as snmp

re_line = re.compile('(.*) : (.*)')
re_dev = re.compile('/dev/md[\d]+')
re_number = re.compile('([\d]*).*')
keys = []

def add_parse_line(i, line):
  match_line = re_line.match(line)
  if match_line:
    key = match_line.group(1)
    value = match_line.group(2)
     
    try:
      index = keys.index(key) + 1
    except:
      keys.append(key)
      index = len(keys)
    
    pp.add_str('0.1.2.{0}'.format(index), key)
      
    if key in ['Array Size', 'Used Dev Size']:
      match_number = re_number.match(value)
      pp.add_str('1.{0}.2.{1}'.format(i, index), match_number.group(1))
    else:
      pp.add_str('1.{0}.2.{1}'.format(i, index), value)

  # TODO: parse disk values
  

def update():

  pp.add_str('0.1', 'md_values')
  pp.add_str('0.1.1', 'md_name')

  i = 1  
  for md_dev in glob.glob("/dev/md*"):
    if re_dev.match(md_dev): 
      pp.add_str('1.{0}.1'.format(i), md_dev.replace('/dev/', ''))
      result = subprocess.Popen('mdadm --verbose --detail {0}'.format(md_dev), shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    
      for line in result.stdout.readlines():
        add_parse_line(i, line.strip()) 
          
      i += 1
    
pp = snmp.PassPersist('.1.3.6.1.4.1.32473.102')
pp.start(update, 60)