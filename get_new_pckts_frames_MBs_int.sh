#!/bin/bash

SCR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export LC_ALL=C
GOT_QUIT=0
# function called by trap
catch_signal() {
    printf "\rSIGINT caught      "
    GOT_QUIT=1
}
trap 'catch_signal' SIGINT

ck_last_rc() {
   local RC=$1
   local FROM=$2
   if [ $RC -gt 0 ]; then
      echo "$0: got non-zero RC=$RC at $LINENO. called from line $FROM" > /dev/stderr
      exit $RC
   fi
}

EXTRA=0
INTRVL=0
NET_DEV=eth0

#ODIR=$1
while getopts "hvxa:C:d:f:i:N:s:S:t:w:" opt; do
  case ${opt} in
    a )
      ACT=$OPTARG
      ;;
    C )
      CLNT=$OPTARG
      ;;
    d )
      ODIR_IN=$OPTARG
      ;;
    f )
      OUTFILE=$OPTARG
      ;;
    i )
      INTRVL=$OPTARG
      ;;
    N )
      NET_DEV=$OPTARG
      ;;
    s )
      SUM_FILE=$OPTARG
      ;;
    S )
      SRVR=$OPTARG
      ;;
    t )
      TM_RUN=$OPTARG
      ;;
    w )
      WORK_DIR=$OPTARG
      ;;
    x )
      EXTRA=$((EXTRA+1))
      ;;
    v )
      VERBOSE=$((VERBOSE+1))
      ;;
    h )
      echo "$0 run tcpdump client server"
      echo "Usage: $0 [ -v ] "
      echo "   -a action must be get (collect data) or read (post process data collection)"
      echo "   -d out_dir"
      echo "   -f output_file  assumes '-a read'"
      echo "   -i interval_in_secconds_to_collect_stats   if missing or 0 then only collect stats at begin and end"
      echo "   -s summary_file  "
      echo "   -t time_to_run_in_secs this usually doesn't need to be as long as the full test run (maybe 5-10 secs of data). 1st dat file is usually not yet peak bw. def = 20"
      echo "   -x flag collect extra stats (just 'perf stat' currently)"
      echo "   -w work_dir  for tmp output files"
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
 
if [ "$ODIR_IN" == "" ]; then
  echo "$0.$LINENO arg1 should be output dir"
  exit 1
fi
ODIR=$ODIR_IN
ODIR=$(echo $ODIR | sed 's!/$!!')
if [[ -f $ODIR ]]; then
  ODIR=$(dirname $ODIR)
fi
#CK_NM=$(basename $ODIR)
#if [[ "$CK_NM" != "get_new_pckts_frames_MBs_int" ]]; then
#  ODIR=$ODIR/get_new_pckts_frames_MBs_int
#fi

if [ "$OUTFILE" != "" ]; then
  ACT="read"
fi
if [ ! -d "$ODIR" ]; then
  if [ "$ACT" == "get" ]; then
    mkdir -p $ODIR
  else
    echo "$0.$LINENO got -a read but didn't find dir= -d $ODIR_IN got odir= $ODIR"
    exit 1
  fi
fi
echo "$0.$LINENO got to top of script" >> $ODIR/trace_cmds.txt
#ACT=$2 # get or read
if [[ "$ACT" != "get" ]] && [[ "$ACT" != "read" ]]; then
  echo "$0.$LINENO -a arg should be get (collect data) or read (post process already collected data). got -a \"$ACT\""
  exit 1
fi
if [ "$OUTFILE" != "" ]; then
  ACT="read"
fi
TM_RUN_FILE=$ODIR/tm_run.txt
if [[ "$ACT" == "read" ]]; then
  if [[ ! -e $TM_RUN_FILE ]]; then
    if [[ -e $ODIR/tm_0.txt ]] && [[ -e $ODIR/tm_1.txt ]]; then
      echo "$0.$LINENO didnt find $TM_RUN_FILE but have tm_0.txt and tm_1.txt"
    else
      echo "$0.$LINENO cant find $TM_RUN_FILE  bye"
      exit 1
    fi
  else
    TM_RUN=$(cat $TM_RUN_FILE)
  fi
  if [[ -e "$ODIR/tm_0.txt" ]] && [[ -e "$ODIR/tm_1.txt" ]]; then
    TM_0=$(cat $ODIR/tm_0.txt)
    TM_1=$(cat $ODIR/tm_1.txt)
    TM_RUN2=$(awk -v tm0="$TM_0" -v tm1="$TM_1" 'BEGIN{ printf("%.3f", (tm1 - tm0)); exit(0);}')
    ck_last_rc $? $LINENO
    if [ "$TM_RUN" == "" ]; then
      TM_RUN="$TM_RUN2"
    fi
  fi
  echo "$0.$LINENO tm0= $TM_0 tm1= $TM_1 tm_run= $TM_RUN, tm_x_diff= $TM_RUN2"
fi
 
if [ "$TM_RUN" == "" ]; then
  echo "$0.$LINENO missing -t arg. bye"
  exit 1
fi

if [[ "$ACT" == "get" ]]; then
  echo $TM_RUN > $TM_RUN_FILE
fi

if [ ! -e $ODIR/net_irqs.txt ]; then
  NET_IRQS=($(ls -1 /sys/class/net/$NET_DEV/device/msi_irqs/ | sort -nk 1 ))
  echo "${NET_IRQS[@]}" > $ODIR/net_irqs.txt
else
  NET_IRQS=($(cat $ODIR/net_irqs.txt))
fi
if [ ! -e $ODIR/num_cpus.txt ]; then
  NUM_CPUS=$(grep -c processor /proc/cpuinfo)
  echo "$NUM_CPUS" > $ODIR/num_cpus.txt
else
  NUM_CPUS=$(cat $ODIR/num_cpus.txt)
fi

AWK=awk
SLP=$TM_RUN

