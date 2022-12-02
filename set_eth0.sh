#!/usr/bin/env bash

# this script sets the NIC parameters. 
# ./set_eth0.sh brc # sets NIC to broadcom default
# ./set_eth0.sh mlx # sets NIC to mellanox default
# ./set_eth0.sh cfg_qXX sets q size to XX
# 
# ./set_eth0.sh get_cur_str  # get current settings string
# ./set_eth0.sh.20 typ= brc
# cfg_str cfg_q8_a00_ru10_rf15_rif1_tu28_tf30_tif2
# ./set_eth0.sh get_def_str  # get default settings string
# ./set_eth0.sh.20 typ= brc
# cfg_str cfg_q8_a00_ru10_rf15_rif1_tu28_tf30_tif2

CFG_IN=
CFG_IN2=
DEV_IN="eth0"
IFS_SV=$IFS
TYP=$(lspci|grep Ether| awk '/Mellan/{printf("mlx");exit(0);}/Broadcom/{printf("brc");exit(0);}')
DEF_FILE=/root/${TYP}_def_settings_${DEV_IN}.txt
CUR_FILE=/tmp/${TYP}_cur_settings_${DEV_IN}.txt
NET_DEVS=($(ip link | grep -v mgmt| awk '/ state UP /{v=$2;gsub(/:/,"",v); printf("%s\n",v);}'))
DEV_IN=${NET_DEVS[0]}

RET_CD=0
ck_last_rc() {
   local RC=$1
   local FROM=$2
   local STR=$3
   if [[ $RC -gt 0 ]] || [[ "$GOT_QUIT" == "1" ]]; then
      echo "$0: got non-zero RC=$RC at $LINENO. called from line $FROM. GOT_QUIT= $GOT_QUIT str= $STR" 1>&2
      RET_CD=1
      #kill -term $$ # send this program a terminate signal
      if [[ "$GOT_QUIT" == "1" ]]; then
        exit 1
      fi
      exit $RC
   fi
}

while getopts "hvc:C:d:" opt; do
  case ${opt} in
    c )
      CFG_IN=$OPTARG
      ;;
    C )
      CFG_IN2=$OPTARG
      ;;
    d )
      DEV_IN=$OPTARG
      DEF_FILE=/root/${TYP}_def_settings_${DEV_IN}.txt
      CUR_FILE=/tmp/${TYP}_cur_settings_${DEV_IN}.txt
      ;;
    v )
      VERBOSE=$((VERBOSE+1))
      ;;
    h )
      echo "$0 run set_eth0.sh to get network dev config or change the config"
      echo "Usage: $0 [ -v ] "
      echo "   -c config_in"
      echo "      config_in can be prebuilt cmds or a config_string"
      echo "        prebuilt: get_def_str get default config string based on default file $DEF_FILE (created by this script)"
      echo "        prebuilt: get_cur_str get current config string based on current file $CUR_FILE (created by this script)"
      echo "        prebuilt: get_def_or_cur_str  get_def_str (if def file exists) or get_cur_str"
      echo "        prebuilt: brc reset to broadcom defaults (must be brc NIC and have defaults file)"
      echo "        prebuilt: mlx reset to mellanox defaults (must be mlx NIC and have defaults file)"
      echo "   -d device  default is ${NET_DEVS[0]}. valid list= ${NET_DEVS[@]}"
      echo "   -v verbose mode"
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

if [ "$CFG_IN" == "" ]; then
  echo "$0.$LINENO missing -c config option"
  exit 1
