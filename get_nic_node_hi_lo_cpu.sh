#!/usr/bin/env bash

# arg1 is network device (do ./set_eth0.sh -h to get list of devices
# looks at numa node for device. then returns the hi performance cpu for that node (the HT1 thread the first core on that node)
#  adn the lo performance cpu for the other numa node (the HT1 thread the first core on the other node)
WANT="hi"
NET_DEV=eth0
if [ "$1" != "" ]; then
  NET_DEV=$1
fi
NUMA_CPU=()
for ((i=0; i < 2; i++)); do
  NUMA_CPU[i]=$(lscpu |grep NUMA|awk -v nd="$i" '/NUMA node/{str="node"nd; if ($2!=str){next;}; n = split($4,arr,","); nn=split(arr[2], brr,"-");printf("%s\n", brr[1]);}')
  echo "$0.$LINENO numa_cpu[$i]= ${NUMA_CPU[$i]}"
done
ETH_NODE=$(cat /sys/class/net/$NET_DEV/device/numa_node)
if [ "$ETH_NODE" == "0" ]; then
  HI=${NUMA_CPU[0]}
  LO=${NUMA_CPU[1]}
else
  HI=${NUMA_CPU[1]}
  LO=${NUMA_CPU[0]}
fi
if [ "$WANT" == "node" ]; then
 echo "node_with_nic= $ETH_NODE"
fi
if [[ "$WANT" == "hi" ]] || [[ "$WANT" == "high" ]]; then
 echo "hi_perf_cpu= $HI"
fi
if [[ "$WANT" == "lo" ]] || [[ "$WANT" == "low" ]]; then
 echo "lo_perf_cpu= $LO"
fi
NUM_CPUS=$(grep -c processor /proc/cpuinfo)
QTR=$((NUM_CPUS/4))
HLF=$((NUM_CPUS/2))
echo "$0.$LINENO num_cpus= $NUM_CPUS eth_numa_node= $ETH_NODE hi= $HI lo= $LO"
exit 0