if [ "$ACT" == "get" ]; then
  echo "$0.$LINENO doing act= $ACT"
  if [ -d $SCR_DIR/60secs ]; then
    MY60DIR=$SCR_DIR/60secs
  else
    MY60DIR=$SCR_DIR/../60secs
  fi
  if [ -d $SCR_DIR/patrick_fay_bin ]; then
    MYBIN=$SCR_DIR/patrick_fay_bin
  else
    MYBIN=$SCR_DIR/../patrick_fay_bin
  fi
  PRF_BIN=$MYBIN/perf
  AWK_BIN=$MYBIN/gawk
  PF_SLP=$MY60DIR/pfay1_sleep.sh

    lscpu > $ODIR/lscpu.txt
    $SCR_DIR/mk_irq_smp_affinity.sh $ODIR $NET_DEV
    (lspci |grep Ethernet;echo ethtool -l; sudo ethtool -l $NET_DEV; echo ethtool -c; sudo ethtool -c $NET_DEV; echo ethtool -g; sudo ethtool -g $NET_DEV;) > $ODIR/ethtool.txt
    sudo ethtool -i $NET_DEV > $ODIR/ethtool_i.txt

  USE_DEV=$NET_DEV
  if [[ "$SRVR" == "127.0.0."* ]] || [[ "$CLNT" == "127.0.0."* ]]; then
    USE_DEV="lo"
  fi
  LST_FLS=$(ls -1 /sys/class/net/$USE_DEV/statistics/)
  ETH_STATS=$ODIR/eth0_statistics_0.txt
  : > $ETH_STATS
  for j in $LST_FLS; do
     v=$(sudo cat /sys/class/net/$USE_DEV/statistics/$j)
     echo "$v $j" >> $ETH_STATS
  done
  cat /proc/softirqs > $ODIR/proc_softirqs_0.txt
  cat /proc/net/softnet_stat > $ODIR/softnet_stat_0.txt
  cat /proc/interrupts > $ODIR/proc_interrupts_0.txt
  sudo ethtool -S $NET_DEV > $ODIR/ethtool_S_0.txt
  netstat -s > $ODIR/netstat_s_0.txt
  cat /proc/stat > $ODIR/proc_stat_0.txt


  if [ "$EXTRA" != "0" ]; then
    echo "sudo nohup $PRF_BIN stat -e cpu-clock,duration_time,msr/aperf/,msr/mperf/,msr/tsc/ -a -o $ODIR/perf_stat_all.txt -I 1000  -- sleep $SLP  > $ODIR/perf_stat_all_stdout.txt 2> $ODIR/perf_stat_all_stderr.txt &"
    sudo nohup $PRF_BIN stat -e cpu-clock,duration_time,msr/aperf/,msr/mperf/,msr/tsc/ -a -o $ODIR/perf_stat_all.txt -I 1000  -- sleep $SLP  > $ODIR/perf_stat_all_stdout.txt 2> $ODIR/perf_stat_all_stderr.txt &
    PRF_ALL_PID=$!
    TM_PRF_BEG=$(date +"%s.%N")
    echo "$0.$LINENO abs_ts start perf_stat tm= $TM_PRF_BEG"
  fi
    
  TM_BEG=$(date +"%s.%N")
  #if [ ! -e $ODIR/tm_0.txt ]; then
    echo "$TM_BEG" > $ODIR/tm_0.txt
  #fi
  ts_beg=$(date +"%s")
  ts_end=$((ts_beg+SLP))
  
  if [ "$INTRVL" == "0" ]; then
    $PF_SLP $SLP
    TM_END=$(date +"%s.%N")
  else
    OFILE=$ODIR/interval_stats.txt
    ts_cur=$(date +"%s")
    echo "__tm_beg__ $TM_BEG $ts_cur $ts_end $INTRVL" > $OFILE
    while [ "$GOT_QUIT" == "0" ]; do
      ts_cur=$(date +"%s")
      echo "__date__ $ts_cur $ts_end" >> $OFILE
      echo ""                     >> $OFILE
      echo "__eth0_statistics__" >> $OFILE
      for j in $LST_FLS; do
        v=$(cat /sys/class/net/$NET_DEV/statistics/$j)
        echo "$v $j" >> $OFILE
      done
      echo ""                     >> $OFILE
      echo "__proc_softirqs__"    >> $OFILE
      cat /proc/softirqs          >> $OFILE
      echo ""                     >> $OFILE
      echo "__softnet_stats__"    >> $OFILE
      cat /proc/net/softnet_stat  >> $OFILE
      echo ""                     >> $OFILE
      echo "__proc_interrupts__"  >> $OFILE
      cat /proc/interrupts | grep -E "CPU0|mlx|$NET_DEV" >> $OFILE
      echo ""                     >> $OFILE
      echo "__ethtool_S__"        >> $OFILE
      sudo ethtool -S $NET_DEV        >> $OFILE
      echo ""                     >> $OFILE
      echo "__netstat_s__"        >> $OFILE
      netstat -s                  >> $OFILE
      echo ""                     >> $OFILE
      echo "__proc_stat__"        >> $OFILE
      cat /proc/stat              >> $OFILE
      echo ""                     >> $OFILE
      #sleep $INTRVL
      #echo $0.$LINENO $PF_SLP $INTRVL
      $PF_SLP $INTRVL
      if [[ "$GOT_QUIT" == "1" ]]; then
        echo "__end__ $0.$LINENO end loop due to got_quit=1 ts_cur= $ts_cur ts_end= $ts_end. bye" 
        echo "__end__ $0.$LINENO end loop due to got_quit=1 ts_cur= $ts_cur ts_end= $ts_end. bye" >> $OFILE
        break
      fi
      if [[ $ts_cur -ge $ts_end ]]; then
        echo "__end__ $0.$LINENO end loop due to time exceeded ts_cur= $ts_cur ts_end= $ts_end. bye" 
        echo "__end__ $0.$LINENO end loop due to time exceeded ts_cur= $ts_cur ts_end= $ts_end. bye" >> $OFILE
        break
      fi
    done
    #TM_END=$(date +"%s.%N")
    if [ -e "$ODIR/tm_1.txt" ]; then
      TM_END=$(cat $ODIR/tm_1.txt)
    else
      TM_END=$(awk -v tm0="$TM_BEG" -v dur="$SLP" 'BEGIN{printf("%.6f", tm0+dur);exit(0);}')
      ck_last_rc $? $LINENO
    fi
    echo "__tm_end__ $TM_END $ts_cur $ts_end" >> $OFILE
  fi
  
  if [ ! -e $ODIR/tm_1.txt ]; then
    echo "$TM_END" > $ODIR/tm_1.txt
  fi
  if [ "$PRF_ALL_PID" != "" ]; then
     #echo "$0.$LINENO pkill $PF_SLP"
     #ps -ef|grep perf
     #pgrep -lP $PRF_ALL_PID
     SLP_PID=$(pgrep -lP $PRF_ALL_PID | awk '/sleep/{print $1}')
     #pgrep  -f $PF_SLP
     if [ "$SLP_PID" != "" ]; then
       kill -2 $SLP_PID
     fi
  fi
    if [ ! -e $ODIR/proc_stat_1.txt ]; then
    cat /proc/stat > $ODIR/proc_stat_1.txt
    fi
  ETH_STATS=$ODIR/eth0_statistics_1.txt
  : > $ETH_STATS
  for j in $LST_FLS; do
     v=$(cat /sys/class/net/$USE_DEV/statistics/$j)
     echo "$v $j" >> $ETH_STATS
  done
  cat /proc/interrupts > $ODIR/proc_interrupts_1.txt
  cat /proc/softirqs > $ODIR/proc_softirqs_1.txt
  cat /proc/net/softnet_stat > $ODIR/softnet_stat_1.txt
  sudo ethtool -S $NET_DEV > $ODIR/ethtool_S_1.txt
  netstat -s > $ODIR/netstat_s_1.txt
  #if [ "$EXTRA" != "0" ]; then
    #if [ ! -e $ODIR/proc_stat_1.txt ]; then
    #cat /proc/stat > $ODIR/proc_stat_1.txt
    #fi
  #fi
  echo "$0.$LINENO wait for background tasks"
  jobs
  wait
