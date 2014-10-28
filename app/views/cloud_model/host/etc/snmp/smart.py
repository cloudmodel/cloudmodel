#!/usr/bin/python2 -u

import re
import os
import glob
import subprocess
import time
import snmp_passpersist as snmp

re_status = re.compile('SMART overall-health self-assessment test result: (.*)')
re_attr = re.compile('([\d]+) ([\S]+)\s+0x[0-9a-f]+[\s]+[\d]+[\s]+[\d]+[\s]+[\d]+[\s]+[\S]+[\s]+[\S]+[\s]+[\S]+[\s]+([\d]+)')

def parse_line(line):
  match_status = re_status.match(line)
  if match_status:
    return ['1', 'smart_status', match_status.group(1)]

  match_attr = re_attr.match(line)
  if match_attr:
     return ['2.{0}'.format(match_attr.group(1)), match_attr.group(2), match_attr.group(3)]
  return None

def update():

  pp.add_str('0.1', 'disk_values')
  pp.add_str('0.1.1', 'disk_name')

  i = 1
  for disk in glob.glob("/dev/sd[a-z]"):
    disk_name = disk.replace('/dev/', '').replace('.scope', '')
    pp.add_str('1.{0}.1'.format(i), disk_name)

    result = subprocess.Popen('/usr/sbin/smartctl -a {0}'.format(disk), shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    for line in result.stdout.readlines():
      line_parsed = parse_line(line.strip())
      if line_parsed:
          pp.add_str('0.1.2.{0}'.format(line_parsed[0]), line_parsed[1])
          pp.add_str('1.{0}.2.{1}'.format(i, line_parsed[0]), line_parsed[2])
      
    i += 1
    
pp = snmp.PassPersist('.1.3.6.1.4.1.32473.101')
pp.start(update, 60)