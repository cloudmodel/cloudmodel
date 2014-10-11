#!/usr/bin/python2 -u

import re
import os
import glob
import subprocess
import multiprocessing
import time
import snmp_passpersist as snmp

interval = 1

def get_values():
  values = {}

  for machine in glob.glob("/sys/fs/cgroup/cpu/machine.slice/machine-lxc\\x2d*"):
    machine_name = machine.replace('/sys/fs/cgroup/cpu/machine.slice/machine-lxc\\x2d', '').replace('.scope', '').replace('\\x2d', '-')

    file = open('{0}/cpuacct.usage'.format(machine, 'r'))
    values[machine_name] = file.read().strip()

  return values

def update():
  cpus = multiprocessing.cpu_count()

  startval = get_values()  
  time.sleep(interval)
  endval = get_values()

  pp.add_str('0.1', 'machine_values')
  pp.add_str('0.1.1', 'machine_name')
  pp.add_str('0.1.2.1', 'mem_available')
  pp.add_str('0.1.2.2', 'mem_used')
  pp.add_str('0.1.3.1', 'cpu_usage')

  i = 1
  for machine in glob.glob("/sys/fs/cgroup/memory/machine.slice/machine-lxc\\x2d*"):
    machine_name = machine.replace('/sys/fs/cgroup/memory/machine.slice/machine-lxc\\x2d', '').replace('.scope', '').replace('\\x2d', '-')
    pp.add_str('1.{0}.1'.format(i), machine_name)

    file = open('{0}/memory.limit_in_bytes'.format(machine, 'r'))
    pp.add_int('1.{0}.2.1'.format(i), file.read().strip())
    file = open('{0}/memory.usage_in_bytes'.format(machine, 'r'))
    pp.add_int('1.{0}.2.2'.format(i), file.read().strip())

    if machine_name in startval and machine_name in endval:
      delta = int(endval[machine_name]) - int(startval[machine_name])
      dpns = float(delta / interval)
      dps = dpns / 10000000
      usage = dps / cpus
      pp.add_str('1.{0}.3.1'.format(i), usage)

    i += 1

  pp.add_str('0.2.0', 'number of machines')
  pp.add_cnt_64bit('0.2.1', i-1)

pp = snmp.PassPersist('.1.3.6.1.4.1.32473.100')
pp.start(update, 60)