fi

#NUM_CPUS=$(grep -c processor /proc/cpuinfo)
IRQ_STR="${NET_IRQS[@]}"

if [ "$ACT" == "get" ]; then
  exit 0
fi

if [ "$ACT" == "read" ]; then
  echo "$0.$LINENO doing act= $ACT odir= $ODIR"
  echo "$0.$LINENO $AWK -v tm="$TM_RUN" -v net_int=${IRQ_STR}" 
  if [ 1 == 2 ]; then
  $AWK -v num_cpus="$NUM_CPUS" -v tm="$TM_RUN" -v net_int="${IRQ_STR}" '
    BEGIN{
      n = split(net_int, net_arr, " ");
      for (i=1; i <= n; i++) {
        int_list[net_arr[i]] = i;
        int_lkup[i] = net_arr[i];
      }
      printf("n interrupts= %d\n", n);
    }
    /^Average:/ { 
      for(i=1; i <= n; i++) {
        if ($2 == int_lkup[i]) {
          net_irqs += $3;
          #printf("intr %s val= %s\n", $2, $3);
          break;
        }
      }
    }
    END{
      printf("tot_net_irqs/s= %.3f net_irqsK/s= %.3f\n", net_irqs, 0.001*net_irqs); 
    }
  ' $ODIR/intr.txt
    ck_last_rc $? $LINENO
  fi
  #echo $0.$LINENO $AWK -v tm="$TM_RUN" -v num_cpus="$NUM_CPUS" -v net_int="${IRQ_STR}" 
  $AWK -v tm="$TM_RUN" -v num_cpus="$NUM_CPUS" -v net_int="${IRQ_STR}" '
    BEGIN{
      n = split(net_int, net_arr, " ");
      for (i=1; i <= n; i++) {
        int_list[net_arr[i]":"] = i;
        int_lkup[i] = net_arr[i]":";
        #printf("int[%d]= %s\n", i, int_lkup[i]);
      }
      #printf("irq_n= %d\n", n);
    }
    {
      if (FILENAME != fl_prev) {
        fl++;
        fl_prev = FILENAME;
      }
      if (!($1 in int_list)) {next;}
      for(i=1; i <= n; i++) {
        #printf("ck in int= %s lkup[%d]= %s\n", $1, i, int_lkup[i]);
        if ($1 == int_lkup[i]) { 
          #printf("ok in int= %s lkup[%d]= %s\n", $1, i, int_lkup[i]);
          for (j=2; j <= (num_cpus+1); j++) {
            #if ($j != "0"){
            #  printf("intr %s fl= %d line= %d v[%d]= %s\n", $1, fl, FNR, j, $j);
            #}
            sum[fl] += $j;
          }
          break;
        }
      }
    }
    END{
      dff = sum[2] - sum[1];
      printf("proc_tot_net_irqs= %.3f net_irqsK/s= %.3f\n", dff, 0.001*dff/tm); 
    }
  ' $ODIR/proc_interrupts_0.txt $ODIR/proc_interrupts_1.txt
    ck_last_rc $? $LINENO
  $AWK -v metric="softirqsK/s" -v tm="$TM_RUN" '
    /NET_RX:|NET_TX:/ {
      if (FILENAME != fl_prev) {
        fl++;
        fl_prev = FILENAME;
      }
      val = 0;
      #for (i=2; i <= 10; i++) { val += $i; }
      for (i=2; i <= NF; i++) { val += $i; }
      v[fl] += val;
     #printf("argind= %d argc= %s fl= %s v= %s\n", ARGIND, ARGC, fl, $1);
    }
    END{
        printf("%s= %.3f\n", metric, 1e-3*(v[2]-v[1])/tm);
    }
  ' $ODIR/proc_softirqs_0.txt $ODIR/proc_softirqs_1.txt
    ck_last_rc $? $LINENO
  $AWK -v metric="${i}_MBytes/s" -v tm="$TM_RUN" '
    BEGIN{
      str = "rx_bytes tx_bytes rx_packets tx_packets";
      nw  = "rx_MB/s tx_MB/s rx_pktsK/s tx_pktsK/s";
      n  = split(str, arr, " ");
      n2 = split(nw,  arr2, " ");
      for (i=1; i <= n; i++) {
        nm_list[arr[i]] = ++nm_mx;
        nm_lkup[nm_mx] = arr[i];
        nw_list[arr[i]] = nm_mx;
        nw_lkup[nm_mx] = arr2[i];
      }
    }
    {
      if (FILENAME != fl_prev) {
        fl++;
        fl_prev = FILENAME;
      }
    }
    /rx_bytes|tx_bytes|rx_packets|tx_packets/{
      v[fl,$2] = $1;
      if (fl == 2) {
        i = nm_list[$2];
        if (i <= 2) { fctr = 1e-6; } else { fctr = 1e-3; }
        val = fctr*(v[2,$2]-v[1,$2])/tm;
        if (i <= 2) { tot_MBps += val; } else { tot_pktKps += val;}
        printf("%s= %.3f\n", nw_lkup[i], fctr*(v[2,$2]-v[1,$2])/tm);
      }
     #printf("argind= %d argc= %s fl= %s v= %s\n", ARGIND, ARGC, fl, $1);
    }
    END{
        printf("%s= %.3f\n", "tot_MB/s", tot_MBps);
        printf("%s= %.3f\n", "tot_pktsK/s", tot_pktKps);
    }
    #/rx_packets|tx_packets/{
    #  v[fl,$2] = $1;
    #  if (fl == 2) {
    #    printf("%s= %.3f\n", metric, 1e-3*(v[2,$2]-v[1,$2])/tm);
    #  }
    # #printf("argind= %d argc= %s fl= %s v= %s\n", ARGIND, ARGC, fl, $1);
    #}
  ' $ODIR/eth0_statistics_0.txt $ODIR/eth0_statistics_1.txt
    ck_last_rc $? $LINENO
  #$AWK -v metric="${i}_pcktsK/s" -v tm="$TM_RUN" '
  #' $ODIR/eth0_statistics_0.txt $ODIR/eth0_statistics_1.txt