fi
got_it=0
for ((i=0; i < ${#NET_DEVS[@]}; i++)); do
  if [ "$DEV_IN" == "${NET_DEVS[$i]}" ]; then
    got_it=1
    break
  fi
done
if [ "$got_it" == "0" ]; then
  echo "$0.$LINENO you entered (or defaulted to) net device= $DEV_IN but that dev is not in the supported list of net devices"
  echo "$0.$LINENO net devices on this host: ${NET_DEVS[@]}  redo with -d net_dev. bye" 
  exit 1
fi


if [ "$CFG_IN" == "dummy" ]; then
  # this is the case where this script calls itself. Don't want to echo arg1 to cfg.log in this case.
  CFG_IN="$CFG_IN2"
  #shift
else
  echo $CFG_IN > cfg.log
fi

if [[ "$CFG_IN" == "brc" ]] && [[ "$TYP" != "brc" ]]; then
  echo "$0.$LINENO got -c $CFG_IN -d $DEV_IN but NIC typ= $TYP so wrong type -c $CFG_IN. bye"
  exit 1
fi
if [[ "$CFG_IN" == "mlx" ]] && [[ "$TYP" != "mlx" ]]; then
  echo "$0.$LINENO got -c $CFG_IN -d $DEV_IN but NIC typ= $TYP so wrong type -c $CFG_IN. bye"
  exit 1
fi
echo "$0.$LINENO typ= $TYP dev= $DEV_IN"
eth_l=$(ethtool -l ${DEV_IN})
eth_c=$(ethtool -c ${DEV_IN})
eth_g=$(ethtool -g ${DEV_IN})
eth_comb_max=$(echo "$eth_l" | awk -v want=1 '/Combined/{++n; if (want==n){printf("%s", $NF);exit(0);}}')
eth_comb_cur=$(echo "$eth_l" | awk -v want=2 '/Combined/{++n; if (want==n){printf("%s", $NF);exit(0);}}')
#echo "$0.$LINENO bye cmb_mx= $eth_comb_max, cmb_cur= $eth_comb_cur"
#exit 1
tot_cpus=$(grep -c processor /proc/cpuinfo)
tot_nodes=$(lscpu | awk '/NUMA node.s.:/{ printf("%s", $3); exit(0); }')
cpus_per_node=$((tot_cpus/tot_nodes))
cores_per_node=$((cpus_per_node/2))
eth_comb_max_cpus=$eth_comb_max
if [[ "$eth_comb_max_cpus" -gt "$tot_cpus" ]]; then
  eth_comb_max_cpus=$tot_cpus
fi

if [ "$CFG_IN" == "nochg" ]; then
  echo "$0.$LINENO nochg so no changes"
  exit 0
fi
  
if [ "$CFG_IN" == "" ]; then
  ethtool -l ${DEV_IN}
  ethtool -c ${DEV_IN}
  ethtool -g ${DEV_IN}
  exit 0
fi
  if [ "$TYP" != "brc" ]; then
    ADAP_TX_ON=on
  else
    ADAP_TX_ON=off
  fi

get_default_from_file() {
  local file=$1
  local area=$2
  local sub_area=$3
  local lkfor=$4
  local fld=$5
  resp=$(awk -v dev_in="$DEV_IN"  -v fld="$fld" -v area="$area" -v sub_area="$sub_area" -v lkfor="$lkfor" '
     BEGIN{
      ln_area = length(area);
      ln_sub_area = length(sub_area);
      ln_lkfor = length(lkfor);
      if (fld == "") { fld= 2; }
     }
     /Channel parameters for .*:|Coalesce parameters for .*:|Ring parameters for .*:|Features for .*:/ {
       ck_dev = " "dev_in":";
       #printf("ck dev_in= \"%s\" str= %s\n", ck_dev, $0) > "/dev/stderr";
       if (index($0, ck_dev) == 0) { next; }
       got_area = 0;
       if (substr($0, 1, ln_area) == area) { got_area = 1; }
       if (ln_sub_area == 0 && got_area == 1) { got_sub_area == 1; }
       #next;
     }
     {
       if (index($0, "\t") > 0) {
         gsub(/\t/, " ", $0);
         $1 = $1;
       }
       pos = index($0, $1);
       if (ln_sub_area > 0 && got_area == 1 && substr($0, pos, ln_sub_area) == sub_area) { got_sub_area = 1; next;}
       if (got_area == 1 && got_sub_area == 1 && substr($0, pos, ln_lkfor) == lkfor) {
          if (fld > NF) { printf("err: area= %s sub_area= %s, lkfor= %s, NF= %s, fld= %d: fld > NF\n", area, sub_area, lkfor, NF, fld) > "/dev/stderr"; printf(""); exit(1); }
          if (index( $(fld+1), "fixed") > 0) {
             printf("fix: area= %s sub_area= %s, lkfor= %s, NF= %s, fld= %d fld is fixed\n", area, sub_area, lkfor, NF, fld) > "/dev/stderr";
             printf("");
             exit(0);
          }
          printf("%s", $fld);
          exit(0);
       }
    }
    ' $file
    ck_last_rc $? $LINENO $file
    )
   echo "$resp"
}
     
CARR=()
CMD=$CFG_IN
  for ((i=0; i < ${#NET_DEVS[@]}; i++)); do
    DEF_FL="/root/${TYP}_def_settings_${NET_DEVS[$i]}.txt"
    CUR_FL="/tmp/${TYP}_cur_settings_${NET_DEVS[$i]}.txt"
    (ethtool -l ${NET_DEVS[$i]}; ethtool -c ${NET_DEVS[$i]}; ethtool -g ${NET_DEVS[$i]}; ethtool -k ${NET_DEVS[$i]}) > $CUR_FL
    if [ ! -e "$DEF_FL" ]; then
      cp $CUR_FL $DEF_FL
    fi
  done
  DEF_FILE=/root/${TYP}_def_settings_${DEV_IN}.txt
  CUR_FILE=/tmp/${TYP}_cur_settings_${DEV_IN}.txt
  if [[ "$TYP" == "brc" ]]; then
    DEF_L_RX=0
    DEF_L_TX=0
    DEF_L_OTH=0
    DEF_L_CMB=8
    DEF_C_ADP_RX=off
    DEF_C_ADP_TX=off
    DEF_C_RX_USECS=10
    DEF_C_RX_FRAME=15
    DEF_C_TX_USECS=28
    DEF_C_TX_FRAME=30
  fi
  if [[ "$TYP" == "mlx" ]]; then
    #DEF_L_RX=0
    #DEF_L_TX=0
    #DEF_L_OTH=0
    #DEF_L_CMB=32
    #DEF_C_ADP_RX=on
    #DEF_C_ADP_TX=off
    #DEF_C_RX_USECS=8
    #DEF_C_RX_FRAME=128
    #DEF_C_TX_USECS=16
    #DEF_C_TX_FRAME=32
    DEF_L_RX=0
    DEF_L_TX=0
    DEF_L_OTH=0
    DEF_L_CMB=63
    DEF_C_ADP_RX=on
    DEF_C_ADP_TX=on
    DEF_C_RX_USECS=8
    DEF_C_RX_FRAME=128
    DEF_C_TX_USECS=8
    DEF_C_TX_FRAME=128
  fi
  CUR_L_RX=$(get_default_from_file $CUR_FILE Channel Current RX: 2)
  CUR_L_TX=$(get_default_from_file $CUR_FILE Channel Current TX: 2)
  CUR_L_OTH=$(get_default_from_file $CUR_FILE Channel Current Other: 2)
  CUR_L_CMB=$(get_default_from_file $CUR_FILE Channel Current Combined: 2)
  CUR_C_ADP_RX=$(get_default_from_file $CUR_FILE Coalesce Coalesce Adaptive 3)
  CUR_C_ADP_TX=$(get_default_from_file $CUR_FILE Coalesce Coalesce Adaptive 5)
  CUR_C_RX_USECS=$(get_default_from_file $CUR_FILE Coalesce Coalesce rx-usecs: 2)
  CUR_C_RX_FRAME=$(get_default_from_file $CUR_FILE Coalesce Coalesce rx-frames: 2)
  CUR_C_TX_USECS=$(get_default_from_file $CUR_FILE Coalesce Coalesce tx-usecs: 2)
  CUR_C_TX_FRAME=$(get_default_from_file $CUR_FILE Coalesce Coalesce tx-frames: 2)
  CUR_C_RX_USECS_IRQ=$(get_default_from_file $CUR_FILE Coalesce Coalesce rx-usecs-irq: 2)
  CUR_C_RX_FRAME_IRQ=$(get_default_from_file $CUR_FILE Coalesce Coalesce rx-frames-irq: 2)
  CUR_C_TX_USECS_IRQ=$(get_default_from_file $CUR_FILE Coalesce Coalesce tx-usecs-irq: 2)
  CUR_C_TX_FRAME_IRQ=$(get_default_from_file $CUR_FILE Coalesce Coalesce tx-frames-irq: 2)
  if [ -e $DEF_FILE ]; then
    DEF_L_RX=$(get_default_from_file $DEF_FILE Channel Current RX: 2)
    DEF_L_TX=$(get_default_from_file $DEF_FILE Channel Current TX: 2)
    DEF_L_OTH=$(get_default_from_file $DEF_FILE Channel Current Other: 2)
    DEF_L_CMB=$(get_default_from_file $DEF_FILE Channel Current Combined: 2)
    DEF_C_ADP_RX=$(get_default_from_file $DEF_FILE Coalesce Coalesce Adaptive 3)
    DEF_C_ADP_TX=$(get_default_from_file $DEF_FILE Coalesce Coalesce Adaptive 5)
    DEF_C_RX_USECS=$(get_default_from_file $DEF_FILE Coalesce Coalesce rx-usecs: 2)
    DEF_C_RX_FRAME=$(get_default_from_file $DEF_FILE Coalesce Coalesce rx-frames: 2)
    DEF_C_TX_USECS=$(get_default_from_file $DEF_FILE Coalesce Coalesce tx-usecs: 2)
    DEF_C_TX_FRAME=$(get_default_from_file $DEF_FILE Coalesce Coalesce tx-frames: 2)
    DEF_C_RX_USECS_IRQ=$(get_default_from_file $DEF_FILE Coalesce Coalesce rx-usecs-irq: 2)
    DEF_C_RX_FRAME_IRQ=$(get_default_from_file $DEF_FILE Coalesce Coalesce rx-frames-irq: 2)
    DEF_C_TX_USECS_IRQ=$(get_default_from_file $DEF_FILE Coalesce Coalesce tx-usecs-irq: 2)
    DEF_C_TX_FRAME_IRQ=$(get_default_from_file $DEF_FILE Coalesce Coalesce tx-frames-irq: 2)
    ADAP_TX_ON=$DEF_C_ADP_TX
  fi
if [[ "$CMD" == "get_def_or_cur_str" ]]; then
  if [[ -e $DEF_FILE ]]; then
    CMD="get_def_str"
  else
    CMD="get_cur_str"
  fi
  build_cfg_str
  exit 0
fi

build_cfg_str() {
  if [[ "$CMD" == "get_cur_str" ]]; then
  local L_CMB=$CUR_L_CMB
  local C_ADP_RX=$CUR_C_ADP_RX
  local C_ADP_TX=$CUR_C_ADP_TX
  local C_RX_USECS=$CUR_C_RX_USECS
  local C_RX_FRAME=$CUR_C_RX_FRAME
  local C_RX_USECS_IRQ=$CUR_C_RX_USECS_IRQ
  local C_RX_FRAME_IRQ=$CUR_C_RX_FRAME_IRQ
  local C_TX_USECS=$CUR_C_TX_USECS
  local C_TX_FRAME=$CUR_C_TX_FRAME
  local C_TX_USECS_IRQ=$CUR_C_TX_USECS_IRQ
  local C_TX_FRAME_IRQ=$CUR_C_TX_FRAME_IRQ
  else
  local L_CMB=$DEF_L_CMB
  local C_ADP_RX=$DEF_C_ADP_RX
  local C_ADP_TX=$DEF_C_ADP_TX
  local C_RX_USECS=$DEF_C_RX_USECS
  local C_RX_FRAME=$DEF_C_RX_FRAME
  local C_RX_USECS_IRQ=$DEF_C_RX_USECS_IRQ
  local C_RX_FRAME_IRQ=$DEF_C_RX_FRAME_IRQ
  local C_TX_USECS=$DEF_C_TX_USECS
  local C_TX_FRAME=$DEF_C_TX_FRAME
  local C_TX_USECS_IRQ=$DEF_C_TX_USECS_IRQ
  local C_TX_FRAME_IRQ=$DEF_C_TX_FRAME_IRQ
  fi

  CFG="cfg_q${L_CMB}_a"
  if [ "$C_ADP_RX" == "off" ]; then
    CFG="${CFG}0"
  else
    CFG="${CFG}1"
  fi
  if [ "$C_ADP_TX" == "off" ]; then
    CFG="${CFG}0"
  else
    CFG="${CFG}1"
  fi
  RUI_STR=
  if [ "$C_RX_USECS_IRQ" != "n/a" ]; then
    RUI_STR="riu${C_RX_USECS_IRQ}_"
  fi
  TUI_STR=
  if [ "$C_TX_USECS_IRQ" != "n/a" ]; then
    TUI_STR="tiu${C_TX_USECS_IRQ}_"
  fi
  RIF_STR=
  if [ "$C_RX_FRAME_IRQ" != "n/a" ]; then
    RIF_STR="rif${C_RX_FRAME_IRQ}"
  fi
  TIF_STR=
  if [ "$C_TX_FRAME_IRQ" != "n/a" ]; then
    TIF_STR="tif${C_TX_FRAME_IRQ}"
  fi
  CFG="${CFG}_ru${C_RX_USECS}_rf${C_RX_FRAME}_${RIU_STR}${RIF_STR}"
  CFG="${CFG}_tu${C_TX_USECS}_tf${C_TX_FRAME}_${TIU_STR}${TIF_STR}"
  CFG=$(echo "$CFG" | sed 's/__/_/g;s/_$//')
  echo "cfg_str $CFG"
}

if [[ "$CMD" == "get_cur_str" ]]; then
  build_cfg_str
  exit 0
fi
if [[ "$CMD" == "get_def_str" ]]; then
  if [[ ! -e $DEF_FILE ]]; then
    echo "$0.$LINENO cmd= $CMD but didn't find default file $DEF_FILE"
    exit 0
  fi
  build_cfg_str
  exit 0
fi
if [[ "$CMD" == "" ]] || [[ "$CMD" == "brc" ]] || [[ "$CMD" == "mlx" ]]; then
  echo "$0.$LINENO got def L_rx = $DEF_L_RX tx= $DEF_L_TX othr= $DEF_L_OTH combined= $DEF_L_CMB adp_rx= $DEF_C_ADP_RX adp_tx= $DEF_C_ADP_TX, rx_usec= $DEF_C_RX_USECS, rx_frames= $DEF_C_RX_FRAME tx_usec= $DEF_C_TX_USECS, tx_frames= $DEF_C_TX_FRAME"
  echo "$0.$LINENO got cur L_rx = $CUR_L_RX tx= $CUR_L_TX othr= $CUR_L_OTH combined= $CUR_L_CMB adp_rx= $CUR_C_ADP_RX adp_tx= $CUR_C_ADP_TX, rx_usec= $CUR_C_RX_USECS, rx_frames= $CUR_C_RX_FRAME tx_usec= $CUR_C_TX_USECS, tx_frames= $CUR_C_TX_FRAME"
  echo "$0.$LINENO got def rx_usec_irq= $DEF_C_RX_USECS_IRQ, rx_frames_irq= $DEF_C_RX_FRAME_IRQ tx_usec_irq= $DEF_C_TX_USECS_IRQ, tx_frames_irq= $DEF_C_TX_FRAME_IRQ"
  echo "$0.$LINENO got cur rx_usec_irq= $CUR_C_RX_USECS_IRQ, rx_frames_irq= $CUR_C_RX_FRAME_IRQ tx_usec_irq= $CUR_C_TX_USECS_IRQ, tx_frames_irq= $CUR_C_TX_FRAME_IRQ"
  echo "$0.$LINENO DEF_L_CMB= $DEF_L_CMB"
  if [[ "$2" == "" ]] || [[ $2 =~ "l" ]]; then
    V=$DEF_L_RX
    X=$CUR_L_RX
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -L ${DEV_IN} rx $V")
    fi
    V=$DEF_L_TX
    X=$CUR_L_TX
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -L ${DEV_IN} tx $V")
    fi
    V=$DEF_L_OTH
    X=$CUR_L_OTH
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -L ${DEV_IN} other $V")
    fi
    V=$DEF_L_CMB
    X=$CUR_L_CMB
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -L ${DEV_IN} combined $V")
    fi
  fi
  if [[ "$2" == "" ]] || [[ $2 =~ "c" ]]; then
    V=$DEF_C_ADP_RX
    X=$CUR_C_ADP_RX
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} adaptive-rx $V")
    fi
    V=$DEF_C_ADP_TX
    X=$CUR_C_ADP_TX
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} adaptive-tx $V")
    fi
    #CARR+=("ethtool -C ${DEV_IN} stats-block-usecs 1000000")
    #CARR+=("ethtool -C ${DEV_IN} sample-interval 0")
    #CARR+=("ethtool -C ${DEV_IN} pkt-rate-low 0")
    #CARR+=("ethtool -C ${DEV_IN} pkt-rate-high 0")
    V=$DEF_C_RX_USECS
    X=$CUR_C_RX_USECS
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} rx-usecs $V")
    fi
    V=$DEF_C_RX_FRAME
    X=$CUR_C_RX_FRAME
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} rx-frames $V")
    fi
    #CARR+=("ethtool -C ${DEV_IN} rx-usecs-irq 1")
    #CARR+=("ethtool -C ${DEV_IN} rx-frames-irq 1")
    V=$DEF_C_TX_USECS
    X=$CUR_C_TX_USECS
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} tx-usecs $V")
    fi
    V=$DEF_C_TX_FRAME
    X=$CUR_C_TX_FRAME
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} tx-frames $V")
    fi
    V=$DEF_C_RX_USECS_IRQ
    X=$CUR_C_RX_USECS_IRQ
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} rx-usecs-irq $V")
    fi
    V=$DEF_C_RX_FRAME_IRQ
    X=$CUR_C_RX_FRAME_IRQ
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} rx-frames-irq $V")
    fi
    V=$DEF_C_TX_USECS_IRQ
    X=$CUR_C_TX_USECS_IRQ
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} tx-usecs-irq $V")
    fi
    V=$DEF_C_TX_FRAME_IRQ
    X=$CUR_C_TX_FRAME_IRQ
    if [[ "$V" != "" ]] && [[ "$V" != "$X" ]]; then
      CARR+=("ethtool -C ${DEV_IN} tx-frames-irq $V")
    fi
    #CARR+=("ethtool -C ${DEV_IN} tx-usecs-irq 2")
    #CARR+=("ethtool -C ${DEV_IN} tx-frames-irq 2")
    #CARR+=("ethtool -C ${DEV_IN} rx-usecs-low 0")
    #CARR+=("ethtool -C ${DEV_IN} rx-frames-low 0")
    #CARR+=("ethtool -C ${DEV_IN} tx-usecs-low 0")
    #CARR+=("ethtool -C ${DEV_IN} tx-frames-low 0")
    #CARR+=("ethtool -C ${DEV_IN} rx-usecs-high 0")
    #CARR+=("ethtool -C ${DEV_IN} rx-frames-high 0")
    #CARR+=("ethtool -C ${DEV_IN} tx-usecs-high 0")
    #CARR+=("ethtool -C ${DEV_IN} tx-frames-high 0")
  fi
