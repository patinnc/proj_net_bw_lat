#!/usr/bin/env bash

SCR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ODIR=$1
if [ "$1" == "" ]; then
  ODIR="./"
fi
NET_DEV=eth0
if [ "$2" != "" ]; then
  NET_DEV=$2
fi

RET_CD=0
ck_last_rc() {
   local RC=$1
   local FROM=$2
   if [[ $RC -gt 0 ]] || [[ "$GOT_QUIT" == "1" ]]; then
      echo "$0: got non-zero RC=$RC at $LINENO. called from line $FROM. GOT_QUIT= $GOT_QUIT" >> /dev/stderr
      RET_CD=1
      #kill -term $$ # send this program a terminate signal
      if [[ "$GOT_QUIT" == "1" ]]; then
        exit 1
      fi
      exit $RC
   fi
}

AWK_BIN=awk

MSI_FILE="$ODIR/msi_irqs_eth0.txt"
if [[ -d $ODIR ]] && [[ "$ODIR" != "./" ]] && [[ -e "$MSI_FILE" ]]; then
  NET_IRQS=$(cat $MSI_FILE)
  if [ -e "$MSI_FILE" ]; then
    echo "$0.$LINENO file exists $MSI_FILE"
  fi
  #echo "$0.$LINENO net_irqs= $NET_IRQS  msi_file= $MSI_FILE"
else
  NET_IRQS=$(ls -1 /sys/class/net/$NET_DEV/device/msi_irqs/ | sort -nk 1 );
  #echo "$0.$LINENO net_irqs= $NET_IRQS"
  echo "$NET_IRQS" > $MSI_FILE
fi
if [[ -d $ODIR ]] && [[ "$ODIR" != "./" ]] && [[ -e $ODIR/ethtool.txt ]]; then
  RING_BUFS=$(cat $ODIR/ethtool.txt |grep Combined|tail -1|$AWK_BIN '{printf("%s\n", $2);}')
  ck_last_rc $? $LINENO
else
  RING_BUFS=$(sudo ethtool -l $NET_DEV|grep Combined|tail -1|$AWK_BIN '{printf("%s\n", $2);}')
  ck_last_rc $? $LINENO
fi
declare -A IRQ_AFF_ARR
SMP_FILE=$ODIR/smp_affinity_list_eth0.txt
SV_IFS=$IFS

if [[ -d $ODIR ]] && [[ "$ODIR" != "./" ]] && [[ -e $SMP_FILE ]]; then
  IFS=$'\n'
  ARR=($(cat $SMP_FILE))
  IFS="$SV_IFS"
  for ((i=0; i < ${#ARR[@]}; i++)); do
    str=${ARR[$i]}
    if [[ "$str" == *"-"* ]] || [[ "$str" == *","* ]]; then
     echo "$0.LINENO skip - or , $str"
      continue
    fi
    str_arr=(${str// / })
    #echo "str0= ${str_arr[0]} str1= ${str_arr[1]} line= ${ARR[$i]}"
    IRQ_AFF_ARR[${str_arr[0]}]=${str_arr[1]}
    #echo "IRQ_AFF_ARR[${str_arr[0]}]=${IRQ_AFF_ARR[${str_arr[0]}]}"
  done
else
  : > $SMP_FILE # set file sz to 0 bytes
  #echo "$0.$LINENO net_irqs $NET_IRQS"
  j=-1
  for i in $NET_IRQS; do
    #printf "irq %s\n" $i
    if [ ! -e /proc/irq/$i/smp_affinity_list ]; then
      continue
    fi
    j=$((j+1))
    CPU=$(cat /proc/irq/$i/smp_affinity_list)
    if [[ "$CPU" == *"-"* ]] || [[ "$CPU" == *","* ]]; then
     echo "$0.LINENO skip - or , $CPU"
      continue
    fi
    echo "$i $CPU" >> $SMP_FILE
    IRQ_AFF_ARR[$j]=$CPU
  done
  #cat $SMP_FILE
fi
exit 0