PRF_STAT_ALL=$ODIR/perf_stat_all.txt
if [ -e $PRF_STAT_ALL ]; then
    awk '
    BEGIN{
      col_tm = -1;
      col_num = 1;
      col_unit= 2;
      col_evt = 3;
    }
      
##           time             counts unit events
  /^#.*time.*counts/ {
   has_tm
   for (i=2; i <= NF; i++) {
     if ($i == "time") { col_tm = i-1; }
     if ($i == "counts") { col_num = i-1; }
     if ($i == "units") { col_unit = i-1; }
     if ($i == "events") { col_evt  = i-1; }
   }
   next;
  }
  {
    itm_i = -1;
    if (col_tm != -1) {
      itm = $(col_tm);
      if (!(itm in itm_list)) {
        itm_list[itm] = ++itm_mx;
        itm_lkup[itm_mx] = itm;
      }
      itm_i = itm_list[itm];
    }
  }
  /msr\/aperf\//{
    v=$(col_num);
    gsub(/,/,"",v);
    aperf += v;
    evt[itm_i,"aperf"] += v;
    #printf("mperf= %s\n", mperf);
  }
  /msr\/mperf\//{
    v=$(col_num);
    gsub(/,/,"",v);
    mperf += v;
    evt[itm_i,"mperf"] += v;
    #printf("mperf= %s\n", mperf);
  }
  /duration_time/{
    v=$(col_num);
    gsub(/,/,"",v);
    tm += 1.0e-9*v;
    evt[itm_i,"tm"] += 1.0e-9*v;
    #printf("tm= %s v= %s $0= %s\n", tm, v, $0);
  }/msr\/tsc\//{
    v=$(col_num);
    gsub(/,/,"",v);
    tsc += v
    evt[itm_i,"tsc"] += v;
    #printf("tsc= %s\n", tsc);
  }
  /cpu-clock/{
    v=$(col_num);
    gsub(/,/,"",v);
    cpu_secs += 0.001*v
    evt[itm_i,"cpu_secs"] += 0.001*v;
  }
  END{
    ncpus = cpu_secs/tm;
    tsc_freq = tsc/tm/ncpus;
    busy = 100*mperf/tsc;
    cpus_busy= ncpus * busy;
    avg_freq = 1.0e-9 * tsc_freq * aperf / mperf;
    printf("below is from file %s\n", ARGV[1]);
    # see https://tanelpoder.com/posts/linux-hiding-interrupt-cpu-usage/ for diff between perf cpus_busyTL and proc stat alt_busyTL
    printf("perf_stat_all tsc_freq= %.3f %%host_unhalted= %.3f cpus_busyTL= %.3f avg_freq= %.3f ncpus= %.3f duration_secs= %.3f\n",
      1.0e-9*tsc_freq, busy, cpus_busy, avg_freq, ncpus, tm);
    for (i=1; i <= itm_mx; i++) {
      cpu_secs = evt[i,"cpu_secs"];
      tm       = evt[i,"tm"];
      tsc      = evt[i,"tsc"];
      mperf    = evt[i,"mperf"];
      aperf    = evt[i,"aperf"];
      ncpus = cpu_secs/tm;
      tsc_freq = tsc/tm/ncpus;
      busy = 100*mperf/tsc;
      cpus_busy= ncpus * busy;
      avg_freq = 1.0e-9 * tsc_freq * aperf / mperf;
      printf("perf_stat[%s] tsc_freq= %.3f %%host_unhalted= %.3f cpus_busyTL= %.3f avg_freq= %.3f ncpus= %.3f duration_secs= %.3f\n", i,
      1.0e-9*tsc_freq, busy, cpus_busy, avg_freq, ncpus, tm);
    }
  }' $PRF_STAT_ALL