fi


do_cmds() {
  echo "$0.$LINENO do cmds $1 $2"
  for ((i=0; i < ${#CARR[@]}; i++)); do
    RESP=$(${CARR[$i]} 2> /dev/null)
    #RESP=$(${CARR[$i]})
    RC=$?
    if [[ "$RC" == "80" ]]; then
     echo "no change ${CARR[$i]}"
    fi
    if [[ "$RC" == "1" ]]; then
     echo "error     ${CARR[$i]}"
    fi
    if [[ "$RC" == "0" ]]; then
     echo "no error  ${CARR[$i]}"
    fi
    if [[ "$RC" != "80" ]] && [[ "$RC" != "1" ]] && [[ "$RC" != "0" ]]; then
      echo RC[$i]= $RC  ${CARR[$i]}
    fi
  done
}

do_cmds $CFG_IN $2

CARR=()

if [[ "$CFG_IN" == "cfg"* ]]; then
 $0 -c dummy -C $TYP -d $DEV_IN
 echo "start settings for $CFG_IN"
 if [[ "$CFG_IN" == "cfg_q"* ]]; then

  echo "$0.$LINENO CMDS= awk -v typ=$TYP -v cfg_in=$CFG_IN"
  CMDS=()
  IFS=$'\n' CMDS+=($(awk -v dev_in="$DEV_IN" -v eth_comb_max_cpus="$eth_comb_max_cpus" -v typ="$TYP" -v cfg_in="$CFG_IN" '
    BEGIN{
      n = split(cfg_in, arr, "_");
      #printf("n= %s\n", n);
      adap="";
      #ru = "";
      for (i=2; i <= n; i++) {
        if (substr(arr[i], 1, 1) == "q") {
          if (tolower(substr(arr[i], 2)) == "maxcpus" || tolower(substr(arr[i], 2)) == "max") {
             arr[i] = "q" eth_comb_max_cpus;
          }
          printf("ethtool -L %s combined %s\n", dev_in, substr(arr[i], 2));
          continue;
        }
        if (substr(arr[i], 1, 1) == "a") {
          v = substr(arr[i], 2, 1);
          if (v == "1") { v = "on" } else { v = "off"; }
          #printf("ethtool -C %s adaptive-rx %s\n", dev_in, v);
          adap = adap " adaptive-rx " v;
          v = substr(arr[i], 3, 1);
          if (v == "1") { v = "on" } else { v = "off"; }
          adap = adap " adaptive-tx " v;
          #printf("ethtool -C %s adaptive-tx %s\n", dev_in, v);
          # I dont think we can change tx on brc (and maybe not on mlx) so just dont use tx setting (if present)
          continue
        }
        if (substr(arr[i], 1, 2) == "ru") {
          v = substr(arr[i], 3);
          adap = adap " rx-usecs " v;
          #printf("ethtool -C %s rx-usecs %s\n", dev_in, v);
          continue
        }
        if (substr(arr[i], 1, 2) == "rf") {
          v = substr(arr[i], 3);
          adap = adap " rx-frames " v;
          #printf("ethtool -C %s rx-frames %s\n", dev_in, v);
          continue
        }
        if (substr(arr[i], 1, 3) == "riu") {
          v = substr(arr[i], 4);
          adap = adap " rx-usecs-irq " v;
          #printf("ethtool -C %s rx-usecs-irq %s\n", dev_in, v);
          continue
        }
        if (substr(arr[i], 1, 3) == "rif") {
          v = substr(arr[i], 4);
          adap = adap " rx-frames-irq " v;
          #printf("ethtool -C %s rx-frames-irq %s\n", dev_in, v);
          continue
        }
        if (substr(arr[i], 1, 2) == "tu") {
          v = substr(arr[i], 3);
          adap = adap " tx-usecs " v;
          #printf("ethtool -C %s tx-usecs %s\n", dev_in, v);
          continue
        }
        if (substr(arr[i], 1, 2) == "tf") {
          v = substr(arr[i], 3);
          adap = adap " tx-frames " v;
          #printf("ethtool -C %s tx-frames %s\n", dev_in, v);
          continue
        }
        if (substr(arr[i], 1, 3) == "tiu") {
          v = substr(arr[i], 4);
          adap = adap " tx-usecs-irq " v;
          #printf("ethtool -C %s tx-usecs-irq %s\n", dev_in, v);
          continue
        }
        if (substr(arr[i], 1, 3) == "tif") {
          v = substr(arr[i], 4);
          adap = adap " tx-frames-irq " v;
          #printf("ethtool -C %s tx-frames-irq %s\n", dev_in, v);
          continue
        }
      }
      if (adap != "") {
        printf("ethtool -C %s %s\n", dev_in, adap);
      }
      exit(0);
    }'
    ck_last_rc $? $LINENO bb
    ))
  IFS=$IFS_SV
  echo "$0.$LINENO num= ${#CMDS[@]}, elem: ${CMDS[@]}"
    for ((i=0; i < ${#CMDS[@]}; i++)); do
      #echo "$0.$LINENO elem[$i]: ${CMDS[$i]}"
      CARR+=("${CMDS[$i]}")
    done
    #for ((i=0; i < ${#CARR[@]}; i++)); do
    #  echo "$0.$LINENO carr[$i]: \"${CARR[$i]}\""
    #done
    #exit 0
  #V=${1:5}
  #echo $0.$LINENO carr "ethtool -L ${DEV_IN} combined $V "
  #CARR+=("ethtool -L ${DEV_IN} combined $V ")
  do_cmds $CFG_IN
  exit 0
 fi
 if [[ "${#CARR[@]}" == "0" ]] && [[ "$CFG_IN" != "cfg14" ]]; then
   echo "$0 cfg $CFG_IN has no settings"
   exit 1
 fi
 do_cmds $CFG_IN
fi

exit 0

exit


#ethtool -C|--coalesce devname [adaptive-rx on|off] [adaptive-tx on|off] [rx-usecs N] [rx-frames N] [rx-usecs-irq N] [rx-frames-irq N] [tx-usecs N] [tx-frames N] [tx-usecs-irq N]
#              [tx-frames-irq N] [stats-block-usecs N] [pkt-rate-low N] [rx-usecs-low N] [rx-frames-low N] [tx-usecs-low N] [tx-frames-low N] [pkt-rate-high N] [rx-usecs-high N]
#              [rx-frames-high N] [tx-usecs-high N] [tx-frames-high N] [sample-interval N]
#Ring parameters for eth0:
#Pre-set maximums:
#RX:		2047
#RX Mini:	0
#RX Jumbo:	8191
#TX:		2047
#Current hardware settings:
#RX:		511
#RX Mini:	0
#RX Jumbo:	2044
#TX:		511
#ethtool -G|--set-ring devname [rx N] [rx-mini N] [rx-jumbo N] [tx N]


Channel parameters		
	broadcom	mellanox
chnl_max RX	37	0
chnl_max TX	37	0
chnl_max Other	0	0
chnl_max Combined	74	63
chnl_cur RX	0	0
chnl_cur TX	0	0
chnl_cur Other	0	0
chnl_cur Combined	8	63
		
Coalesce parameters		
	broadcom	mellanox
Adaptive_RX	off	on
Adaptive_TX	off	on
stats-block-usecs	1000000	0
sample-interval	0	0
pkt-rate-low	0	0
pkt-rate-high	0	0
rx-usecs	10	8
rx-frames	15	128
rx-usecs-irq	1	0
rx-frames-irq	1	0
tx-usecs	28	8
tx-frames	30	128
tx-usecs-irq	2	0
tx-frames-irq	2	0
rx-usecs-low	0	0
rx-frame-low	0	0
tx-usecs-low	0	0
tx-frame-low	0	0
rx-usecs-high	0	0
rx-frame-high	0	0
tx-usecs-high	0	0
tx-frame-high	0	0
		
Ring parameters		
	broadcom	mellanox
ring_max RX	2047	8192
ring_max TX	2047	8192
ring_cur RX	511	1024
ring_cur TX	511	1024
