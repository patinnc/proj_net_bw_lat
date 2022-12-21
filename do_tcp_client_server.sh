#!/usr/bin/env bash

SCR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCR_DIR
#MY_IP=$(ifconfig |grep 192.168|awk '{printf("%s\n", $2);exit(0);}')
MY_IP=$(hostname -I | awk '{print $1;}')
N_START=1
PORT=8000
OUTS_REQ=1
MSG_LEN=1024
VERBOSE=0
ODIR="tmp"
GOT_QUIT=0
export LC_ALL=C
DO_SCP=0
RET_CD=0
OPT_SKIP_CLIENT_LAT=

cd $SCR_DIR

ck_last_rc() {
   local RC=$1
   local FROM=$2
   if [[ $RC -gt 0 ]] || [[ "$GOT_QUIT" == "1" ]]; then
      echo "$0: got non-zero RC=$RC at $LINENO. called from line $FROM. GOT_QUIT= $GOT_QUIT" 1>&2
      RET_CD=1
      #kill -term $$ # send this program a terminate signal
      if [[ "$GOT_QUIT" == "1" ]]; then
        exit 1
      fi
      exit $RC
   fi
}

# function called by trap
catch_signal() {
    printf "\rSIGINT caught      "
    GOT_QUIT=1
}
trap 'catch_signal' SIGINT

EXTRA=0
NET_DEV=eth0
USER=root

while getopts "hvzxB:C:D:d:k:L:l:s:S:m:n:N:o:p:t:T:u:" opt; do
  case ${opt} in
    B )
      BW_MAX=$OPTARG
      ;;
    C )
      CLNT=$OPTARG
      ;;
    D )
      TCP_NODELAY=$OPTARG
      ;;
    d )
      ODIR=$OPTARG
      ;;
    k )
      KEYS=$OPTARG
      ;;
    l )
      LAT_CPU=$OPTARG
      ;;
    L )
     LAT_AFT=$OPTARG
      ;;
    m )
      MODE=$OPTARG
      ;;
    n )
      N_START=$OPTARG
      ;;
    N )
      NET_DEV=$OPTARG
      ;;
    o )
      OUTS_REQ=$OPTARG
      ;;
    p )
      PORT=$OPTARG
      ;;
    s )
      MSG_LEN=$OPTARG
      ;;
    S )
      SRVR=$OPTARG
      ;;
    t )
      TM_RUN=$OPTARG
      ;;
    T )
      TOT_PKTS=$OPTARG
      ;;
    u )
      USER=$OPTARG
      ;;
    v )
      VERBOSE=$((VERBOSE+1))
      ;;
    x )
      EXTRA=$((EXTRA+1))
      ;;
    z )
      OPT_SKIP_CLIENT_LAT=" -z "
      ;;
    h )
      echo "$0 run tcpdump client server"
      echo "Usage: $0 [ -v ] "
      echo "   -C client_ip"
      echo "   -D tcp_option_string  like -D maxseg=4csv900 "
      echo "   -S server_ip"
      echo "   -s length_of_request, def 1024"
      echo "   -k private_ssh_key_file  if you need a private key to ssh to client host then use this option"
      echo "   -m mode  mode= client or server or latency. this is for the case of running on the same host (so client_ip == server_ip)"
      echo "       if you are starting a run use '-m server'... the server code will invoke to client side. After the run you can do '-m latency' to gen latency stats"
      echo "       mode can also be server_scp which causes the tcp_*.sh, tcp_*.x and tcp_*.c files to be scp'd to client (if client!=server). scp'ing increases time of script when called from other scripts"
      echo "   -L if 1 do latency at end."
      echo "      The latency stuff can take a while so don't do '-L 1' if you don't want the extra time in your measurment. You can get the latency with '-m latency' later"
      echo "   -o outstandng_requests, can be -o x[,y]. if just -o x then y set to x. y is number of writes client will issue before doing x number of reads."
      echo "        server will do y reads from client and then x writes back to client. default is -o 1,1"
      echo "   -n number of processes to launch"
      echo "   -N network_device default eth0"
      echo "   -p port"
      echo "   -t time_to_run_in_secs this usually doesn't need to be as long as the full test run (maybe 5-10 secs of data). 1st dat file is usually not yet peak bw. def = 20"
      echo "   -T total msgs to send. If got -t time_in_secs and -T tot_msgs are entered then -T tot_msgs overrides"
      echo "   -v verbose mode"
      echo "   -x flag to collect 'perf stat' data (for computing frequency, %unhalted)"
      echo "   -z flag to skip collecting client latency data (if you have lots of requests this can take extra time (10% more sometimes (long run time, lots of outstanding)."
      echo "   -h this info"
      echo " example bw cmdline: (the ,nodelay=* arg is not necessary for bw test but the bw_altdir=1 is required for bw). -B 200 limits each proc to 200MB/s avg."
      echo "   -n 8 start 8 procs. -m server_scp means the script is being started from the server box and scp the client stuff to the client box. The -L 1 means run the get latency stuff after.".
      echo " ./do_tcp_client_server.sh -C 192.168.1.55 -S 192.168.1.162 -p 8000,8000 -n 8 -o 1 -t 10 -s 1000 -m server_scp -d tmp/tstb -l 24 -L 1  -D bw_altdir=1,nodelay=4csv1  -B 200"
      echo " example latency (do 1 send and wait for reply each loop)  cmdline:"
      echo " ./do_tcp_client_server.sh -C 192.168.1.55 -S 192.168.1.162 -p 8000,8000 -n 8 -o 1 -t 10 -s 1000 -m server_scp -d tmp/tstb -l 24 -B 0  -L 1"
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