fi

  if [[ -e $ODIR/proc_stat_0.txt ]] && [[ -e $ODIR/proc_stat_1.txt ]]; then
    CS0=$(grep '^ctxt ' $ODIR/proc_stat_0.txt | sed 's/ctxt //')
    CS1=$(grep '^ctxt ' $ODIR/proc_stat_1.txt | sed 's/ctxt //')
    CSTOT=$(( CS1 - CS0 ))
    awk -v cs_tot="$CSTOT" -v tm="$TM_RUN" 'BEGIN{ v = 0; if (tm > 0) { v = 1e-3*cs_tot/tm; }; printf("tot_cswitch (K/s)= %.3f\n", v); exit(0);}'
    ck_last_rc $? $LINENO
    awk -v num_cpus="$NUM_CPUS" -v tm="$TM_RUN" '
      /^cpu /{
#                     user   (1) Time spent in user mode.
#                     nice   (2) Time spent in user mode with low priority (nice).
#                     system (3) Time spent in system mode.
#                     idle   (4) Time spent in the idle task.  This value should be USER_HZ times the second entry in the /proc/uptime pseudo-file.
#                     iowait (since Linux 2.5.41) (5) Time waiting for I/O to complete.  This value is not reliable, for the following reasons:
#                     irq (since Linux 2.6.0-test4) (6) Time servicing interrupts.
#                     softirq (since Linux 2.6.0-test4) (7) Time servicing softirqs.
        v[ARGIND]   += $5;
        alt[ARGIND] += $2+$4+$7+$8; # user + system + irq + softirq
        tot[ARGIND] += $2+$3+$4+$5+$6+$7+$8; # user + nice+ system + idle + iowait + irq + softirq
        us[ARGIND] += $2+$4;
      }
      /^intr / {
        tot_intr[ARGIND] = $2;
      }
      END{
        x=0;
        b=0;
        if (tm > 0) {
          x = (v[2]-v[1])/tm;
          b = 100*num_cpus - x;
          tot_diff = (tot[2]-tot[1])/tm;
          fctr = num_cpus * 100.0/tot_diff; # total doesnt sum up to exactly num_cpu (usually)
          y = (alt[2]-alt[1])/tm;
          z = (us[2]-us[1])/tm;
          tot_intr_kps = 0.001*(tot_intr[2]-tot_intr[1])/tm;
          #yb = 100*num_cpus - y;
        }
        printf("%%idleTL= %.3f %%busyTL= %.3f %%alt_busyTL= %.3f %%usr_sysTL= %.3f tm= %.3f num_cpus= %d tot_intr_Kps= %.3f fctr= %.3f\n",
          x*fctr, b, y*fctr, z*fctr, tm, num_cpus, tot_intr_kps, fctr);
        exit(0);
      }' $ODIR/proc_stat_*.txt
    ck_last_rc $? $LINENO
    echo "$0.$LINENO did awk -v num_cpus=$NUM_CPUS -v tm=$TM_RUN 'process proc_stat data' $ODIR/proc_stat_*.txt"
  fi
  
  if [[ -e $ODIR/netstat_s_0.txt ]] && [[ -e $ODIR/netstat_s_1.txt ]]; then
   awk -v tm="$TM_RUN" '
    BEGIN{
    str = "delayed acks sent";
    nets_list[str] = ++nets_mx;
    nets_lkup[nets_mx] = str;
    nets_pos[nets_mx] = 1;
    nets_fctr[nets_mx] = 1;
    nets_hdrs[nets_mx] = "DelAck/s";

    str = "delayed acks further delayed";
    nets_list[str] = ++nets_mx;
    nets_lkup[nets_mx] = str;
    nets_pos[nets_mx] = 1;
    nets_fctr[nets_mx] = 1;
    nets_hdrs[nets_mx] = "extDelAck/s";

    str = "Quick ack mode was activated";
    nets_list[str] = ++nets_mx;
    nets_lkup[nets_mx] = str;
    nets_pos[nets_mx] = 6;
    nets_fctr[nets_mx] = 1;
    nets_hdrs[nets_mx] = "QuickAckActivated/s";

    str = "TCPAutoCorking";
    nets_list[str] = ++nets_mx;
    nets_lkup[nets_mx] = str;
    nets_pos[nets_mx] = 2;
    nets_fctr[nets_mx] = 1;
    nets_hdrs[nets_mx] = "AutoCorking/s";
   }
   {
      for (i=1; i <= nets_mx; i++) {
        if (index($0, nets_lkup[i]) == 0) { continue; }
        v = $(nets_pos[i]) + 0;
        sv_nets[ARGIND, i] = v;
      }
   }
   END{
     for (i=1; i <= nets_mx; i++) {
       v  = 0;
       if (tm > 0) {
         v = (sv_nets[2, i] - sv_nets[1, i])/tm;
       }
       printf("%s %.3f\n", nets_hdrs[i], v);
     }
   }' $ODIR/netstat_s_*.txt
  fi
  if [[ "$TM_BEG" == "" ]] && [[ -e "$ODIR/tm_0.txt" ]]; then
    TM_BEG=$(cat "$ODIR/tm_0.txt")
  fi
  if [[ "$TM_END" == "" ]] && [[ -e "$ODIR/tm_1.txt" ]]; then
    TM_END=$(cat "$ODIR/tm_1.txt")
  fi
  printf "tm_beg= %.4f\n" $TM_BEG
  printf "tm_end= %.4f\n" $TM_END
  printf "tm_end-tm_beg= %.4f\n" $(awk -v tm1="$TM_END" -v tm0="$TM_BEG" 'BEGIN{printf("%.6f", tm1-tm0);exit(0);}')
  printf "tm_run= %.4f\n" $TM_RUN
  $AWK -v tm="$TM_RUN" -f $SCR_DIR/ethtool_S_diff.awk $ODIR/ethtool_S_0.txt $ODIR/ethtool_S_1.txt
  ck_last_rc $? $LINENO
  $AWK -v metric="ethtool_S MB/s" -v tm="$TM_RUN" '
    /rx_bytes:|tx_bytes:/{
      if (FILENAME != fl_prev) {
        fl++;
        fl_prev = FILENAME;
      }
      v[fl] += $2;
     #printf("argind= %d argc= %s fl= %s v= %s\n", ARGIND, ARGC, fl, $1);
    }
    END{
        ck = 1e-6*(v[2]-v[1])/tm;
        if (ck < 0.0) { ck = 0.0;}
        printf("%s= %.3f\n", metric, ck);
    }
  ' $ODIR/ethtool_S_0.txt $ODIR/ethtool_S_1.txt
    ck_last_rc $? $LINENO
    
