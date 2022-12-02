#!/usr/bin/env bash

SCR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
#sysctl -w net.ipv4.tcp_low_latency=1  # def 0 on brc. see https://support.mellanox.com/s/article/linux-sysctl-tuning

# function called by trap
catch_signal() {
    printf "\rSIGINT caught      "
    GOT_QUIT=1
}
trap 'catch_signal' SIGINT

#CLNT=192.168.1.55
#SRVR=192.168.1.119 
MSG_LEN=1000,1000
ODIR="tmp/tstb1"
PORT="8000,8000"
BW_MAX=200
N_LST_BW="1 2 3 4 5 6 7 8 10 12 14 16"  # bw cliets
N_LST_LAT="1 2 3 4 5 6 7 8 10 20 30 40 48 72 96" # lat clients
TM_RUN=
Q_IN=
TYP_NIC=$(lspci|grep Ether| awk '/Mellan/{printf("mlx");exit(0);}/Broadcom/{printf("brc");exit(0);}')
NET_DEV=$($SCR_DIR/set_eth0.sh -c get_cur_str | awk -v ln="$0.$LINENO.awk" '
  / dev= /{
   if ($4 != "dev="){
     printf("dev= string expected to be field 4, line= %s. missed dev=. error at %s\n", $0, ln) > "/dev/stderr";
     exit(1)
   }
   printf("%s\n", $5);
  }')
echo "net_dev= $NET_DEV"
#exit 1
BOTH_IN=0
CMD_LN="$@"
echo "$0.$LINENO cmd_line= $CMD_LN"
CMD_ARR=( $0 "$@" )
QT_ARR=()
for ((i=0; i < ${#CMD_ARR[@]}; i++)); do
  echo "cmd[$i]= ${CMD_ARR[$i]}"
  #CMD_ARR+=(${@[$i]})
  if [[ "${CMD_ARR[$i]}" == *" "* ]]; then
    QT_ARR+=("'${CMD_ARR[$i]}'")
  else
    QT_ARR+=(${CMD_ARR[$i]})
  fi
done
REDIR1=$(readlink /proc/$$/fd/1)
REDIR2=$(readlink /proc/$$/fd/2)
if [[ "$REDIR1" != *"pts"* ]]; then
  QT_ARR+=(">")
  QT_ARR+=($REDIR1)
fi
if [[ "$REDIR2" != *"pts"* ]]; then
  if [ "$REDIR1" == "$REDIR2" ]; then
    QT_ARR+=("2>&1")
    QT_ARR+=($REDIR1)
  else
    QT_ARR+=("2>")
    QT_ARR+=($REDIR2)
  fi
fi
echo "$0.$LINENO cmd_arr= ${CMD_ARR[@]}"
echo "$0.$LINENO qt_arr= ${QT_ARR[@]}"
XFER_IN=0
#exit 1
USER=root
SSH_CMD_PFX=()

while getopts "bhvXzB:C:D:d:L:l:m:n:o:p:q:s:S:t:T:u:" opt; do
  case ${opt} in
    b )
      BOTH_IN=1
      ;;
    B )
      BW_MAX=$OPTARG
      ;;
    C )
      CLNT=$OPTARG
      ;;
    D )
      TCP_OPTIONS=$OPTARG
      ;;
    d )
      ODIR=$OPTARG
      ;;
    l )
      LAT_CPU_IN="$(echo "$OPTARG" | sed 's/,/ /g')"
      ;;