#LST="proc_stat_0.txt proc_stat_1.txt tm_0.txt tmp_1.txt"
#for i in $LST; do
#  if [ -e "$ODIR/$i" ]; then
#    rm $ODIR/$i
#  fi
#done
 
if [[ "$ODIR" != "" ]] && [[ ! -d "$ODIR" ]]; then
  mkdir -p "$ODIR"
fi
if [ "$KEYS" != "" ]; then
  if [ ! -e $KEYS ]; then
    echo "$0.$LINENO didn't find -k $KEYS file. bye"
    exit 1
  fi
  OPT_KEYS="-i $KEYS"
fi
SSH_CMD_PFX=()
if [ "$USER" != "root" ]; then
  SSH_CMD_PFX=(sudo -u root -i bash -c)
fi
  SSH_CMD_PFX=(sudo -u root -i bash -c)
TM_TOP=$(date +"%s.%N")
MODE_IN=$MODE
if [[ "$MODE_IN" == *"server"* ]]; then
  DO_SERVER_JUST_START=1
  DO_SERVER_STARTS_CLIENT=1
  if [[ "$MODE_IN" == *"scp"* ]]; then
    DO_SCP=1
  fi
  if [[ "$MODE_IN" == *"just"* ]]; then
    DO_SERVER_JUST_START=1
    DO_SERVER_STARTS_CLIENT=0
  fi
  if [[ "$MODE_IN" == *"client"* ]]; then
    DO_SERVER_JUST_START=0
    DO_SERVER_STARTS_CLIENT=1
  fi
  MODE="server"
fi
echo "$0.$LINENO top of script section" >> $ODIR/trace_cmds.txt
if [[ "$MODE" == "" ]] && [[ "$CLNT" == "$SRVR" ]]; then
  echo "$0.$LINENO if client_ip == server_ip then you must enter -m server"
  exit 1
fi
if [[ "$MODE" == "" ]] && [[ "$CLNT" != "$SRVR" ]] && [[ "$MY_IP" == "$SRVR" ]]; then
  MODE="server"
fi
if [[ "$MODE" == "" ]] && [[ "$CLNT" != "$SRVR" ]] && [[ "$MY_IP" == "$CLNT" ]]; then
  MODE="client"
fi
if [[ "$MODE" != "client" ]] && [[ "$MODE" != "server" ]] && [[ "$MODE" != "latency" ]]; then
  echo "$0.$LINENO expected mode == client or server or latency. got \"-m $MODE\". bye"
  echo "cmd line= ${@}" 1>&2
  exit 1
fi
if [ ! -d $ODIR ]; then
  mkdir -p $ODIR
fi
OPT_V=
for ((i=1; i <= VERBOSE; i++)); do
    OPT_V="$OPT_V -v"
done
if [ "$TOT_PKTS" != "" ]; then
  OPT_PKTS=" -T $TOT_PKTS "
