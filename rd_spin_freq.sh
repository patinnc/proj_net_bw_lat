#!/usr/bin/env bash

SCR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ODIR=$1
if [ "$1" == "" ]; then
  ODIR="./"
fi
if [ "$2" != "" ]; then
  NET_DEV=$2
fi

if [ -d $ODIR ]; then
  FILE=$ODIR/spin.txt
else
  FILE=$ODIR
fi
if [ ! -e $FILE ]; then
  echo "$0.$LINENO didn't find file= $FILE"
  exit 1
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
  #NET_IRQS=($(cat $MSI_FILE))
  readarray -t arr < $MSI_FILE
  #echo "$0.$LINENO arr= ${arr[@]}"
  NET_IRQS="${arr[@]}"
  #echo "$0.$LINENO net_irqs= $NET_IRQS"
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
  RING_BUFS=$(ethtool -l $NET_DEV |grep Combined|tail -1|$AWK_BIN '{printf("%s\n", $2);}')
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
      continue
    fi
    str_arr=(${str// / })
    #echo "str0= ${str_arr[0]} str1= ${str_arr[1]} line= ${ARR[$i]}"
    IRQ_AFF_ARR[${str_arr[0]}]=${str_arr[1]}
    #echo "IRQ_AFF_ARR[${str_arr[0]}]=${IRQ_AFF_ARR[${str_arr[0]}]}"
  done
else
  : > $SMP_FILE # set file sz to 0 bytes
  for i in $NET_IRQS; do
    #printf "irq %s\n" $i
    CPU=$(cat /proc/irq/$i/smp_affinity_list)
    if [[ "$CPU" == *"-"* ]] || [[ "$CPU" == *","* ]]; then
      continue
    fi
    echo "$i $CPU" >> $SMP_FILE
    IRQ_AFF_ARR[$i]=$CPU
    #echo "IRQ_AFF_ARR[$i]=${IRQ_AFF_ARR[$i]}"
  done
  cat $SMP_FILE
fi
INT_FILE="$ODIR/interrupts_0.txt"
if [[ -d $ODIR ]] && [[ "$ODIR" != "./" ]] && [[ -e $INT_FILE ]]; then
  PROC_INTS=$(cat $INT_FILE)
else
  PROC_INTS=$(cat /proc/interrupts)
fi

SEP=
  j=0
  #echo "$0.$LINENO net_irqs= $NET_IRQS"
  for i in $NET_IRQS; do
    #printf "irq %s\n" $i
    #CPU=$(cat /proc/irq/$i/smp_affinity_list)
    CPU=${IRQ_AFF_ARR[$i]}
    if [ "$CPU" == "" ]; then
      echo "$0.$LINENO messed up geting smp_affinity_list for irq $i. Does file $SMP_FILE exist?"
      continue
      exit 1
    fi
    MULTI=0
    INT_LINE=$(echo "$PROC_INTS" | grep " $i: " | sed 's/  */ /g')
    if [[ "$CPU" == *"-"* ]] || [[ "$CPU" == *","* ]]; then
      CMP_STR=$(echo "$INT_LINE" | sed 's/ 0//g' | sed 's/  */ /g')
      MULTI=1
      continue
    fi
    VAL=$(echo "$INT_LINE" | $AWK_BIN -v cpu="$CPU" '{print $(cpu+2);}')
    if [[ "$j" -le "$RING_BUFS" ]]; then
     #echo "$0.$LINENO j($j) <= ringbufs($RING_BUFS) irq= $i cpu= $CPU val= $VAL"
     INT_ARR[$j]=$i
     CPU_ARR[$j]=$CPU
     VAL_ARR[$j]=$VAL
    #else
    # echo "$0.$LINENO j($j) > ringbufs($RING_BUFS) irq= $i cpu= $CPU"
     #continue
    fi
    j=$((j+1))
    IRQ_CPUS="${IRQ_CPUS}${SEP}${CPU}"
    SEP=" "
  done

echo "irq_cpus= ${#CPU_ARR[@]}"
#echo "irq_cpus arr= ${CPU_ARR[@]}"

SPN_ARR=($(awk '/^work=.*threads/{v=$2;gsub(/,/, "", v); printf("%s\n", v);v=$4;gsub(/,/, "", v);printf("%s\n", v);exit(0);}' $FILE))
  ck_last_rc $? $LINENO
echo "spn_arr= ${SPN_ARR[@]}"
SPN_WRK=${SPN_ARR[0]}
SPN_THR=${SPN_ARR[1]}
echo "spin_work $SPN_WRK"
echo "spin_cpus $SPN_THR"
CHIP_FAM=$($SCR_DIR/../60secs/decode_cpu_fam_mod.sh | sed 's/ /_/g' | awk '{printf("%s", tolower($0));exit(0);}')
  ck_last_rc $? $LINENO
REF_PERF=
if [ "$CHIP_FAM" == "ice_lake" ]; then
  REF_PERF=
  if [ ! -e spin_ref.txt ]; then
    $SCR_DIR/../patrick_fay_bin/spin.x -w spin -t 10 > spin_ref.txt
  fi
  # work= spin, threads= 96, total perf= 35.870 Gops/sec
  REF_PERF=$(awk '
    BEGIN{perf=0;}
    /^work= spin, threads=.*total perf= .*Gops\/sec/{
      thrds= $4+0;
      perf= $7/thrds;
    }
    END{
      printf("%.5f", perf);
    }' spin_ref.txt)
  ck_last_rc $? $LINENO
  echo "$0.$LINENO $CHIP_FAM ref perf= $REF_PERF"
  if [ "$REF_PERF" == "0" ]; then
    echo "$0.$LINENO something wrong running above awk script. got REF_PERF= 0. maybe spin_ref.txt not found or spin work type != 'spin'. bye"
    exit 1
  fi
fi
SPN_GOPS=$(awk '
  /^cpu.*Gops=/{
    for(i=1;i<NF;i++){
      if ($i == "Gops=") {
        sum += $(i+1);
      }
    }
  }
  END{
   printf("%.3f", sum);
  }' $FILE)
  ck_last_rc $? $LINENO

$AWK_BIN -v ref_perf="$REF_PERF"  -v irq_cpus="${#CPU_ARR[@]}" '
  BEGIN{
    # just to avoid div by 0
    cputm = 1.0;
  }
  /^work= .*, threads= / {
    spn_cpus= $4+0;
    wrk_type= $2;
  }
  /^num_cpus= /{
    num_cpus= $2;
  }
  /^process cpu_time= .* secs, / {
    tm_cpu = $3 + 0;
  }
  /^cpu\[ /{
    for (i=1; i<NF;i++){
      if($i == "dura="){
        dura += $(i+1);
    tm = $(i+1);
      }
      if($i == "cpu_tm="){
        cputm = $(i+1)+0;
      }
      if($i == "Gops="){
        sum += $(i+1)/cputm;
    #printf("sum= %.3f, gops= %.3f cputm= %.3f\n", sum, $(i+1), cputm);
        n++;
        sum1 += $(i+3);
      }
    }
  }
  END{
    if (ref_perf != "") {
      if (wrk_type != "spin,") {
       printf("for ice lake spin.x needs to be run with -w spin instead of work type %s. bye\n", wrk_type) > "/dev/stderr";
       exit(1);
      }
      sum1 = n*ref_perf;
    }
    v=sum/sum1;
    if (v > 0.9999) { v = 1.0;}
    printf("sum= %.3f sum1= %.3f %%ratio= %.3f missing_perfTL= %.3f tm_cpu= %f\n", sum, sum1, v*100, tm_cpu*(1-v), tm_cpu);
  }' $FILE
  ck_last_rc $? $LINENO

INT_FILE="$ODIR/interrupts_1.txt"
if [[ -d $ODIR ]] && [[ "$ODIR" != "./" ]] && [[ -e $INT_FILE ]]; then
  PROC_INTS=$(cat $INT_FILE)
fi
echo "spin total Gops $SPN_GOPS"
SPN_DURA=$(awk -v spn_gops="$SPN_GOPS" '/^process cpu_time=/{for(i=1;i<NF;i++){if ($i == "tm_loop=") {printf("Gops/s= %.3f tm_loop= %.3f\n", spn_gops/$(i+1), $(i+1));exit(0);}}}' $FILE)
  ck_last_rc $? $LINENO
echo "spin total $SPN_DURA"
#process cpu_time= 2881.327057 secs, elapsed_secs= 30.137 secs, tm_loop= 30.018 tm_bef_loop= 0.119 at spin_wait/spin.cpp 3354
grep "^process cpu_time= " $FILE
exit 0

