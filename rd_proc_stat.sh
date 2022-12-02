#!/bin/bash

# old (pre getops): arg1 is dir with proc_stat_0.txt proc_stat_1.txt tm_0.txt tm_1.txt
# now -d output_dir_with_files_to_be_read -p proc_stat_0.txt -p proc_stat_1.txt -t tm_0.txt -t tmp1.txt
SCR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export LC_ALL=C

OSTYP=$OSTYPE
if [[ "$OSTYP" == "linux-gnu"* ]]; then
  for i in . $SCR_DIR/../patrick_fay_bin; do
    if [ -e $i/gawk ]; then
      AWK_BIN=$i/gawk
      break
    fi
  done
elif [[ "$OSTYP" == "darwin"* ]]; then
   # Mac OSX
  AWK_BIN=gawk
fi
ck_last_rc() {
   local RC=$1
   local FROM=$2
   if [ $RC -gt 0 ]; then
      echo "$0: got non-zero RC=$RC at $LINENO. called from line $FROM" > /dev/stderr
      exit $RC
   fi
}
PSTAT_IN=()
TM_IN=()

while getopts "hvxd:f:p:s:t:" opt; do
  case ${opt} in
    d )
      ODIR_IN=$OPTARG
      ;;
    f )
      OUTFILE=$OPTARG
      ;;
    p )
      PSTAT_IN+=($OPTARG)
      ;;
    s )
      SUM_FILE=$OPTARG
      ;;
    t )
      TM_IN+=($OPTARG)
      ;;
    v )
      VERBOSE=$((VERBOSE+1))
      ;;
    h )
      echo "$0 run tcpdump client server"
      echo "Usage: $0 [ -v ] "
      echo "   -d out_dir (dir with files to be read)"
      echo "   -f output_file "
      echo "   -p proc_stat files. do like -p proc_stat_0.txt -p proc_stat_1.txt where the 1st file is the beg proc_stat file and the 2nd is the end proc_stat file"
      echo "   -s summary_file  "
      echo "   -t tm_x.txt files. do like -t tm_0.txt -t tm_1.txt where the 1st -t file is the beg time and the 2nd is the end time"
      echo "   -v flag verbose mode"
      echo "   -h this info"
      exit 1
      ;;
    : )
      echo "$0 Invalid option: $OPTARG requires an argument. cmdline= ${@}" 1>&2
      exit 1
      ;;
    \? )
      echo "$0 Invalid option: $OPTARG, cmdline= ${@} " 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))
 

if [ "$ODIR_IN" != "" ]; then
  ODIR=$ODIR_IN
else
  ODIR=$1
fi
if [[ "$ODIR" == "" ]] || [[ ! -d $ODIR ]]; then
  echo "$0.$LINENO didn't find input dir -d $ODIR"
  exit 1
fi
OFILE=$ODIR/proc_stat.txt

if [[ "$ODIR" != "" ]] && [[ -d $ODIR ]]; then
  if [ "${#PSTAT_IN[@]}" == "2" ]; then
    FL0=${PSTAT_IN[0]}
    FL1=${PSTAT_IN[1]}
  else
    FL0=$ODIR/proc_stat_0.txt
    FL1=$ODIR/proc_stat_1.txt
  fi
  if [ "${#TM_IN[@]}" == "2" ]; then
    TM0=$(cat ${TM_IN[0]})
    TM1=$(cat ${TM_IN[1]})
  else
    TM0=$(cat $ODIR/tm_0.txt)
    TM1=$(cat $ODIR/tm_1.txt)
  fi
  if [ -e $ODIR/lscpu.txt ]; then
    cpus=$(awk '/^CPU.s.: /{printf("%s\n", $2);exit(0);}' $ODIR/lscpu.txt)
    ck_last_rc $? $LINENO
  fi
else
  echo "$0.$LINENO arg1 must dir with proc_stat_0.txt proc_stat_1.txt tm_0.txt tm_1.txt"
  exit 1
fi
if [[ "$FL0" == "" ]] || [[ "$FL1" == "" ]] || [[ ! -e $FL0 ]] || [[ ! -e $FL1 ]]; then
  echo "$0.$LINENO arg1= $FL0 and arg2= $FL1 but didn't find arg1 or arg2"
  exit 1
fi
if [ "$cpus" == "" ]; then
  if [ -e $ODIR/num_cpus.txt ]; then
    cpus=$(cat $ODIR/num_cpus.txt)
  else
    cpus=$(grep -c processor /proc/cpuinfo)
  fi
fi

SOFTIRQ_FILE=/proc/softirqs
if [ -e "$ODIR/proc_softirqs_0.txt" ]; then
  SOFTIRQ_FILE="$ODIR/proc_softirqs_0.txt"
fi
SFT_IRQS=($(awk '{if (NR == 1) {next}; v = substr($1,1, length($1)-1); printf("%s\n", v);}' $SOFTIRQ_FILE))
    ck_last_rc $? $LINENO