if [ "$OUTFILE" == "" ]; then
  echo "$0.$LINENO option '-f outfile' not specified. Using tmp.txt as outfile"
  OUTFILE="tmp.txt"
fi
if [[ "$WORK_DIR" == "" ]]; then
  WORK_DIR="./work_dir"
fi
if [[ ! -d "$WORK_DIR" ]]; then
  mkdir -p "$WORK_DIR"
fi
echo "$0.$LINENO work_dir= $WORK_DIR"
  if [ -e $ODIR/interval_stats.txt ]; then
  $AWK -v sum_file="$SUM_FILE" -v ofile="$OUTFILE" -v idir="$ODIR" -v work_dir="$WORK_DIR" -v scr_dir="$SCR_DIR" '
  BEGIN{
    n = split("multicast    rx_bytes       rx_packets tx_bytes tx_packets", arr);
    nf = split("1           1.0e-6         1.0e-3     1.0e-6   1.0e-3s",    farr);
    nh = split("multicast/s rx_bytes(MB/s) rx_packets(K/s) tx_bytes(MB/s) tx_packets(K/s)", harr);
    for (i=1; i <= n; i++) {
      est_list[arr[i]] = ++est_mx;
      est_lkup[est_mx] = arr[i];
      est_fctr[est_mx] = farr[i]+0;
      est_hdrs[est_mx] = harr[i];
    }
    str = "delayed acks sent";
    nets_list[str] = ++nets_mx;
    nets_lkup[nets_mx] = str;
    nets_pos[nets_mx] = 1;
    nets_fctr[nets_mx] = 1;
    nets_hdrs[nets_mx] = "DelAck/s";

    str = "delayed acks further delayed";
    nets_list[str] = ++nets_mx;
    nets_lkup[nets_mx] = str;
    nets_pos[nets_mx] = 1;
    nets_fctr[nets_mx] = 1;
    nets_hdrs[nets_mx] = "extDelAck/s";

    str = "Quick ack mode was activated";
    nets_list[str] = ++nets_mx;
    nets_lkup[nets_mx] = str;
    nets_pos[nets_mx] = 6;
    nets_fctr[nets_mx] = 1;
    nets_hdrs[nets_mx] = "QuickAckActivated/s";

    str = "TCPAutoCorking";
    nets_list[str] = ++nets_mx;
    nets_lkup[nets_mx] = str;
    nets_pos[nets_mx] = 2;
    nets_fctr[nets_mx] = 1;
    nets_hdrs[nets_mx] = "AutoCorking/s";

        px_mx = 0;
        px[++px_mx] = 10;
        px[++px_mx] = 20;
        px[++px_mx] = 30;
        px[++px_mx] = 40;
        px[++px_mx] = 50;
        px[++px_mx] = 60;
        px[++px_mx] = 70;
        px[++px_mx] = 80;
        px[++px_mx] = 90;
        px[++px_mx] = 95;
        px[++px_mx] = 99;
        px[++px_mx] = 99.5;
        px[++px_mx] = 100;
  }
  /^__date__/ {
    dt_mx++;
    dt[dt_mx] = $2+0;
    next;
  }
  /^__eth0_statistics__/ {
    n_est++;
    while((getline) > 0) {
      if ($0 == "" || substr($0, 1, 2) == "__") {
        break;
      }
      nm = $2;
      v  = $1 + 0;
      if (!(nm in est_list)) {
        continue;
      }
      est_i = est_list[nm];
      sv_est[n_est, est_i] = v;
    }
  }
  /^__proc_stat__/ {
    n_ps++;
    ln = 0;
    while((getline) > 0) {
      if ($0 == "" || substr($0, 1, 2) == "__") {
        break;
      }
      ln++;
      ps_ln_mx[n_ps] = ln;
      sv_ps[n_est, ln] = $0;
    }
  }
  /^__netstat_s__/ {
    n_nets++;
    while((getline) > 0) {
      if ($0 == "" || substr($0, 1, 2) == "__") {
        break;
      }
      for (i=1; i <= nets_mx; i++) {
        if (index($0, nets_lkup[i]) == 0) { continue; }
        v = $(nets_pos[i]) + 0;
        sv_nets[n_nets, i] = v;
      }
    }
  }