fi
A_ARR=(${PORT//,/ })
PORT_RD=${A_ARR[0]} # port for reads. client will read on this port, server will write on this port
PORT_WR=${A_ARR[1]} # client will write on this port, server will read on this port
if [ "$PORT_WR" == "" ]; then
  PORT_WR=$PORT_RD
fi
if [ "$PORT_RD" == "$PORT_WR" ]; then
  PORT_INC=1
else
  V=$((PORT_RD+1))
  if [ "$V" == "$PORT_WR" ]; then
    PORT_INC=2
  else
    V=$((PORT_RD+N_START))
    if [[ "$V" -gt "$PORT_WR" ]]; then
      echo "$0.$LINENO got read port= $PORT_RD and write port= $PORT_WR but with starting $N_START processes the port numbers will overlap. EXpect ending read port= $V"
      exit 1
    fi
    PORT_INC=1
  fi
fi
echo "$0.$LINENO got port_rd= $PORT_RD port_wr= $PORT_WR port_incr= $PORT_INC"
PR=$PORT_RD
PW=$PORT_WR
#exit 1
NUM_CPUS=$(grep -c processor /proc/cpuinfo)
if [ "$LAT_CPU" != "" ]; then
  BEG_CPU=$LAT_CPU
fi
ALTERNATE_DIR=
ALT_ARR=()
if [[ "$TCP_NODELAY" == *"bw_altdir=1"* ]]; then
  ALTERNATE_DIR=1
  ALT_ARR+=("1,0" "0,1")
  #echo "$0.$LINENO tcp_nodelay before= $TCP_NODELAY"
  echo "$0.$LINENO got alternating directions option. outstanding requests will alternate between 1,0 and 0,1 for each client+serve pair started"
  echo "$0.$LINENO alt_arr n= ${#ALT_ARR[@]} val= ${ALT_ARR[@]}"
fi
#echo "$0.$LINENO bye"
#exit 1
if [ "$TCP_NODELAY" != "" ]; then
  OPT_D=" -D $TCP_NODELAY "
  #OPT_DODELAY=$(echo $TCP_NODELAY | sed 's/bw_altdir=1//g' | sed 's/,,/,/g' | sed 's/^,//' sed 's/,$//')
fi
if [ "$MODE" == "server" ]; then
  echo "$0.$LINENO got into server section" >> $ODIR/trace_cmds.txt
  CK_ODIR=$(cd $ODIR; pwd)
  if [ "$CK_ODIR" == "/tmp" ]; then
    echo "$0.$LINENO got -d $ODIR and this seems to /tmp which we can't use as the -d dir (since I delete its contents). ck_dir= \"$CK_ODIR\" bye"
    exit 1
  fi
  if [ "$DO_SERVER_JUST_START" == "1" ]; then
    rm -rf $ODIR/*
    if [ "$DO_SCP" == "1" ]; then
      CK_GCC=$(command -v gcc)
      if [ "$CK_GCC" != "" ]; then
        gcc -O tcp_client.c -static -o tcp_client.x; gcc -O tcp_sort_latency.c -static -o tcp_sort_latency.x; gcc -O tcp_server.c -static -o tcp_server.x
        RC=$?
        if [ "$RC" != "0" ]; then
          echo $0.$LINENO gcc rc= $?
          exit 1
        fi
        if [[ "$VERBOSE" -gt "0" ]]; then
          echo "$0.$LINENO build of tcp_client.x and tcp_server.x got RC= $RC"
        fi
      fi
    fi
    if [ "1" == "2" ]; then
    if [ "$SRVR" != "$CLNT" ]; then
      if [[ "$VERBOSE" -gt "0" ]]; then
        echo "$0.$LINENO scp do_tcp_client_server.sh $CLNT:$SCR_DIR/do_tcp_client_server.sh"
      fi
      if [ "$DO_SCP" == "1" ]; then
      #scp do_tcp_client_server.sh $CLNT:$SCR_DIR/do_tcp_client_server.sh
      echo $0.$LINENO scp $OPT_KEYS do_tcp_client_server.sh tcp_server.* tcp_client.* tcp_sort_latency.* ${USER}@$CLNT:$SCR_DIR/
                      scp $OPT_KEYS do_tcp_client_server.sh tcp_server.* tcp_client.* tcp_sort_latency.* ${USER}@$CLNT:$SCR_DIR/
      RC=$?
      ck_last_rc $RC $LINENO
      echo "$0.$LINENO scp rc= $RC"
      fi
      #echo "$0.$LINENO bye"
      #exit 0
      #scp tcp_client.x ${USER}@$CLNT:$SCR_DIR/tcp_client.x
    fi
    fi
    pkill -2 -f $SCR_DIR/tcp_server.x
    CK_PID=$(pgrep -f $SCR_DIR/tcp_server.x)
      if [ "$CK_PID" != "" ]; then
        echo "$0.$LINENO __________________can't kill tcp_server.x. ck whats going on dude"
      fi
    if [ "$CK_PID" != "" ]; then
      pkill -9 -f $SCR_DIR/tcp_server.x
      CK_PID=$(pgrep -f $SCR_DIR/tcp_server.x)
      if [ "$CK_PID" != "" ]; then
        echo "$0.$LINENO can't kill tcp_server.x. ck whats going on dude"
        exit 1
      fi
    fi
    echo "$0.$LINENO got server side code"
    PERF_EVT="cpu-clock"
    OPT_F=" -F 1000 "
    ODAT="perf_callstacks.dat"
    OTXT="perf_callstacks.txt"
    for ((i=0; i < $N_START; i++)); do
      NUMA="strace -o $ODIR/strace_server.txt "
      NUMA=
      if [ "$BEG_CPU" != "" ]; then
        NUMA="numactl -C $BEG_CPU "
        BEG_CPU=$((BEG_CPU+1))
        if [[ "$BEG_CPU" -ge "$NUM_CPUS" ]]; then
          BEG_CPU=0
        fi
      fi
      OPT_ALT=" -o $OUTS_REQ "
      if [ "$ALTERNATE_DIR" == "1" ]; then
        jj=$((i % 2))
        OPT_ALT=" -o ${ALT_ARR[$jj]} "
      fi
      NN=$(printf "%.2d" $i)
      #if [[ "$VERBOSE" -gt "0" ]] || [[ "$i" -eq "0" ]];  then
      echo $0.$LINENO $NUMA $SCR_DIR/tcp_server.x -H $SRVR -s $MSG_LEN -p $PR,$PW $OPT_ALT -d $ODIR $OPT_V $OPT_D > $ODIR/tmp_tcp_server.${NN}.cmdline.txt
      #fi
                nohup $NUMA $SCR_DIR/tcp_server.x -H $SRVR -s $MSG_LEN -p $PR,$PW $OPT_ALT -d $ODIR $OPT_V $OPT_D > $ODIR/tmp_tcp_server.${NN}.txt 2> $ODIR/tmp_tcp_server.${NN}.stderr.txt &
                      RC=$?
      PR=$((PR+PORT_INC))
      PW=$((PW+PORT_INC))
    done
  fi
  #nohup $SCR_DIR/../60secs/perf record -k CLOCK_MONOTONIC $OPT_F -e $PERF_EVT -a -g -o "$ODIR/${ODAT}"  -- $SCR_DIR/../60secs/pfay1_sleep.sh $TM_RUN  &> $ODIR/perf_callstacks.log  &
  #PERF_PID=$!
  EPOCH_TM_BEG=$(date +"%s.%N")
  echo "$EPOCH_TM_BEG" > $ODIR/tm_0.txt
  if [ -d $ODIR/do_tcp ]; then
    echo "$EPOCH_TM_BEG" > $ODIR/do_tcp/tm_0.txt
  fi
  if [ "$DO_SERVER_STARTS_CLIENT" == "1" ]; then
    DO_PRC_STT=1
    #../patrick_fay_bin/spin.x -w freq_sml -t 0.0001 -l 1 > tmp_spin_0.txt
    CHIP_FAM=$($SCR_DIR/../60secs/decode_cpu_fam_mod.sh | sed 's/ /_/g' | awk '{printf("%s", tolower($0));exit(0);}')
    ck_last_rc $? $LINENO
    SPIN_WORK="freq_sml"
    if [ "$CHIP_FAM" == "ice_lake" ]; then
      SPIN_WORK="spin"
    fi
    echo "$0.$LINENO chip_fam= $CHIP_FAM"
    SPIN_LOAD=0
    if [[ "$TCP_NODELAY" == *"spin_load"* ]]; then
      SPIN_LOAD=1
      modprobe msr
    fi
    PRC_STT_0=$(cat /proc/stat)
    echo "$PRC_STT_0" | head -1
    if [ "$DO_PRC_STT" == "1" ]; then
      echo "$PRC_STT_0" > $ODIR/proc_stat_0.txt
    fi
    STAT_TM0=$(date +"%s")
    OPT_X=
    if [ "$EXTRA" != "0" ]; then
      OPT_X=" -x "
    fi
    if [ "$SPIN_LOAD" != "0" ]; then
      SPIN_LD=$(awk -v val="$SPIN_LOAD" 'BEGIN{n=val+0; if (n>100){n=100;} if (n > 0 ) {printf("%.4f", 0.01*n);} else {printf("0");}; exit(0);}')
      echo "$0.$LINENO nohup nice -20 $SCR_DIR/../patrick_fay_bin/spin.x -w $SPIN_WORK -t $TM_RUN  > $ODIR/spin.txt &"
      nohup nice -20 $SCR_DIR/../patrick_fay_bin/spin.x -w $SPIN_WORK -t $TM_RUN    > $ODIR/spin.txt 2> $ODIR/spin2.txt &
      #nohup          $SCR_DIR/../patrick_fay_bin/spin.x -w $SPIN_WORK -t $MON_SECS  > $ODIR/spin.txt &
      #nohup $SCR_DIR/../patrick_fay_bin/spin.x -w spin -t $MON_SECS > $ODIR/spin.txt &
      SPIN_PID=$!
      TM_SPIN0=$(date +"%s.%N")
    fi
    $SCR_DIR/get_new_pckts_frames_MBs_int.sh -N $NET_DEV -d $ODIR -t $TM_RUN $OPT_PKTS -a get $OPT_X &
    STAT_PID=$!
    if [ "$LAT_CPU" != "" ]; then
      OPT_LAT=" -l $LAT_CPU "
    fi
    TM_beg=$(date +"%s.%N")
    echo "$0.$LINENO abs_ts start -m client tm= $TM_beg"
    if [ "$SRVR" != "$CLNT" ]; then
      if [ "$BW_MAX" != "" ]; then
        OPT_BW_MAX=" -B $BW_MAX "
      fi
      #nohup nice -20 $SCR_DIR/../patrick_fay_bin/spin.x -w freq_sml -t $TM_RUN  > $ODIR/spin.txt 2>&1 &
      #TM_begq=$(date +"%s")
      TM_DT=$(date)
      echo "$0.$LINENO got here"
      if [ 1 == 1 ]; then
      CMD=$(printf "%q" "$SCR_DIR/do_tcp_client_server.sh $OPT_D $OPT_V $OPT_BW_MAX $OPT_PKTS -m client -S $SRVR -s $MSG_LEN -n $N_START -o $OUTS_REQ -t $TM_RUN -p $PORT_RD,$PORT_WR -d $ODIR $OPT_LAT $OPT_SKIP_CLIENT_LAT ")
      echo $0.$LINENO ssh $OPT_KEYS -A -t ${USER}@$CLNT "${SSH_CMD_PFX[@]} $CMD" > $ODIR/start_do_tcp_client_server.sh.txt
      echo "$0.$LINENO before do_tcp_client_server.sh -m client got here beg date_time= $TM_DT abs_ts= $TM_beg"
                      ssh $OPT_KEYS -A -t ${USER}@$CLNT "${SSH_CMD_PFX[@]} $CMD" >> $ODIR/start_do_tcp_client_server.sh.txt
      RC=$?
      ck_last_rc $RC $LINENO
      echo "$0.$LINENO ssh rc= $RC"
      else
      echo $0.$LINENO ssh $OPT_KEYS -A -t  ${USER}@${CLNT} "$SCR_DIR/do_tcp_client_server.sh $OPT_D $OPT_V $OPT_BW_MAX $OPT_PKTS -m client -S $SRVR -s $MSG_LEN -n $N_START -o $OUTS_REQ -t $TM_RUN -p $PORT_RD,$PORT_WR -d $ODIR $OPT_LAT $OPT_SKIP_CLIENT_LAT " > $ODIR/start_do_tcp_client_server.sh.txt
                      ssh $OPT_KEYS -A -t ${USER}@${CLNT} "$SCR_DIR/do_tcp_client_server.sh $OPT_D $OPT_V $OPT_BW_MAX $OPT_PKTS -m client -S $SRVR -s $MSG_LEN -n $N_START -o $OUTS_REQ -t $TM_RUN -p $PORT_RD,$PORT_WR -d $ODIR $OPT_LAT $OPT_SKIP_CLIENT_LAT " >> $ODIR/start_do_tcp_client_server.sh.txt
      RC=$?
      ck_last_rc $RC $LINENO
      echo "$0.$LINENO ssh rc= $RC"
      fi
      echo "$0.$LINENO got here"
    else
      echo $0.$LINENO "$SCR_DIR/do_tcp_client_server.sh $OPT_D $OPT_V $OPT_PKTS $OPT_BW_MAX -m client -S $SRVR -s $MSG_LEN -n $N_START -o $OUTS_REQ -t $TM_RUN -p $PORT_RD,$PORT_WR -m client -d $ODIR  " > $ODIR/start_do_tcp_client_server.sh.txt
                       $SCR_DIR/do_tcp_client_server.sh $OPT_D $OPT_V $OPT_PKTS $OPT_BW_MAX -m client -S $SRVR -s $MSG_LEN -n $N_START -o $OUTS_REQ -t $TM_RUN -p $PORT_RD,$PORT_WR -m client -d $ODIR  >> $ODIR/start_do_tcp_client_server.sh.txt
    fi
    TM_endq=$(date +"%s")
    EPOCH_TM_END=$(date +"%s.%N")
    TM_CLNT=$(awk -v tm1="$EPOCH_TM_END" -v tm0="$TM_beg" 'BEGIN{ dff= tm1 - tm0; printf("%f\n", dff); exit(0);}')
    echo "$0.$LINENO abs_ts end   -m client tm= $EPOCH_TM_END run client tm_diff= $TM_CLNT"
    echo "$0.$LINENO do_tcp_client_server.sh -m client took $TM_CLNT secs" >> $ODIR/trace_cmds.txt
    if [ ! -e $ODIR/tm_1.txt ]; then
      echo "$EPOCH_TM_END" > $ODIR/tm_1.txt
    fi
    if [[ -d $ODIR/get_new_pckts_frames_MBs_int ]] && [[ ! -e $ODIR/get_new_pckts_frames_MBs_int/tm_1.txt ]]; then
      echo "$EPOCH_TM_END" > $ODIR/get_new_pckts_frames_MBs_int/tm_1.txt
    fi
    if [ "$SPIN_PID" != "" ]; then
      if [ -e /proc/$SPIN_PID ]; then
        kill -2 $SPIN_PID
      fi
      TM_SPIN1=$(date +"%s.%N")
      TM_SPIN_DFF=$(awk -v tm0="$TM_SPIN0" -v tm1="$TM_SPIN1" 'BEGIN{printf("%f", tm1-tm0);exit(0);}')
      echo "$0.$LINENO tm_spin_dff= $TM_SPIN_DFF"
    fi
    if [[ -d $ODIR/do_tcp ]] && [[ ! -e $ODIR/do_tcp/tm_1.txt ]]; then
      echo "$EPOCH_TM_END" > $ODIR/do_tcp/tm_1.txt
    fi
    TM_dffq=$((TM_endq - TM_begq))
    #../patrick_fay_bin/spin.x -w freq_sml -t 0.0001 -l 1 > /dev/null
    #../patrick_fay_bin/spin.x -w freq_sml -t 0.0001 -l 1 > tmp_spin_1.txt
    if [ ! -e $ODIR/proc_stat_1.txt ]; then
      PRC_STT_1=$(cat /proc/stat)
    fi
    echo "$PRC_STT_1" | head -1
    if [ -d $ODIR/get_new_pckts_frames_MBs_int ]; then
      echo "$PRC_STT_1" > $ODIR/get_new_pckts_frames_MBs_int/proc_stat_1.txt
    fi
    if [[ "$DO_PRC_STT" == "1" ]] || [[ ! -e $ODIR/proc_stat_1.txt ]]; then
      if [ ! -e $ODIR/proc_stat_1.txt ]; then
        echo "$PRC_STT_1" > $ODIR/proc_stat_1.txt
      fi
      if [ -d $ODIR/get_new_pckts_frames_MBs_int ]; then
        cp $ODIR/get_new_pckts_frames_MBs_int/tm_*.txt $ODIR
      fi
    fi
    EPOCH_TM_DIFF=$(awk -v tm0="$EPOCH_TM_BEG" -v tm1="$EPOCH_TM_END" 'BEGIN{tm_dff = tm1 - tm0; printf("%.6f", tm_dff);exit(0);}')
    ck_last_rc $? $LINENO
    echo "$0.$LINENO tm_run= $TM_RUN tm_dffq= $TM_dffq  epoch_tm_diff= $EPOCH_TM_DIFF"
    if [ "$PERF_PID" != "" ]; then
      pkill -9 pfay1_sleep.sh
      wait $PERF_PID
      $SCR_DIR/../60secs/perf script -I --header -i $ODIR/$ODAT --kallsyms=/proc/kallsyms > $ODIR/$OTXT
      perl $SCR_DIR/../FlameGraph/stackcollapse-perf.pl $ODIR/$OTXT | perl $SCR_DIR/../FlameGraph/flamegraph.pl > $ODIR/$OTXT.svg
    fi
    if [ "$STAT_PID" != "" ]; then
      #echo "$0.$LINENO do ps -ef pfay1_sleep.sh $STAT_PID"
      #ps -ef|grep pfay1_sleep.sh
      STAT_TM1=$(date +"%s")
      STAT_TM_DFF=$((STAT_TM1-STAT_TM0))
      echo "$0.$LINENO pgrep stat_elap_secs= $STAT_TM_DFF"
      pgrep  pfay1_sleep.sh
      pkill  -9 pfay1_sleep.sh
      #kill -2 $STAT_PID
      wait $STAT_PID
    fi
    if [ "$SPIN_LOAD" != "0" ]; then
      SPN_TXT_CUR=$($SCR_DIR/rd_spin_freq.sh $ODIR $NET_DEV)
      echo "$0.$LINENO spin_txt: $SPN_TXT_CUR"
    fi
    TM_aft=$(date +"%s.%N")
    TM_end=$(date +"%s.%N")
    TM_DFF=$(awk -v tm_beg="$TM_beg" -v tm_aft="$TM_aft" -v tm_scp="$TM_scp" -v tm_end="$TM_end" 'BEGIN{printf("tm_tcp_server.x= %.3f tm_scp= %.3f tm_rem= %.3f tm_elap= %.3f\n",
         tm_aft-tm_beg, tm_scp-tm_aft, tm_end-tm_scp, tm_end-tm_beg); exit(0);}')
    echo "$0.$LINENO finished client side: $TM_DFF"
    # latency pct= 10 latency(usecs)= 28.118957
    # RPS(k) p50 p90 p99
    #if [ -d $ODIR/get_new_pckts_frames_MBs_int ]; then
    #   $SCR_DIR/get_new_pckts_frames_MBs_int.sh -d $ODIR -t $TM_RUN -a read
    #fi
    if [ 1 == 1 ]; then
    if [ "$LAT_AFT" == "1" ]; then
      MODE="latency"
    fi
    fi
  fi
  echo "$0.$LINENO got at end of server section" >> $ODIR/trace_cmds.txt
  wait
  exit 0

elif [ "$MODE" == "client" ]; then

  if [ ! -d "$ODIR" ]; then
    mkdir -p $ODIR
  fi
  echo "$0.$LINENO got into client section" >> $ODIR/trace_cmds.txt
  pkill -2 -f $SCR_DIR/tcp_client.x
  if [[ "$VERBOSE" -gt "0" ]]; then
  echo "$0.$LINENO got client side code"
  fi
  rm $ODIR/tmp_tcp_client.*.txt $ODIR/tcp_client_*_latency.txt $ODIR/tmp_lat_all_unsorted.txt 1> /dev/null 2>&1
  if [ "$BW_MAX" != "" ]; then
    OPT_BW_MAX=" -B $BW_MAX "
  fi
  OPT_SKP_LAT=
  if [ "$OPT_SKIP_CLIENT_LAT" != "" ]; then
    OPT_SKP_LAT=" -l "
  fi
  TM_bef=$(date +"%s.%N")
  for ((i=0; i < $N_START; i++)); do
    NN=$(printf "%.2d" $i)
    NUMA="strace -o $ODIR/strace_client.txt "
    NUMA=
    if [ "$BEG_CPU" != "" ]; then
      NUMA="numactl -C $BEG_CPU "
      BEG_CPU=$((BEG_CPU+1))
      if [[ "$BEG_CPU" -ge "$NUM_CPUS" ]]; then
        BEG_CPU=0
      fi
    fi
    OPT_ALT=" -o $OUTS_REQ "
    if [ "$ALTERNATE_DIR" == "1" ]; then
      jj=$((i % 2))
      OPT_ALT=" -o ${ALT_ARR[$jj]} "
    fi
    #if [[ "$VERBOSE" -gt "0" ]]; then
    echo "$0.$LINENO $NUMA $SCR_DIR/tcp_client.x $OPT_D $OPT_V $OPT_BW_MAX $OPT_PKTS -H $SRVR -s $MSG_LEN -t $TM_RUN $OPT_ALT -p $PR,$PW -d $ODIR $OPT_SKP_LAT i= $i PORT= $PORT   > $ODIR/tmp_tcp_client.${NN}.cmdline.txt"
    #fi
               nohup $NUMA $SCR_DIR/tcp_client.x $OPT_D $OPT_V $OPT_BW_MAX $OPT_PKTS -H $SRVR -s $MSG_LEN -t $TM_RUN $OPT_ALT -p $PR,$PW -d $ODIR $OPT_SKP_LAT > $ODIR/tmp_tcp_client.${NN}.txt 2> $ODIR/tmp_tcp_client.${NN}.stderr.txt &
    PR=$((PR+PORT_INC))
    PW=$((PW+PORT_INC))
  done
  TM_BEF_WAIT=$(date +"%s.%N")
  wait
  TM_aft=$(date +"%s.%N")
  cat $ODIR/tmp_tcp_client.*.txt
  TM_end=$(date +"%s.%N")
  TM_DFF=$(awk -v tm_bef_wait="$TM_BEF_WAIT" -v tm_bef="$TM_bef" -v tm_aft="$TM_aft" -v tm_end="$TM_end" 'BEGIN{printf("tm_tcp_client.x= %.3f tm_post= %.3f tm_elap= %.3f abs_ts abs_ts_bef_start_clients= %.6f tm_dff_to_start_clients= %.3f\n",
       tm_aft-tm_bef, tm_end-tm_aft, tm_end-tm_bef, tm_bef_wait, tm_bef_wait-tm_bef); exit(0);}')
  echo "$0.$LINENO finished client side: $TM_DFF"
  echo "$0.$LINENO got at end of client section" >> $ODIR/trace_cmds.txt
  echo "$0.$LINENO got end_of_client tm_dff= $TM_DFF" >> $ODIR/trace_cmds.txt
  echo "$0.$LINENO got end_of_client tm_dff= $TM_DFF"
  exit 0
fi

if [[ "$MODE" == "latency" ]]; then

  echo "$0.$LINENO got into latency section" >> $ODIR/trace_cmds.txt
  TM_beg=$(date +"%s.%N")
  TMP_UNSRTED=$ODIR/tmp_lat_all_unsorted.txt
  OSORT="$ODIR/tcp_client_latency_all.txt"
  if [ ! -e $TMP_UNSRTED ]; then
      CMD=$(printf "%q" "cd $SCR_DIR; cat $ODIR/tcp_client_*_latency.txt > /tmp/tmp_lat_all_unsorted.txt")
      echo "$0.$LINENO got here"
      echo $0.$LINENO ssh $OPT_KEYS -A -t ${USER}@$CLNT "${SSH_CMD_PFX[@]} $CMD"
                      ssh $OPT_KEYS -A -t ${USER}@$CLNT "${SSH_CMD_PFX[@]} $CMD"
      RC=$?
      ck_last_rc $RC $LINENO
      echo "$0.$LINENO ssh rc= $RC"
      echo "$0.$LINENO got here"
  #ssh $OPT_KEYS ${USER}@${CLNT} "cd $SCR_DIR; cat $ODIR/tcp_client_*_latency.txt > $ODIR/tmp_lat_all_unsorted.txt"
   echo $0.$LINENO scp $OPT_KEYS ${USER}@${CLNT}:/tmp/tmp_lat_all_unsorted.txt $ODIR/tmp_lat_all_unsorted.txt >> tmp/tmp.jnk
                   scp $OPT_KEYS ${USER}@${CLNT}:/tmp/tmp_lat_all_unsorted.txt $ODIR/tmp_lat_all_unsorted.txt 2>> tmp/tmp2.jnk
      RC=$?
      ck_last_rc $RC $LINENO
      echo "$0.$LINENO scp rc= $RC"
                   CMD=$(printf "%q" "cd $SCR_DIR/$ODIR; rm /tmp/tmp_lat_all_unsorted.txt; rm tcp_client_80*_latency.txt")
      echo "$0.$LINENO got here"
                   ssh $OPT_KEYS -A -t ${USER}@$CLNT "${SSH_CMD_PFX[@]} $CMD"
      RC=$?
      ck_last_rc $RC $LINENO
      echo "$0.$LINENO ssh rc= $RC"
      echo "$0.$LINENO got here"
                  #ssh $OPT_KEYS ${USER}@${CLNT} "cd $SCR_DIR/$ODIR; rm tmp_lat_all_unsorted.txt; rm tcp_client_80*_latency.txt"
    if [ ! -e $TMP_UNSRTED ]; then
      echo "$0.$LINENO didn't find unsorted latency file $TMP_UNSRTED. bye"
      exit 1
    fi
  fi
  ls -l $TMP_UNSRTED
  LAT_PXX=$ODIR/latency_pxx_stats.txt
  if [[ -e "$TMP_UNSRTED" ]] && [[ -e $SCR_DIR/tcp_sort_latency.x ]]; then
    $SCR_DIR/tcp_sort_latency.x -i $TMP_UNSRTED > $LAT_PXX
    rm $TMP_UNSRTED
  fi
  cat $LAT_PXX
  #sorting and writing latency data took 0.01836 seconds for file= tmp/tstb1/tcp_client_8029_latency.txt at tcp_client.c 681
  grep "writing latency" $ODIR/start_do_tcp_client_server.sh.txt | sort -nk 7 |head -1
  grep "writing latency" $ODIR/start_do_tcp_client_server.sh.txt | sort -nk 7 |tail -1
  GET_STATS=$(awk '/^MB\/sec= / { sum += $2+0; rps+= $8; n++;} END{printf("tot_MB/sec= %.3f tot_rpsK= %.3f\n", sum, rps);}' $ODIR/start_do_tcp_client_server.sh.txt)
  LAT_STATS=$(awk -v get_stats="$GET_STATS" '
     BEGIN{
       n = split(get_stats, arr, " ");
       tot_MBps = arr[2];
       tot_rpsK = arr[4];
     }
     /latency/ { lat[$3] = $5;}
     END{
        printf("tot_MBps= %.3f\n", tot_MBps);
        printf("tot_rpsK= %.3f\n", tot_rpsK);
        printf("p50= %.3f\n", lat["50"]);
        printf("p90= %.3f\n", lat["90"]);
        printf("p99= %.3f\n", lat["99"]);
     }' $ODIR/latency_pxx_stats.txt)
  ck_last_rc $? $LINENO
  echo "$LAT_STATS" >> $ODIR/do_tcp_summary_stats.txt
  echo "lat_stats= $LAT_STATS" >> tmp/tmp.jnk
  echo "$LAT_STATS"
  ./rd_proc_stat.sh $ODIR
  exit 0
  if [ -e "$TMP_UNSRTED" ]; then
  sort -nk 1 < $TMP_UNSRTED  > $OSORT
  #cat $ODIR/tcp_client_*_latency.txt | sort -nk 1 > $OSORT
  NLINES=$(cat $OSORT | wc -l)
  TM_srt=$(date +"%s.%N")
  echo "$0.$LINENO nlines= $NLINES"
  awk -v nlines="$NLINES" -v lat_str="10 20 30 40 50 60 70 80 90 95 99 99.5 99.9 99.999 100" '
    BEGIN{
      rc = 0;
      nlines += 0;
      if (nlines < 1) {
         printf("got nlines in file %s < 1.... somethings wrong.\n", ARGV[1]);
         rc = 1;
         exit(rc);
      }
      n = split(lat_str, lat_arr, " ");
      for (i=1; i <= n; i++) {
        lat_list[lat_arr[i]] = i;
        lat_lkup[i] = lat_arr[i] + 0;
      }
      n_lat = n;
      n = 0;
      ck = 1;
    }
    {
      n++;
      n_pct = 100 * n/nlines;
      for (i= ck; i <= n_lat; i++) {
        if (n_pct >= lat_lkup[i]) {
          if (i < n_lat || n == nlines) {
          printf("latency pct= %s latency(usecs)= %s\n", lat_lkup[i], $1);
          ck++;
          }
        }
        break;
     }
   }
   ' $OSORT >> $ODIR/start_do_tcp_client_server.sh.txt
  TM_pxx=$(date +"%s.%N")
  
  echo "$0.$LINENO hi" >> tmp/tmp.jnk
  echo "$0.$LINENO ready to do lat_stats"
  echo "$LAT_STATS"
  echo "$0.$LINENO hi" >> tmp/tmp.jnk
  echo "$LAT_STATS" >> $ODIR/do_tcp_summary_stats.txt
  echo "lat_stats= $LAT_STATS" >> tmp/tmp.jnk
  pwd >> tmp/tmp.jnk
  echo "last line" >> tmp/tmp.jnk
  echo "$0.$LINENO hi" >> tmp/tmp.jnk
  ls -l $ODIR/start_do_tcp_client_server.sh.txt >> tmp/tmp.jnk
  ck_last_rc $? $LINENO
  TM_end=$(date +"%s.%N")
  grep "latency pct" $ODIR/start_do_tcp_client_server.sh.txt
  awk -v line="$0.$LINENO" -v tm_beg="$TM_beg" -v tm_pxx="$TM_pxx" -v tm_srt="$TM_srt" -v tm_end="$TM_end" 'BEGIN{printf("%s mode=latency tm_sort= %.3f tm_pxx= %.3f tm_rem= %.3f tm_elap= %.3f\n",
       line, tm_srt-tm_beg, tm_pxx-tm_srt, tm_end-tm_pxx, tm_end-tm_beg); exit(0);}'
  rm $TMP_UNSRTED  $OSORT
  else
        printf "tot_MBps= %.3f\n"  0.0
        printf "tot_rpsK= %.3f\n"  0.0
        printf "p50= %.3f\n" 0.0
        printf "p90= %.3f\n" 0.0
        printf "p99= %.3f\n" 0.0
  fi
  if [ "$DO_PRC_STT" == "1" ]; then
    if [ -d $ODIR/get_new_pckts_frames_MBs_int ]; then
      cp $ODIR/get_new_pckts_frames_MBs_int/tm_*.txt $ODIR
    fi
  fi
  echo "$0.$LINENO got to here"
  echo "$0.$LINENO got at end of latency section" >> $ODIR/trace_cmds.txt
fi 
echo "$0.$LINENO got at end of section" >> $ODIR/trace_cmds.txt
exit 0
 
