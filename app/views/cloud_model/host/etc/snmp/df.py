#!/usr/bin/python2 -u

import re
import os
import glob
import subprocess
import time
import snmp_passpersist as snmp

re_line = re.compile('(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\%\s+(\S+)')

def update():

  pp.add_str('0.1', 'df_values')
  pp.add_str('0.1.1', 'mountpoint')
  pp.add_str('0.1.2.1', 'device')
  pp.add_str('0.1.2.2', 'bytes_total')
  pp.add_str('0.1.2.3', 'bytes_used')
  pp.add_str('0.1.2.4', 'bytes_available')
  pp.add_str('0.1.2.5', 'usage')

  result = subprocess.Popen('/bin/df -B 1', shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

  lines = result.stdout.readlines()
  header_line = lines.pop(0).strip()
#  match_header = re_line.match(header_line)

  i = 1
  for line in lines:
    match_line = re_line.match(line)
    if match_line:
      pp.add_str('1.{0}.1'.format(i), match_line.group(6))
      pp.add_str('1.{0}.2.1'.format(i), match_line.group(1))
      pp.add_cnt_64bit('1.{0}.2.2'.format(i), match_line.group(2))
      pp.add_cnt_64bit('1.{0}.2.3'.format(i), match_line.group(3))
      pp.add_cnt_64bit('1.{0}.2.4'.format(i), match_line.group(4))
      pp.add_int('1.{0}.2.5'.format(i), match_line.group(5))
    
    i += 1

pp = snmp.PassPersist('.1.3.6.1.4.1.32473.104')
pp.start(update, 60)