function compute_pxx(kk, my_n, res_i, arr_in,     pi, pii, piu, uval, piup1) {
    pi  = 0.01 * px[kk] * my_n; # index into array for this percentile
    pii = int(pi);       # integer part
    if (pii != pi) {
      # so pi is not an integer
      piu = pii+1;
      if (piu > my_n) { piu = my_n; }
      uval = arr_in[res_i[piu]]
    } else {
      piu = pii;
      if (piu >= my_n) {
        uval = arr_in[res_i[my_n]];
      } else {
        piup1=piu + 1;
        uval = 0.5*(arr_in[res_i[piu]] + arr_in[res_i[piup1]]);
      }
    }
    return uval;
}
function arr_in_compare(i1, v1, i2, v2,    l, r)
{
    m1 = arr_in[i1];
    m2 = arr_in[i2];
    if (m2 > m1)
        return -1
    else if (m1 == m2)
        return 0
    else
        return 1
}
  END{
    if (ofile == "") {
      ofile="tmp.txt"
    }
    n_ps_hdrs = split("%user %nice %sys %idle %iowait %irq %softirq %tot %busy secs", ps_hdrs, " ");
    n_int_hdrs = split("int_rateK/s int_net_rateK/s int_net_softirqs_rateK/s context_switch_K/s", int_hdrs, " ");
    for (i=2; i <= n_ps; i++) {
      tm0_file=work_dir"/tmp_tm0.txt";
      tm1_file=work_dir"/tmp_tm1.txt";
      ps0_file=work_dir"/tmp_ps0.txt";
      ps1_file=work_dir"/tmp_ps1.txt";
      printf("%f\n", dt[i-1]) > tm0_file;
      printf("%f\n", dt[i])   > tm1_file;
      for (j=1; j <= ps_ln_mx[i-1]; j++) {
        printf("%s\n", sv_ps[i-1,j]) > ps0_file;
      }
      for (j=1; j <= ps_ln_mx[i]; j++) {
        printf("%s\n", sv_ps[i,j]) > ps1_file;
      }
      close(tm0_file);
      close(tm1_file);
      close(ps0_file);
      close(ps1_file);
      cmd = scr_dir"/rd_proc_stat.sh -d " idir " -p " ps0_file " -p " ps1_file " -t " tm0_file " -t " tm1_file;
      #printf("cmd= %s\n", cmd) > "/dev/stderr";
      #printf("i= %d, n_ps= %d, dt[%d]= %s dt[%d]= %s\n", i, n_ps, i-1, dt[i-1],  i, dt[i]) > "/dev/stderr";
#usr= 1711.65 nice= 20.72 sys= 471.34 idle= 7145.37 iow= 0.00 irq= 0.00 soft= 76.97, tot= 9426.05, elap_secs= 300.03
#proc_stat_tot_int_rateK/s= 280.81971
#proc_stat_tot_int_net_rateK/s= 115.22160
#proc_stat_tot_net_softirqs_rateK/s= 153.54985
#proc_stat_tot_context_switch_K/s= 782.16985
      while ((cmd | getline) > 0) {
        #printf("%s\n", $0);
        if ($1 == "usr=") {
           #printf("got usr= line= %s\n", $0);}
           gsub(/,/, "");
           for (k=1; k <= n_ps_hdrs; k++) {
             sv_ps_ext[i,ps_hdrs[k]] = $(k*2);
           }
        }
        if ($1 == "proc_stat_tot_int_rateK/s=") {
           sv_ps_ext[i,int_hdrs[1]] = $2;
        }
        if ($1 == "proc_stat_tot_int_net_rateK/s=") {
           sv_ps_ext[i,int_hdrs[2]] = $2;
        }
        if ($1 == "proc_stat_tot_net_softirqs_rateK/s=") {
           sv_ps_ext[i,int_hdrs[3]] = $2;
        }
        if ($1 == "proc_stat_tot_context_switch_K/s=") {
           sv_ps_ext[i,int_hdrs[4]] = $2;
        }
      }
      #system(cmd);
      close(cmd);
      #if (i > 4) {
      #  exit(1);
      #}
    }
    trow = 0;

    printf("title\t%s\tsheet\t%s\ttype\tscatter_straight\n", "proc_stat %cpuTL util", "eth_stats") > ofile;
    trow++;
    printf("hdrs\t%d\t%d\t%d\t%d\t%d\n", trow+1, 2, -1, 1+n_ps_hdrs-1, 1) > ofile;
    trow++;
    printf("epoch\tts") > ofile
    for(i=1; i <= n_ps_hdrs-1; i++) {
      printf("\t%s", ps_hdrs[i]) > ofile;
      if (ps_hdrs[i] == "%busy") {
        ps_busy_i= i;
      }
    }
    printf("\n") > ofile;
    trow++;
    for(k=2; k <= n_ps; k++) {
      tdff = dt[k]-dt[k-1];
      printf("%.4f\t%d", dt[k], dt[k]-dt[1]) > ofile;
      for(i=1; i <= n_ps_hdrs-1; i++) {
        v = sv_ps_ext[k,ps_hdrs[i]];
        if (v < 0.0) { v = 0.0; }
        printf("\t%.3f", v) > ofile;
        if (i == ps_busy_i && i < n_ps) {
          avg_busy_sum += v;
          avg_busy_n++;
        }
      }
      printf("\n") > ofile;
      trow++;
    }
    trow++;
    printf("\n") > ofile;

    if (sum_file != "") {
    for (i=1; i <= n_ps_hdrs-1; i++) {
      delete arr_in;
      delete idx;
      delete res_i;
      nnstr = "";
      for(k=2; k <= n_ps; k++) {
        idx[k-1] = k;
        arr_in[k-1] = sv_ps_ext[k,ps_hdrs[i]];
        nnstr = nnstr "" sprintf("\t%f", arr_in[k-1]);
      }
      asorti(idx, res_i, "arr_in_compare");
      nstr = sprintf("%s\t%s\t%f\t%s val_arr", "prc_stat_%cpuTl_val_arr", "prc_stat_%cpuTL_val_arr", n_ps-1, ps_hdrs[i]);
      printf("%s%s\n", nstr, nnstr) > sum_file;
      for (kk=1; kk <= px_mx; kk++) {
        uval = compute_pxx(kk, n_ps-1, res_i, arr_in);
        strp = ps_hdrs[i] " p" px[kk];
        printf("%s\t%s\t%f\t%s\n", "prc_stat_%cpuTL_per_hst", "prc_stat_%cpuTL_per_hst", uval, strp) > sum_file;
      }
    }
    }
    printf("title\t%s\tsheet\t%s\ttype\tscatter_straight\n", "interrupts K/s and cswitches K/s", "eth_stats") > ofile;
    trow++;
    printf("hdrs\t%d\t%d\t%d\t%d\t%d\n", trow+1, 2, -1, 1+n_int_hdrs, 1) > ofile;
    trow++;
    printf("epoch\tts") > ofile
    for(i=1; i <= n_int_hdrs; i++) {
      printf("\t%s", int_hdrs[i]) > ofile;
    }
    printf("\n") > ofile;
    trow++;
    for(k=2; k <= n_ps; k++) {
      tdff = dt[k]-dt[k-1];
      printf("%.4f\t%d", dt[k], dt[k]-dt[1]) > ofile;
      for(i=1; i <= n_int_hdrs; i++) {
        v = sv_ps_ext[k,int_hdrs[i]];
        if (v < 0.0) { v = 0.0; }
        printf("\t%.3f", v) > ofile;
      }
      printf("\n") > ofile;
      trow++;
    }
    trow++;
    printf("\n") > ofile;

    printf("title\t%s\tsheet\t%s\ttype\tscatter_straight\n", "eth0_stats/sec", "eth_stats") > ofile;
    trow++;
    printf("hdrs\t%d\t%d\t%d\t%d\t%d\n", trow+1, 2, -1, 1+est_mx, 1) > ofile;
    trow++;
    printf("epoch\tts") > ofile
    for(i=1; i <= est_mx; i++) {
      printf("\t%s", est_hdrs[i]) > ofile;
      if (est_lkup[i] == "rx_bytes") {
        est_rx_i= i;
      }
      if (est_lkup[i] == "tx_bytes") {
        est_tx_i= i;
      }
      if (est_lkup[i] == "rx_packets") {
        est_rx_pkts_i= i;
      }
      if (est_lkup[i] == "tx_packets") {
        est_tx_pkts_i= i;
      }
    }
    printf("\n") > ofile;
    trow++;
    for(k=2; k <= n_est; k++) {
      tdff = dt[k]-dt[k-1];
      printf("%.4f\t%d", dt[k], dt[k]-dt[1]) > ofile;
      for(i=1; i <= est_mx; i++) {
        v = est_fctr[i]*(sv_est[k,i] - sv_est[k-1,i])/tdff;
        printf("\t%.3f", v) > ofile;
        if (k < n_est && (i == est_rx_i || i == est_tx_i)) {
          avg_net_bytes += v;
          avg_net_n++;
        }
        if (k < n_est && (i == est_rx_pkts_i || i == est_tx_pkts_i)) {
          avg_net_pkts += v;
          avg_net_pkts_n++;
        }
      }
      printf("\n") > ofile;
      trow++;
    }
    trow++;
    printf("\n") > ofile;

    printf("title\t%s\tsheet\t%s\ttype\tscatter_straight\n", "netstats_s/sec", "eth_stats") > ofile;
    trow++;
    printf("hdrs\t%d\t%d\t%d\t%d\t%d\n", trow+1, 2, -1, 1+nets_mx, 1) > ofile;
    trow++;
    printf("epoch\tts") > ofile
    for(i=1; i <= nets_mx; i++) {
      printf("\t%s", nets_hdrs[i]) > ofile;
    }
    printf("\n") > ofile;
    trow++;
    for(k=2; k <= n_nets; k++) {
      tdff = dt[k]-dt[k-1];
      printf("%.4f\t%d", dt[k], dt[k]-dt[1]) > ofile;
      for(i=1; i <= nets_mx; i++) {
        pnets[k,i] = nets_fctr[i]*(sv_nets[k,i] - sv_nets[k-1,i])/tdff;
        printf("\t%.3f", pnets[k,i]) > ofile;
      }
      printf("\n") > ofile;
      trow++;
    }
    trow++;
    printf("\n") > ofile;

    if (sum_file != "") {
    for (i=1; i <= nets_mx; i++) {
      delete arr_in;
      delete idx;
      delete res_i;
      nnstr = "";
      for(k=2; k <= n_nets; k++) {
        idx[k] = k;
        arr_in[k] = pnets[k,i];
        nnstr = nnstr "" sprintf("\t%f", arr_in[k]);
      }
      asorti(idx, res_i, "arr_in_compare");
      nstr = sprintf("%s\t%s\t%f\t%s val_arr", "netstats_val_arr", "netstats_val_arr", n_nets-1, nets_hdrs[i]);
      printf("%s%s\n", nstr, nnstr) > sum_file;
      for (kk=1; kk <= px_mx; kk++) {
        uval = compute_pxx(kk, n_nets-1, res_i, arr_in);
        strp = nets_hdrs[i] " p" px[kk];
        printf("%s\t%s\t%f\t%s\n", "tcp_netstat_per_hst", "tcp_netstat_per_hst", uval, strp) > sum_file;
      }
    }
    }
    if (avg_net_n > 0) {
      printf("avg_net_bw(MB/s)= %.3f\n", avg_net_bytes / (0.5*avg_net_n));
    }
    if (avg_net_pkts_n > 0) {
      printf("avg_net_pkts(K/s)= %.3f\n", avg_net_pkts / (0.5*avg_net_pkts_n));
    }
    if (avg_busy_n > 0) {
      printf("avg_%%busyTL= %.3f\n", avg_busy_sum / avg_busy_n);
    }
  }
  ' $ODIR/interval_stats.txt
    ck_last_rc $? $LINENO
  fi
    
fi
echo "$0.$LINENO got to bottom of script" >> $ODIR/trace_cmds.txt

exit 0

