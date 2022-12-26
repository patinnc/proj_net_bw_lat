#!/usr/bin/env bash

INF=tmpac.txt
#echo "$0.$LINENO $[*]"
if [[ "$1" != "" ]]; then
  if [[ -e "$1" ]]; then
   INF="$1"
  else
   echo "$0.$LINENO file $1 not found"
   exit 1
  fi
fi
echo "use file= $INF"
VERBOSE=0
if [[ "$2" != "" ]]; then
  VERBOSE=1
fi
ck_last_rc() {
   local RC=$1
   local FROM=$2
   if [ $RC -gt 0 ]; then
      echo "$0: got non-zero RC=$RC at $LINENO. called from line $FROM" > /dev/stderr
      exit $RC
   fi
}

gawk -v verbose="$VERBOSE" '
 BEGIN{
  N=1;
  rc = 0;
  nice = 0;
  #printf("in_file= %s argc= %s\n", ARGV[1], ARGC);
 }
 /^cfg_str / {
   # cfg_q48_a10_ru10_rf15_rif1_tu28_tf30_tif2
   sv_cfg = $2;
 }



 /____ i= /              {
   cfg = sv_cfg;
   if (def_cfg == "") {
     def_cfg = cfg;
     printf("def cfg= %s\n", def_cfg);
     cstr = cfg;
   } else {
     if (cfg != def_cfg) {
     darr_n = split(def_cfg, darr, "_");
     carr_n = split(cfg, carr, "_");
     cstr = "";
     csep = "";
     for (i=2; i <= carr_n; i++) {
       if (darr[i] != carr[i]) {
         cstr = cstr csep carr[i];
         csep = "_";
       }
     }
     #printf("cfg_n= %s\n", cstr);
     }
   }
   outs      = $3;
   if ($4 = "N="){
     N=$5;
   }
   if ($6 = "typ="){
     TYP_IN=$7;
   }
   #printf("outs= %s N= %s typ= %s cfg= %s\n", outs, N, TYP_IN, cfg);
   if(got__ != "" && did_prt[got__] == 0) {
     prt_stats();
     did_prt[got__] = 1;
   }
   prf_busyTL ="";
   ps_busyTL ="";
   got__++;
   did_prt[got__] = 0;
   if (got__ == 1) {
    grp_init_i = outs;
    grp_init_N = N;
    grp_init_typ = TYP_IN;
   }
   if (TYP_IN != typ_in_prev2 || cstr != cstr_prev2) {
     typ_in_prev2 = TYP_IN;
     cstr_prev2 = cstr;
   }
   #if (outs == grp_init_i && N == grp_init_N && TYP_IN == grp_init_typ) {
   #  grp++;
   #  grp_cfg[grp] = cstr;
   #}
 }
 # proc_tot_net_irqs= 23842224.000 net_irqsK/s= 79.474
 /^proc_tot_net_irqs= / {
   net_irqs = $4;
 }
 #perf_stat_all tsc_freq= 2.200 %host_unhalted= 63.605 cpus_busyTL= 3052.814 avg_freq= 2.700 ncpus= 47.996 duration_secs= 19.763
 /^perf_stat_all tsc_freq= / {
   prf_busyTL = $7;
   frq = $9;
   # below assumes perf_stat data appears before the rd_proc_stat.sh output
   nice = 0.0;
 }
 # usr= 191.56 nice= 1795.20 sys= 1600.83 idle= 7.07 iow= 0.00 irq= 0.00 soft= 1205.34 tot= 4800.00 tot_busy= 4792.93 elap_secs= 59.96 tot_busy_no_fctr= 4793.88
 /^usr= .* nice= .* sys= / {
   nice = $4;
 }
 /tot_MB\/s= /           { bw        = $2; }
 /tot_pktsK\/s= /        { pkts_ps   = $2; }