#    L )
#      LAT_AFT=$OPTARG
#      ;;
#    m )
#      MODE=$OPTARG
#      ;;
    n )
      N_START_IN="$(echo "$OPTARG" | sed 's/,/ /g')"
      ;;
    o )
      OUTS_REQ=$OPTARG
      ;;
    p )
      PORT_IN=$OPTARG
      ;;
    q )
      Q_IN="$(echo "$OPTARG" | sed 's/,/ /g')"
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
      TYP_TST_IN="$(echo "$OPTARG" | sed 's/,/ /g')"
      #TOT_PKTS=$OPTARG
      ;;
    u )
      USER=$OPTARG
      ;;
    v )
      VERBOSE=$((VERBOSE+1))
      ;;
    X )
      XFER_IN=1
      ;;
    z )
      OPT_SKIP_CLIENT_LAT=" -z "
      ;;
    h )
      echo "$0 run tcpdump client server"
      echo "Usage: $0 [ -v ] "
      echo "   -b flag   if -b then, after running test on this server, run the same test on the client (so switch client server roles)"
      echo "      Currently this 'run the test on the other host' is only done if the current host has a broadcom NIC (just to make sure we don't get in a loop)"
      echo "   -B bw_max  for bw-type tests each client limits it bw to bw_max MB/sec. default is $BW_MAX MB/secs"
      echo "   -C client_ip"
      echo "   -d output_dir the various output files will be put here. The dir will be created if it doesn't exist. default is './tmp/tstb1/'"
      echo "   -D tcp_option_string  like -D maxseg=4csv900"
      echo "      if the option string doesn't begin with ',' then it replaces the default_tcp_options string entirely."
      echo "      if the option string begins with ',' then it is appended to the default_tcp_options string."
      echo "      For bw tests the bw_altdir=1 option string is added by default, then the new option string logic is done."
      echo "   -S server_ip"
      echo "   -s length_of_request, def 1024"
      echo "   -l lat_cpu_list   on 48 cpu box this is usually the HT1 cpu of the 1st core with the NIC. "
      echo "      You can add the Ht1 thread of the 1st core without the NIC like (on 48 cpu box1) '-l \"24 36\"'."
      echo "      The 1st client & server thread is put on this cpu, the next thread on the next cpu, etc wrapping around to 0"
      echo "      you can enter lo or hi or '-l \"hi lo\"' or '-l hi,lo' and the script will figure out the hi_perf cpu and the low perf cpu."
      echo "      The default is hi"
      echo "      Note that the latency-type test defaults to starting up to 96 client-server pairs so on a 96 cpu box every cpu will get a thread started"
      echo "   -m mode  mode= client or server or latency. this is for the case of running on the same host (so client_ip == server_ip)"
      echo "       if you are starting a run use '-m server'... the server code will invoke to client side. After the run you can do '-m latency' to gen latency stats"
      echo "       mode can also be server_scp which causes the tcp_*.sh, tcp_*.x and tcp_*.c files to be scp'd to client (if client!=server). scp'ing increases time of script when called from other scripts"
      echo "   -L if 1 do latency at end."
      echo "      The latency stuff can take a while so don't do '-L 1' if you don't want the extra time in your measurment. You can get the latency with '-m latency' later"
      echo "   -o outstandng_requests, can be -o x[,y]. if just -o x then y set to x. y is number of writes client will issue before doing x number of reads."
      echo "        server will do y reads from client and then x writes back to client. default is -o 1,1"
      echo "   -n number of client (and server) threads to launch. Can be space (or ,) separated list (if has spaces then enclose in dbl quotes)."
      echo "      for latency-type tests the default list is \"$N_LST_LAT\""
      echo "      for bw-type tests the default list is \"$N_LST_BW\""
      echo "      you can also enter '-n max' to use just the last value in the default list or '-n min' to use just the 1st value in the list"
      echo "   -p port|snd_port,rcv_port   default is -p $PORT"
      echo "   -q cfg_in like cfg_q8 or cfg_q48 or cfg_q48_a10 or cfg_qmax(to set the queue size to the max allowable) or cfg_q8,cfg_qmax"
      echo "      string should be like what ./set_eth0 get_cur_str returns"
      echo "        ./set_eth0.sh -c get_cur_str"
      echo "        ./set_eth0.sh.118 typ= brc dev= eth0"
      echo "        cfg_str cfg_q48_a00_ru6_rf6_rif1_tu28_tf30_tif2"
      echo "          basically the cfg_q* string broken into a '_' separated array where q* is the queue size, a* is adaptive rx tx enabled=1 disabled=0,"
      echo "          edit set_eth0 and look for \"ru\" to see section of code that handles the substrings and the ethtool cmds for that substring"
      echo "   -t time_to_run_in_secs usually 30-60 seconds is good enough in the lab. quick measurements of 10 secs seem okay. default = 20"
      echo "   -T bw|lat|\"bw lat\"|bw,lat  test_typ can be bw or lat or both \"bw lat\". def is lat"
      echo "   -X   flag indicating you want to create a copy of the current dir's *.sh *.c *.x files on the client's $SCR_DIR"
      echo "   -v verbose mode"
      echo "   -z flag to skip collecting client latency data if you have lots of requests this can take extra time, 10% more sometimes,long run time, lots of outstanding."
      echo "      This time is not part of the measurement time. If latency data is generated it is written in 4byte float binary by each client during the test."
      echo "      This usually adds only 0.0x seconds to the client run time on nvme drives. The output dir file start_do_tcp_client_server.sh.txt has the time."
      echo "      Look for \"writing latency data took \" lines in the file. After the measurements/timings are done then post processing concats all the lat data files, sorts them, then create latency pXX percentiles"
      echo "   -h this info"
      echo " example bw cmdline: the ,nodelay=* arg is not necessary for bw test but the bw_altdir=1 is required for bw. -B 200 limits each proc to 200MB/s avg."
      echo "   -n 8 start 8 procs. -m server_scp means the script is being started from the server box and scp the client stuff to the client box. The -L 1 means run the get latency stuff after."
      echo " ./do_tcp_client_server.sh -C 192.168.1.55 -S 192.168.1.162 -p 8000,8000 -n 8 -o 1 -t 10 -s 1000 -m server_scp -d tmp/tstb -l 24 -L 1  -D bw_altdir=1,nodelay=4csv1  -B 200 -x"
      echo " example latency: do 1 send and wait for reply each loop  cmdline:"
      echo " ./do_tcp_client_server.sh -C 192.168.1.55 -S 192.168.1.162 -p 8000,8000 -n 8 -o 1 -t 10 -s 1000 -m server_scp -d tmp/tstb -l 24 -B 0  -L 1 -x"
      echo " example to latency-type test, put the 1st client/server threads on the hi perf cpu, and increment from that cpu, wrapping around if needed,"
      echo "     use the last value in the number-of-client/server threads list '-n max', run for 60 seconds,"
      echo "     connect to client 192.168.1.218, the server ip is 192.168.1.231. Probably shouldn't be necessary but you can have multiple ip addr on a server"
      echo " ./quick_net.sh -q cfg_qmax  -l hi  -n max  -T lat -t 60 -C 192.168.1.218  -S 192.168.1.231 -X  > tmp4.txt"
      echo " ./extract_tcp_stats.sh tmp4.txt  # extract summary info and display it"
      echo " "
      echo " The tests will done over:"
      echo "   for -T test_type_list"
      echo "     for -q ethtool_configs_list"
      echo "       for -l initial_cpu_to_start_client_server_pairs_on_list"
      echo "         for -n number_of_client_server_pairs_to_start_list" 
      echo "           for outstanding list"
      echo "             ./do_tcp_client_server.sh ..."
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
if [ "$Q_IN" == "" ]; then
  $SCR_DIR/set_eth0.sh -c cfg_q8
