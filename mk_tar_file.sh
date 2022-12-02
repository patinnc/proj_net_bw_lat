#!/usr/bin/env bash

SCR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $SCR_DIR/..
DT=$(date +"%Y%m%d_%H%M%S")

PROJ="proj_net_bw_lat"
tar czf ${PROJ}_${DT}.tar.gz ${PROJ}/*.sh ${PROJ}/*.c ${PROJ}/*.x ${PROJ}/*.stap ${PROJ}/iperf3 ${PROJ}/netperf ${PROJ}/netserver ${PROJ}/README.md
echo ${PROJ}_${DT}.tar.gz
ls -l ${PROJ}_${DT}.tar.gz
exit 0