#%idleTL= 3187.267 %busyTL= 1612.733 %alt_busyTL= 1482.183 %usr_sysTL= 979.800 tm= 60.000 num_cpus= 48 tot_intr_Kps= 34.3
 /%idleTL= /             { ps_busyTL  = $6; idle = $2; usr_sys = $8;
   if (NF >= 12) {num_cpus    = $12+0;} else {num_cpus     =0;} 
   if (NF >= 14) {tot_intr_Kps= $14+0;} else {tot_intr_Kps =0;} 
 }
 /tot_cswitch/           { cs        = $3; }
 /DelAck\/s /            { delack    = $2; }
 /extDelAck\/s /         { extdelack = $2; }
 /QuickAckActivated\/s / { quickack  = $2; }
 /AutoCorking\/s /       { cork      = $2; }
 # do_tcp_client_server.sh -C 192.168.1.55 -S 192.168.1.119 -s 1000,1000 -n 1 -t 300 -l 24 -d tmp/tstb1 -m server -p 8000,8000 -o 1 -D quickack=0x4_csv1
 /\/do_tcp_client_server.sh.*-C.*-S.*-s / {
   lat_cpu = "";
   for (i=2; i <= NF; i++) {
     v = $(i+1);
     if ($i == "-l") { lat_cpu = v; break;}
   }
   if (TYP_IN != typ_in_prev || cfg != cfg_prev || lat_cpu != lat_cpu_prev) {
     typ_in_prev = TYP_IN;
     cfg_prev = cfg;
     lat_cpu_prev = lat_cpu;
     grp++;
     grp_cmds_mx[grp] = 0;
     grp_cfg[grp] = cfg;
   }
   gj = ++grp_cmds_mx[grp];
   printf("cmd[%d]= %s grp= %s gj= %s\n", gj, $0, grp, gj);
   #rc = 1; exit(rc);
   tot_rpsK= "unk";
   p50= 0.0;
   p90= 0.0;
   p95= 0.0;
   p99= 0.0;
   # parse do_tcp_client_server.sh cmd line
   typ_tst = "lat";
   for (i=2; i <= NF; i++) {
     v = $(i+1);
     if ($i == "-B") { cmd_ln[grp,gj,"BW_MAX"]   = v; if ((v+0) > 0) { typ_tst = "bw"; }}
     if ($i == "-C") { cmd_ln[grp,gj,"CLNT"]     = v;}
     if ($i == "-D") { cmd_ln[grp,gj,"TCP_NODELAY"] = v;}
     if ($i == "-d") { cmd_ln[grp,gj,"ODIR"]     = v;}
     if ($i == "-l") { cmd_ln[grp,gj,"LAT_CPU"]  = v;}
     if ($i == "-L") { cmd_ln[grp,gj,"LAT_AFT"]  = v;}
     if ($i == "-m") { cmd_ln[grp,gj,"MODE"]     = v;}
     if ($i == "-n") { cmd_ln[grp,gj,"N_START"]  = v;}
     if ($i == "-o") { cmd_ln[grp,gj,"OUTS_REQ"] = v;}
     if ($i == "-p") { cmd_ln[grp,gj,"PORT"]     = v;}
     if ($i == "-s") { cmd_ln[grp,gj,"MSG_LEN"]  = v;}
     if ($i == "-S") { cmd_ln[grp,gj,"SRVR"]     = v;}
     if ($i == "-t") { cmd_ln[grp,gj,"TM_RUN"]   = v;}
     if ($i == "-T") { cmd_ln[grp,gj,"TOT_PKTS"] = v;}
     if ($i == "-z") { cmd_ln[grp,gj,"SKIP_CLIENT_LAT"] = 1;}
   }
 }
 /^softirqsK\/s= / {
   softirqs_Kps = $2;
 }
 /^tot_rpsK= / {
   tot_rpsK= $2;
 }
 /^p50= / {
   p50= $2;
 }
 /^p90= / {
   p90= $2;
 }
 /^p95= / {
   p95= $2;
 }
 /^p99= / {
   p99= $2;
 }

 #/ethtool_S/ {
