#!/usr/bin/env bash

IFL=qq2.txt
if [ "$1" != "" ]; then
  IFL=$1
fi
INT=hosts_intel2.lst
AMD=hosts_amd2.lst
RT_ODIR=qq2_dirs
LAST_COMMENT="# redo box1 brc & mlx. box1 brc new firmware. 1 port. no spin. client at max_q_sz"
ILST="4 1"
ALST="1"
ILST="3 0"
ALST="0"
ILST="4 3 1 0"
ALST="1 0"

j=-1;
for mm in $INT $AMD; do
  hlst=$ILST
  if [[ "$mm" == "$AMD" ]]; then
    hlst=$ALST
  fi
  for h in $hlst; do
    HST=$(./install_and_run_on_cloud.sh -l $mm -N $h -r show_host_list |awk '/show_host_list=/{print $3}')
    LN=$(./install_and_run_on_cloud.sh -l $mm -N $h -r show_host_line |awk '/show_host_line=/{print $0}' | sed 's/.*show_host_line= / /')
    j=$((j+1))
    AHST[$j]=$HST
    ALN[$j]="$LN"
    ODIR=$RT_ODIR/$HST
    ADIR[$j]=$ODIR
    mkdir -p $ODIR
    echo "$LN" > $ODIR/host.txt
    scp root@$HST:proj_net_bw_lat/$IFL $ODIR/
    awk -v arg1="$1" -v cmnt="$LAST_COMMENT" '
      {
        if (arg1 != "" && index($0, "QQ_") != 1) {
          next;
        }
      }
      /^#/ {
        delete sv;
        n=0;
        sv[++n] = $0;
        sv[++n] = cmnt;
        next;
      }
      { sv[++n] = $0;}
      END{
        for (i=1; i <= n; i++) {
          printf("%s\n", sv[i]);
        }
      }' $ODIR/$IFL > $ODIR/qq2_shrt.txt
    echo hst $h= $HST ln= $LN
  done
done
for ((i=0; i <= $j; i++)); do
  sku_nic[$i]=$(echo ${ALN[$i]} | awk '
    /5318Y CPU/{sku="box2_icx";}
    /4214 CPU/{sku="box1_csx";}
    /EPYC 7643/{sku="box3_mln";}
    /Mellanox/{nic="mlx";}
    /Broadcom/{nic="brc";}
    END{printf("%s_%s", sku, nic);}')
  echo "sku_nic[$i]= ${sku_nic[$i]}"
done
FL=$RT_ODIR/file_list.txt
if [ -e $FL ]; then
  rm $FL
fi
for ((i=0; i <= $j; i++)); do
  echo "${sku_nic[$i]} ${ADIR[$i]}/qq2_shrt.txt" >> $FL
done
cat $FL
exit 0