echo "$0.$LINENO softirqs: num= ${#SFT_IRQS[@]} ${SFT_IRQS[@]}"
net_rx=
net_tx=
sep=
SFT_STR=
for ((i=0; i < ${#SFT_IRQS[@]}; i++)); do
  if [ "${SFT_IRQS[$i]}" == "NET_RX" ]; then
    net_rx=$i
    SFT_STR="${SFT_STR}${SEP}$i"
    SEP=","
  fi
  if [ "${SFT_IRQS[$i]}" == "NET_TX" ]; then
    net_tx=$i
    SFT_STR="${SFT_STR}${SEP}$i"
    SEP=","
  fi
done


ILST={}
SMP_FILE=$ODIR/smp_affinity_list_eth0.txt
if [ -e $SMP_FILE ]; then
  SV_IFS=$IFS
  IFS=$'\n'
  ARR=($(cat $SMP_FILE))
  IFS="$SV_IFS"
  SEP=
  ISTR=
  #echo "$0.$LINENO ARR= ${ARR[@]}"
  for ((i=0; i < ${#ARR[@]}; i++)); do
    str=${ARR[$i]}
    str_arr=(${str// / })
    ISTR="${ISTR}${SEP}${str_arr[0]}"
    SEP=" "
  done
fi
  
#echo "$0.$LINENO irq_int_str= $ISTR"

$AWK_BIN -v sft_str="$SFT_STR"  -v irq_int_str="$ISTR" -v ofile="$OFILE" -v cpus="$cpus" -v tm0="$TM0" -v tm1="$TM1" '
  BEGIN{
    n_irq = split(irq_int_str, irq_arr, " ");
    n_sft = split(sft_str, sft_arr, ",");
  }
  /^cpu / {
   #printf("argind= %d\n", ARGIND);
   f = ARGIND;
   user[f] = 0.01 * $2;
   nice[f] = 0.01 * $3;
   sys[f]  = 0.01 * $4;
   idle[f] = 0.01 * $5;
   iowt[f] = 0.01 * $6;
   irq[f]  = 0.01 * $7;
   soft[f] = 0.01 * $8;
   next;
  }
  /^ctxt /{
    ctxt[f] = $2+0.0;
  }
  /^softirq /{
    if (n_sft > 0) {
      for (i=1; i <= n_sft; i++) {
        net_softirqs[f] += $(sft_arr[i]+3)+0;
      }
    }
  }
  /^intr /{
    intr[f] = $2+0.0;
    net_irq_sum[f] = 0;
    if (n_irq > 0) {
      for (i=1; i <= n_irq; i++) {
        v = $(irq_arr[i]+3);
        net_irq_sum[f] += v;
        #printf("irq[%d,%d]= %.0f v= %s\n", f, irq_arr[i], net_irq_sum[f], v);
      }
    }
  }
  END{
    tdff = (tm1 - tm0);
    #v = 100.0/cpus;
    v = 100.0;
    u = v*(user[2] - user[1])/tdff
    n = v*(nice[2] - nice[1])/tdff;
    s = v*( sys[2] -  sys[1])/tdff;
    id= v*(idle[2] - idle[1])/tdff;
    io= v*( iow[2] -  iow[1])/tdff;
    ir= v*( irq[2] -  irq[1])/tdff;
    so= v*(soft[2] - soft[1])/tdff;
    tot_v = u+n+s+id+io+ir+so;
    fctr = cpus * 100.0/tot_v; # total doesnt sum up to exactly num_cpu (usually)
   # ;tot_%cpu;%usr;%sys;%irq;%soft;
    printf("usr= %.2f nice= %.2f sys= %.2f idle= %.2f iow= %.2f irq= %.2f soft= %.2f tot= %.2f tot_busy= %.2f elap_secs= %.2f tot_busy_no_fctr= %.2f\n",
    fctr*u, fctr*n, fctr*s, fctr*id, fctr*io, fctr*ir, fctr*so, fctr*tot_v, fctr*(tot_v - id), tdff, tot_v-id);
    printf("_hdr_mpstat;tot_%%cpu;%%usr;%%sys;%%irq;%%soft;file\n") > ofile;
    printf("_det_mpstat;%.2f;%.2f;%.2f;%.2f;%.2f;%s\n", fctr*(u+n+s+io+ir+so), fctr*u, fctr*s, fctr*ir, fctr*so, ofile) > ofile;
    printf("tot_int_rateK/s= %.5f\n", (intr[2] - intr[1])/tdff) > ofile;
    printf("proc_stat_tot_int_rateK/s= %.5f\n", 0.001*(intr[2] - intr[1])/tdff);
    printf("proc_stat_tot_int_net_rateK/s= %.5f\n", 0.001*(net_irq_sum[2] - net_irq_sum[1])/tdff);
    printf("proc_stat_tot_net_softirqs_rateK/s= %.5f\n", 0.001*(net_softirqs[2] - net_softirqs[1])/tdff);
    printf("proc_stat_tot_context_switch_K/s= %.5f\n", 0.001*(ctxt[2] - ctxt[1])/tdff);
    close(ofile);
    #printf("tot_busy= %.2f usr= %.2f sys= %.2f irq= %.2f soft= %.2f, elap_secs= %.2f\n",
    #u+n+s_io+ir+so, u, s, ir, so, tdff);
  }' $FL0 $FL1
    ck_last_rc $? $LINENO
cat $OFILE

exit

user   (1) Time spent in user mode.
nice   (2) Time spent in user mode with low priority (nice).
system (3) Time spent in system mode.
idle   (4) Time spent in the idle task.  This value should be USER_HZ times the second entry in the /proc/uptime pseudo-file.
iowait (since Linux 2.5.41) (5) Time waiting for I/O to complete.  This value is not reliable, for the following reasons:
       1. The CPU will not wait for I/O to complete; iowait is the time that a task is waiting for I/O to complete.  When a
          CPU goes into idle state for outstanding task I/O, another task will be scheduled on this CPU.
       2. On a multi-core CPU, the task waiting for I/O to complete is not running on any CPU, so the iowait of each CPU is difficult to calculate.
       3. The value in this field may decrease in certain conditions.
irq (since Linux 2.6.0) (6) Time servicing interrupts.
softirq (since Linux 2.6.0)