function prt_stats()
{
   if (got__ == 1) {
     #printf("QQ_HDR cfg_q_sz redis_cpus RPS(k) p50 p90 p99 cfg grp outs bw(MB/s) pktsK/s csK/s %%busyTL pkts/cs busyTL/GBps delack extdelack quickack autocork N cfg\n");
     nh = 0;
     h[++nh]="outs"; h[++nh]="bw(MB/s)"; h[++nh]="pktsK/s"; h[++nh]="csK/s"; h[++nh]="%busyTL"; h[++nh]="pkts/cs";
     h[++nh]="busyTL/GBps"; h[++nh]="delack";h[++nh]="extdelack"; h[++nh]="quickack"; h[++nh]="autocork\n";
   }
   nc = 0;
   bsy = prf_busyTL - nice;;
  
   c[++nc]= outs;
   c[++nc]= bw;
   c[++nc]= pkts_ps;
   c[++nc]= cs;
   c[++nc]= bsy;
   c[++nc]= pkts_ps/cs;
   if ((bw+0) == 0) { printf("_____got bw= 0. its a problem\n"); c[++nc] = 0; } else {
   c[++nc]= bsy/(0.001*bw);
   }
   c[++nc]= delack;
   c[++nc]= extdelack;
   c[++nc]= quickack;
   c[++nc]= cork;
   if (nc != nh) {
     printf("got nc(%d) != nh(%d). fix it\n", nc, nh) > "/dev/stderr";
     rc = 1;
     exit(1);
   }
   num[grp]++;
   for (i=2; i <= 11; i++) {
     if (i == 2) {vx = bw;}
     else if (i == 6) {vx = cs;}
     else {vx = 0.001*bw;}
     vy = c[i];
     x_sum[grp,i]  += vx;
     y_sum[grp,i]  += vy;
     xy_sum[grp,i] += vx * vy;
     x2_sum[grp,i] += vx * vx;
     x[grp,i,num[g]] = vx;
     y[grp,i,num[g]] = vy;
   }
   #  grp_cfg[grp] = cstr;
   carr_n = split(grp_cfg[grp], carr, "_");
   q_sz = "unk";
   for (i=2; i <= carr_n; i++) {
     if (substr(carr[i], 1, 1) == "q") {
       q_sz = substr(carr[i], 2);
     }
   }
   if (got__ == 1 || grp != grp_prv) {
#QQ_HDR cfg_q_sz redis_cpus RPS(k) p50 p90 p99 cfg tot_netTL ps_busyTL tot_usableTL cfg_cur freq tot_net_MB/s tot_net_kPkts/s Int_1000/s spin_ref_perf spin_cur_perf spin_work spin_threads num_cpus missing_cpusTL ps_tot_int_rateK/s ps_net_irq_rateK/s ps_net_sftirq_rateK/s ps_cs_rateK/s pct_stdev_int/q dir
    hdr_str = sprintf("QQ_HDR cfg_q_sz redis_cpus RPS(k) p50 p90 p99 cfg tot_netTL ps_busyTL tot_usableTL cfg_cur freq tot_net_MB/s tot_net_kPkts/s Int_1000/s spin_ref_perf spin_cur_perf spin_work spin_threads num_cpus missing_cpusTL ps_tot_int_rateK/s ps_net_irq_rateK/s ps_net_sftirq_rateK/s ps_cs_rateK/s pct_stdev_int/q ""grp outs bw(MB/s) pktsK/s csK/s %%busyTL pkts/cs busyTL/GBps delack extdelack quickack autocork N cfg");
    printf("%s\n", hdr_str);
    grp_prv = grp;
   }

   v1 = cmd_ln[grp,gj,"LAT_CPU"];
   if (v1 == "") { v1 = "unk"; }
   if ((bw+0) == 0) {
     bsy_bw = 0;
   } else {
     bsy_bw = bsy/(0.001*bw);
   }
   det_str = sprintf("QQ_%s_%d %s %s %.3f %.3f %.3f %.3f %s %.3f %.3f %.3f %s %.3f %.3f %.3f %.3f %s %s %s %d %s %.3f %.3f %.3f %.3f %s ""%d %d %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %d %s %s",
     typ_tst, gj-1, q_sz, v1, tot_rpsK, p50, p90, p99, "cfg_q"q_sz, bsy, ps_busyTL, usr_sys, cfg,
     frq, bw, pkts_ps, tot_intr_Kps,
#spin_ref_perf spin_cur_perf spin_work spin_threads num_cpus missing_cpusTL
     0, 0, 0, 0, num_cpus, 0,
#ps_tot_int_rateK/s ps_net_irq_rateK/s ps_net_sftirq_rateK/s ps_cs_rateK/s pct_stdev_int/q
     tot_intr_Kps, net_irqs, softirqs_Kps, cs, 0,

     grp, outs, bw, pkts_ps, cs, bsy, pkts_ps/cs, bsy_bw, delack, extdelack, quickack, cork, N, grp_cfg[grp]);
   printf("%s\n", det_str);
   if (dif_one++ == 0) {
     hdr_n = split(hdr_str, hdr_arr, " ");
     det_n = split(det_str, det_arr, " ");
     if (verbose == 1) {
     for (i=1; i <= hdr_n; i++) {
       printf("%d %s %s\n", i, hdr_arr[i], det_arr[i]);
     }
     }
     if (det_n != hdr_n) {
       printf("got hdr_n= %d det_n= %d\n", hdr_n, det_n);
       rc = 1;
       exit(rc);
     }
   }
}
 END {
   if (rc != 0) {
     printf("got rc= %d. bye\n", rc);
     exit(rc);
   }
   if(got__ != "" && did_prt[got__] == 0) {
     prt_stats();
     did_prt[got__] = 1;
   }
   for (g=1; g <= grp; g++) {
   for (j=2; j <= nh; j++) {
     mean_x = x_sum[g,j] / num[g]
     mean_y = y_sum[g,j] / num[g]
     mean_xy = xy_sum[g,j] / num[g]
     mean_x2 = x2_sum[g,j] / num[g]
     divi = (mean_x2 - (mean_x*mean_x));
     slope = 0;
     if (divi > 0) {
       slope = (mean_xy - (mean_x*mean_y)) / (mean_x2 - (mean_x*mean_x));
       inter = mean_y - slope * mean_x;
       ss_total = 0;
       ss_residual = 0;
       for (i = num[g]; i > 0; i--) {
           ss_total += (y[g,j,i] - mean_y)**2
           ss_residual += (y[g,j,i] - (slope * x[g,j,i] + inter))**2
       }
       r2 = 0;
       if (ss_total > 0) {
         r2 = 1 - (ss_residual / ss_total)
       }
       printf("grp= %d slope= %8.3f intercept= %9.4f R^2= %8.4f var= %s\n", g, slope, inter, r2, h[j] )
     }
   }
   }
 }
 ' "$INF"
 ck_last_rc $? $LINENO
exit 0

# below from http://www.dayofthenewdan.com/2012/12/26/AWK_Linear_Regression.html

BEGIN { FS = "[ ,\t]+" }
NF == 2 { x_sum += $1
          y_sum += $2
          xy_sum += $1*$2
          x2_sum += $1*$1
          num += 1
          x[NR] = $1
          y[NR] = $2
        }
END { mean_x = x_sum / num
      mean_y = y_sum / num
      mean_xy = xy_sum / num
      mean_x2 = x2_sum / num
      slope = (mean_xy - (mean_x*mean_y)) / (mean_x2 - (mean_x*mean_x))
      inter = mean_y - slope * mean_x
      for (i = num; i > 0; i--) {
          ss_total += (y[i] - mean_y)**2
          ss_residual += (y[i] - (slope * x[i] + inter))**2
      }
      r2 = 1 - (ss_residual / ss_total)
      printf("Slope      :  %g\n", slope)
      printf("Intercept  :  %g\n", inter)
      printf("R-Squared  :  %g\n", r2)
    }