else
  $SCR_DIR/set_eth0.sh -c $Q_IN
fi
if [ "$PORT_IN" != "" ]; then
  PORT=$PORT_IN
fi
$SCR_DIR/set_eth0.sh -c get_cur_str  # get current settings string

  SSH_CMD_PFX=(sudo -u root -i bash -c)
if [ "$USER" != "root" ]; then
  #SSH_CMD_PFX=("sudo" "-u" "root" "-i" "bash" "-c")
  SSH_CMD_PFX=(sudo -u root -i bash -c)
fi
   echo "$0.$LINENO ck srvr= $SRVR"
#MY_IP=$(ifconfig |grep 192.168|awk '{printf("%s\n", $2);exit(0);}')
if [ "$SRVR" != "" ]; then
   echo "$0.$LINENO ck srvr= $SRVR"
MY_IP_NET_DEV=($(ifconfig | awk '
   /^ / {
    if ($1 == "inet" && dev != "") {printf("%s\n%s\n", $2, dev);}
   }
   /^[^ ]/{
     v = $1; gsub(/:/,"",v); dev = "";
     if (index($0,"LOOPBACK") == 0 && index($0, "RUNNING") > 0) {
       dev = v;
     }
   }'
   ))
   echo "$0.$LINENO my_ip_net_dev arr= ${MY_IP_NET_DEV[@]}"
   for ((i=0; i < ${#MY_IP_NET_DEV[@]}; i+= 2)); do
     if [ "${MY_IP_NET_DEV[$i]}" == "$SRVR" ]; then
       j=$((i+1))
       TRY_DEV="${MY_IP_NET_DEV[$j]}"
       if [ "$TRY_DEV" == "" ]; then
         echo "$0.$LINENO missed network device for ip_address $SRVR. Bye"
         echo "$0.$LINENO list of ip_addr and devices= ${MY_IP_NET_DEV[@]}. ifconfig output:"
         ifconfig
         exit 1
       fi
       NET_DEV=$TRY_DEV
       MY_IP=$SRVR
       echo "$0.$LINENO my_ip= $MY_IP"
       break
     fi
   done
   
else
MY_IP=$(ifconfig |grep 192.168|awk '{printf("%s\n", $2);exit(0);}')
fi
#echo "$0.$LINENO bye"
#exit 1
HST=192.168.1.168 # brc
PAIRS=()
PAIRS+=(129.213.117.92 10.0.1.103) # 
PAIRS+=(192.168.1.187 192.168.1.130) # 
PAIRS+=(192.168.1.96  192.168.1.168) # 
PAIRS+=(192.168.1.119 192.168.1.55 ) # 
PAIRS+=(192.168.1.147 192.168.1.88 ) # 
#PAIRS+=(192.168.1.147 192.168.1.88 ) # 
PAIRS+=(192.168.1.162 192.168.1.110 ) # 
if [[ "$SRVR" != "" ]] && [[ "$CLNT" != "" ]]; then
  PAIRS=($SRVR $CLNT)
fi
for ((i=0; i < ${#PAIRS[@]}; i+=2)); do
  j=$((i+1))
  if [[ "$MY_IP" == "${PAIRS[$i]}" ]] || [[ "$MY_IP" == "${PAIRS[$j]}" ]]; then
    if [[ "$MY_IP" == "${PAIRS[$i]}" ]]; then
      OTHER=${PAIRS[$j]}
    else
      OTHER=${PAIRS[$i]}
    fi
    break
  fi
done
if [[ "$CLNT" == "" ]] && [[ "$OTHER" != "" ]]; then
  CLNT=$OTHER
fi
if [[ "$SRVR" == "" ]] && [[ "$MY_IP" != "" ]]; then
  SRVR=$MY_IP
fi
if [ "$OTHER" == "" ]; then
  echo "$0.$LINENO didn't find host client pair in PAIRS array for ip_addr= $MY_IP"
  exit 1
fi
HST=$OTHER
echo "$0.$LINENO srvr_ip= $SRVR clnt= $CLNT"
#exit 1
if [ "$XFER_IN" == "1" ]; then
      CK_GCC=$(command -v gcc)
      if [ "$CK_GCC" != "" ]; then
        for i in tcp_client tcp_server tcp_sort_latency get_tsc; do
          gcc -O $i.c -static -o $i.x
          RC=$?
          if [ "$RC" != "0" ]; then
            echo "$0.$LINENO gcc rc= $? for $i.c"
            exit 1
          fi
          if [[ "$VERBOSE" -gt "0" ]]; then
            echo "$0.$LINENO build of $i.x got RC= $RC"
          fi
        done
      fi
      BSNM=$(basename $SCR_DIR)
      cd ..; tar czf $SCR_DIR/tmp/proj_net_bw_lat_sml.tar.gz ${BSNM}/quick_net.sh ${BSNM}/*.c ${BSNM}/*.x ${BSNM}/set_eth0.sh ${BSNM}/mk_tar_file.sh ${BSNM}/get_nic_node_hi_lo_cpu.sh ${BSNM}/do_tcp_client_server.sh ${BSNM}/rd_spin_freq.sh ${BSNM}/get_new_pckts_frames_MBs_int.sh ${BSNM}/mk_irq_smp_affinity.sh ${BSNM}/rd_proc_stat.sh ${BSNM}/extract_tcp_stats.sh
      cd $SCR_DIR
      echo "$0.$LINENO scp tmp/proj_net_bw_lat_sml.tar.gz ${USER}@$OTHER:/tmp"
                       scp tmp/proj_net_bw_lat_sml.tar.gz ${USER}@$OTHER:/tmp
      #echo $0.$LINENO ssh ${USER}@$OTHER "sudo -u root -i bash -c \"cd /root; tar xzf /tmp/proj_net_bw_lat_sml.tar.gz\""
      #ssh -t ${USER}@$OTHER "sudo -u root -i bash -c \"cd /root; tar xzf /tmp/proj_net_bw_lat_sml.tar.gz\""
      #ssh -t ${USER}@$OTHER sudo -u root -i bash -c "cd /root; tar xzf /tmp/proj_net_bw_lat_sml.tar.gz"
      #ssh -t ${USER}@$OTHER "${SSH_CMD_PFX[@]} \"cd /root; tar xzf /tmp/proj_net_bw_lat_sml.tar.gz; whoami; pwd; ls -l\""
      #echo $0.$LINENO ssh -t ${USER}@$OTHER "${SSH_CMD_PFX[@]} $CMD"
      CMD=$(printf "%q" "cd /root; tar xzf /tmp/proj_net_bw_lat_sml.tar.gz; whoami; pwd")
      echo $0.$LINENO ssh -t ${USER}@$OTHER "${SSH_CMD_PFX[@]} $CMD"
                      ssh -t ${USER}@$OTHER "${SSH_CMD_PFX[@]} $CMD"
  echo "$0.$LINENO did build and transfer to $OTHER. bye"
fi
echo "$0.$LINENO ck scp"
#exit 1

CMD=$(printf "%q" "cd $SCR_DIR; $SCR_DIR/set_eth0.sh -c cfg_qmax; $SCR_DIR/../60secs/set_freq.sh -g performance")
echo $0.$LINENO try ssh -t ${USER}@$OTHER "${SSH_CMD_PFX[@]} $CMD"
                    ssh -t ${USER}@$OTHER "${SSH_CMD_PFX[@]} $CMD"
echo $0.$LINENO did ssh -t ${USER}@$OTHER "${SSH_CMD_PFX[@]} $CMD"
#ssh -t ${USER}@$OTHER "cd $SCR_DIR; $SCR_DIR/set_eth0.sh -c cfg_qmax; $SCR_DIR/../60secs/set_freq.sh -g performance"
$SCR_DIR/../60secs/set_freq.sh -g performance

echo "$0.$LINENO got to here"
#exit 0

if [ "1" == "2" ]; then
if [ "$XFER_IN" == "0" ]; then
TAR=$($SCR_DIR/mk_tar_file.sh | awk '/^proj_net/{print $0;}')
scp ../$TAR ${USER}@$OTHER:
CMD=$(printf "%q" "tar xzf $TAR")
ssh -t ${USER}@$OTHER "${SSH_CMD_PFX[@]} $CMD"
#ssh ${USER}@$OTHER "tar xzf $TAR"
echo "$0.$LINENO did tar $TAR to ${USER}@$OTHER and untar"
fi
fi
#exit 1
if [ ! -d tmp ]; then
  mkdir tmp
fi
if [[ "$ODIR" != "" ]] && [[ ! -d "$ODIR" ]]; then
  mkdir -p $ODIR
fi

OPT_D=
OPT_D="quickack=0xf_csv1"
OPT_D="nodelay=0x4_csv1"
OPT_D="nodelay=0x4_csv1,no_lat"
OPT_D="nodelay=0x4_csv1,quickack=0x4_csv1,no_lat,bw_altdir=1"
OPT_D="nodelay=0x4_csv1,quickack=0x4_csv1,no_lat"
OPT_D="no_lat"
OUT="1 2 3 4 6 8 10 15 20"
OUT=1
TYP=bw
TYP_LST=lat
if [ "$TYP_TST_IN" != "" ]; then
  TYP_LST=$TYP_TST_IN
fi
for TYP in $TYP_LST; do
  if [ "$TYP" == "bw" ]; then
    OPT_D="no_lat,bw_altdir=1"
    OPT_D="bw_altdir=1"  # for bw
    N_LST=$N_LST_BW
    OUT="1"
    LIMIT_BW=" -B $BW_MAX "
  else
    N_LST=$N_LST_LAT
    OPT_D=
    OPT_D="quickack=0x4_csv1,no_lat" # skip latency (can take awhile and scripts have to exclude post-processing time from performance measurements
    OPT_D="quickack=0x4_csv1" 
    OUT="1"
    LIMIT_BW=
  fi
  if [ "$TCP_OPTIONS" != "" ]; then
    CK_FOR_CMA=${TCP_OPTIONS:0:1}
    if [ "$CK_FOR_CMA" == "," ]; then
      if [ "$OPT_D" == "" ]; then
        OPT_D="${TCP_OPTIONS:1}"
      else
        OPT_D="${OPT_D}${TCP_OPTIONS}"
      fi
    else
     OPT_D="${TCP_OPTIONS}"
    fi
  fi
  if [ "$OPT_D" != "" ]; then
    OPT_D=" -D $OPT_D "
  fi
  echo "$0.$LINENO opt_d= $OPT_D"
  #exit 1
  N_MIN=$(echo "$N_LST"|awk '{print $1;}')
  N_MAX=$(echo "$N_LST"|awk '{print $NF;}')
  Q_LST="cfg_q8 cfg_q12 cfg_q24 cfg_q48"
  Q_LST="cfg_q8 cfg_q48"
  
  Q_LST="cfg_q48"
  BEG_LST="24 36"
  BEG_LST="24"
  LAT_CPU_STR=$($SCR_DIR/get_nic_node_hi_lo_cpu.sh $NET_DEV | grep num_cpus)
  #./get_nic_node_hi_lo_cpu.sh.37 num_cpus= 48 eth_numa_node= 0 hi= 24 lo= 36
  LAT_HI=$(echo $LAT_CPU_STR | awk '/num_cpus/{print $7;}')
  LAT_LO=$(echo $LAT_CPU_STR | awk '/num_cpus/{print $9;}')
  NUM_CPUS=$(echo $LAT_CPU_STR | awk '/num_cpus/{print $3;}')
  if [ "$LAT_CPU_IN" != "" ]; then
    BEG_LST=$(echo $LAT_CPU_IN | awk -v hi="$LAT_HI" -v lo="$LAT_LO" '{gsub(/lo/, lo, $0); gsub(/hi/, hi, $0); print $0;}')
    #BEG_LST=$LAT_CPU_IN
  fi
  #echo "$0.$LINENO BEG_LST= $BEG_LST"
  #exit 1
  TM=300
  TM=100
  TM=20
  if [ "$TM_RUN" != "" ]; then
    TM=$TM_RUN
  fi
  
  if [ "$Q_IN" != "" ]; then
    Q_LST=$Q_IN
  fi
  #echo "$0.$LINENO N_LST bef= $N_LST"
  if [ "$N_START_IN" != "" ]; then
    N_LST=$(echo "$N_START_IN" | awk -v mx="$N_MAX" -v mn="$N_MIN" '{gsub(/min/, mn, $0); gsub(/max/, mx, $0); print $0;}')
    #N_LST=$N_START_IN
  fi
  #echo "$0.$LINENO N_LST aft= $N_LST"
  #exit 1
  
  for Q in $Q_LST; do
    if [[ "$Q" == *"cfg_"* ]]; then
      $SCR_DIR/set_eth0.sh -c ${Q}
    else
      $SCR_DIR/set_eth0.sh -c cfg_q${Q}
    fi
    $SCR_DIR/set_eth0.sh -c get_cur_str  # get current settings string
    for CPU_BEG in $BEG_LST; do
      for N in $N_LST; do
        for i in $OUT; do
          if [ "$GOT_QUIT" == "1" ]; then
            pkill -2 tcp_server.x
            echo "$0.$LINENO got quit. bye"
            exit 1
          fi
          echo "____ i= $i N= $N typ= $TYP ____"
          echo $SCR_DIR/do_tcp_client_server.sh -C $CLNT -S $SRVR  -s $MSG_LEN -N $NET_DEV -n $N -t $TM -l $CPU_BEG -d $ODIR  -m server  $LIMIT_BW  -p $PORT -o $i $OPT_D -x -u $USER >&2
          echo $SCR_DIR/do_tcp_client_server.sh -C $CLNT -S $SRVR  -s $MSG_LEN -N $NET_DEV  -n $N -t $TM -l $CPU_BEG -d $ODIR  -m server  $LIMIT_BW  -p $PORT -o $i $OPT_D -x -u $USER
               $SCR_DIR/do_tcp_client_server.sh -C $CLNT -S $SRVR  -s $MSG_LEN -N $NET_DEV -n $N -t $TM -l $CPU_BEG -d $ODIR  -m server  $LIMIT_BW  -p $PORT -o $i $OPT_D -x -u $USER
          $SCR_DIR/get_new_pckts_frames_MBs_int.sh -N $NET_DEV -a read -d $ODIR -f tmp.txt -s sum.txt
          if [[ "$OPT_D" != *"no_lat"* ]]; then
            if [ "$GOT_QUIT" == "1" ]; then
              echo "$0.$LINENO got quit. bye"
              exit 1
            fi
            $SCR_DIR/do_tcp_client_server.sh -C $CLNT -S $SRVR  -s $MSG_LEN -N $NET_DEV -n $N -t $TM -l $CPU_BEG -d $ODIR -m latency  -p $PORT -o $i -u $USER
          fi
        done  # OUTSTANDING
      done # N_LST
    done # BEG_LST
  done # Q_LST
done  # TST_TYP

if [[ "$BOTH_IN" == "1" ]] && [[ "$TYP_NIC" == "brc" ]]; then
  echo "$0.$LINENO ssh -t -n ${USER}@$OTHER \"cd $SCR_DIR; nohup ${QT_ARR[@]} &\""
  CMD=$(printf "%q" "cd $SCR_DIR; nohup ${QT_ARR[@]} &")
  ssh -t -n ${USER}@$OTHER "${SSH_CMD_PFX[@]} $CMD"
  #ssh -t -n ${USER}@$OTHER "cd $SCR_DIR; nohup ${QT_ARR[@]} &"
  echo "$0.$LINENO done"
fi
#sysctl -w net.ipv4.tcp_low_latency=0  # reset
#$SCR_DIR/set_eth0.sh -c cfg_q8
echo "$0.$LINENO all done. bye"
echo "$0.$LINENO all done. bye" >&2
$SCR_DIR/set_eth0.sh -c $TYP_NIC
