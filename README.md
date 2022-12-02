# proj_net_lat_bw

# Table of Contents
- [Introduction](#introduction)
- [Data collection](#data-collection)
- [Charting Data](#charting-data)

--------------------------------------------------------------------------------
## Introduction
- dependencies 
    - gawk instead of awk (apt-get install gawk or brew install gawk)
    - https://github.com/jmcnamara/XlsxWriter and python 3.4+ if you want to create spreadsheets/charts of results
       - say to test multiple SKUs and plot cpu-usage by the network as a funciton of network bandwidth usage
       - plot everything, fit lines to variable (such as "number of cpus used by network" per "GB/sec of network traffic"
       - or "number of interrupts/s" or context switchs or packets or "missing cpus"  per "GB/sec of network traffic"
Run and analyze network bandwidth, latency, cpu-usage and other resources.
Initially used iperf3, netperf and netserver to get network bw and latency.
I couldn't find a tool that would let me do both bw and latency so I made
tcp_client.c and tcp_server.c (and tcp_sort_latency.c)

I needed the code and scripts for accurately assessing the impact of
changing network card (NIC) settings like the combined queue size (ethtool -l eth0 X).
Features of the code:
- latency-type round-trip timing. latency timings similar to netperf.
   - can set some tcp options (like TCP_NODELAY) at various places 
   - change number of outstanding sends and receives (default 1)
   - change port number (use same port for send+recv or diff ports)
   - change msg size
   - stop either by number of msgs or after X number of seconds
- bandwidth-type test timing.
   - allow alternating directions. Allows max bw and very low overhead (like iperf3)
       - say client thread 0 on client-host just does writes to server thread 0 and
         client thread 1 on client-host just does reads from server thread 1 etc
   - allow rate limiter (say 200 MB/sec per client) so don't saturate bw with just a
     few clients
- allow not generating latency stats


--------------------------------------------------------------------------------
## Data Collection
- quick_net_stat.sh is a sample top level script to drive a test sequence
   - has default list of how many clients to start (override with -n xx). Can be max or min which means look at the default N_LST and pick the 1st or the last.
   - default list of client server ip addreses (see PAIRS veriable). have to be able to ssh as root to "other" box.
     Which ever box the script is started from is the server box. scripts stops checking PAIRS when it first matches the server's ip address.
   - allows directing output to a dir (-d dir_for_output)
   - allows setting -o outstanding_request
   - allows setting -p port[,port] 
   - allows setting -m msg_size[,msg_recv_sz]
   - allows setting -q ethtool_config_settings  set these options before the test begins.
       - set_eth0.sh script probably assumes the NIC is eth0.
       - allows things like cfg_q48  (set the queue size to 48), cfg_q48_a11 set q=48 and enable adaptive rx and tx. see set_eth0.sh for more.
   - allows specifying (-l min|max|number) the starting cpu number on which instances of tcp_client.x and tcp_server.x will be pinned
       - there is a min (the 1st cpu on the numa node that doesn't have the NIC)
       - there is a max (the 1st cpu on the numa node that does have the NIC)
       - threads start at that cpu and increment by 1 (depending on number of threads requested) and wrap back to cpu 0 if needed.
   - sets up cmd line for do_tcp_client_server.sh
   - sample cmd lines
   ./quick_net.sh -q "cfg_q48" -l hi -n max -T lat -t 60 -D ,spin_load   > sweep1.txt
       - -T lat  just do latency type test on the max number of clients (96 clients)
       - -q cfg_q48 calls ./set_eth0.sh cfg_q48 before the test runs. (there is a default set_eth0.sh call to the client box too so it is set to a known state).
       - -q cfg_qmax sets combined queue size to max allowable
       - -D options (if started with , then append cmd line options to script default options).
       - -D ,spin_load start my spin.x program with nice -20 lowest priority to do fixed work rate so we can see impact of interrupts on anything else running
   ./quick_net.sh -q "cfg_q8 cfg_qmax"  -l "hi lo"  -n "min max" -T "bw lat" -t 60   > sweep1.txt
       - do a sweep where './set_eth0.sh cfg_q8 (set combined q=8)' and another sweep with q=max
       - -l "hi lo" do a sweep starting the clients on the "hi performance" cpu and then another sweep starting the clients on the lo perf cpu. This is the dfault (I think)
       - -n "min max" just start the 1st and last number of clients from the N_LST string (currently 1 and 96)
       - -t time_in_seconds  time to run each test
    - Probably have to be root
    - need to have my 60secs dir up 1 dir so that ../60secs is found
    - server and client have to have the same dir structure (for where this dir is located)
    - script will try to set governor=performance on both client and server before the testing starts
    - script will tar.gz the \*.sh \*.c \*.x files in the server dir and untar them into the client dir before the testing starts
    - there is an option (after the sweep is done) to start the same test sweep on the client (so switch roles of who is server & who is client)
        - say I'm testing setting cfg_qmax on broadcom on the server and then want to test client (so switch roles of who is server & who is client)
    - Need a perf binary if one isn't installed on the box (or remove the -x option from the do_tcp_client_server.sh cmdline)
        - this does a perf stat data collection to get freq, %not_halted
    - Any post processing (such as reading/combining/sorting the latency data (which can be very big)) is done outside of the latency or bw timing step)
        - if latency data is requested (the default is yes) writing out the latency file on the client is very quick (a binary float array) usually taking something like 0.01 seconds (but this is on a server with nvme drives). See the output_dir/start_client*.txt files for the time to write the file.
- after it is done:
    - extract_tcp_stats.sh sweep1.txt > out1.txt
- creates QQ lines like:
```
QQ_HDR cfg_q_sz redis_cpus RPS(k) p50 p90 p99 cfg tot_netTL ps_busyTL tot_usableTL cfg_cur freq tot_net_MB/s tot_net_kPkts/s Int_1000/s spin_ref_perf spin_cur_perf spin_work spin_threads num_cpus missing_cpusTL ps_tot_int_rateK/s ps_net_irq_rateK/s ps_net_sftirq_rateK/s ps_cs_rateK/s pct_stdev_int/q grp outs bw(MB/s) pktsK/s csK/s %busyTL pkts/cs busyTL/GBps delack extdelack quickack autocork N cfg
QQ_bw_0 8 24 200.000 1.382 3.055 10.612 cfg_q8 43.845 38.280 35.595 cfg_q8_a11_ru8_rf128_rif0_tu8_tf128_tif0 1.616 208.751 144.843 8.590 0 0 0 0 48 0.000 8.590 8.202 8.215 1.809 0 1 1.000 208.751 144.843 1.809 43.845 80.068 210.035 0.000 0.000 0.000 1024 2 cfg_q8_a11_ru8_rf128_rif0_tu8_tf128_tif0
QQ_bw_1 8 24 400.000 1.125 3.266 10.521 cfg_q8 92.303 71.303 64.257 cfg_q8_a11_ru8_rf128_rif0_tu8_tf128_tif0 1.562 420.386 308.761 18.494 0 0 0 0 48 0.000 18.494 17.752 19.315 6.682 0 1 1.000 420.386 308.761 6.682 92.303 46.208 219.567 0.000 0.000 0.000 1224 3 cfg_q8_a11_ru8_rf128_rif0_tu8_tf128_tif0
```

## Gathering the data so we can compare and chart it
- now we have server data from at least one ip address, lets say we have 3 pairs of servers, each pair is the same sku except one has broadcom NIC and one has mellanox NIC
- want to get the out1.txt output from each server
- I use qq2_fetch.sh script which uses install_and_run_on_cloud.sh (from 60secs) and 2 host lists (hosts_intel2.lst and hosts_amd2.lst) files
- the output structure looks like:

```
somedir:~$ ./qq2_fetch.sh out1.txt  # assume /root/proj_net_bw_lat/out1.txt exists and probably a bunch of other assumptions
somedir:~$ find qq2_dirs
qq2_dirs
qq2_dirs/192.168.1.119
qq2_dirs/192.168.1.119/host.txt
qq2_dirs/192.168.1.119/qq2_shrt.txt  # the extracted QQ lines from out1.txt
qq2_dirs/192.168.1.119/out1.txt
qq2_dirs/192.168.1.130
qq2_dirs/192.168.1.130/host.txt
qq2_dirs/192.168.1.130/qq2_shrt.txt
qq2_dirs/192.168.1.130/out1.txt
qq2_dirs/192.168.1.168
qq2_dirs/192.168.1.168/host.txt
qq2_dirs/192.168.1.168/qq2_shrt.txt
qq2_dirs/192.168.1.168/out1.txt
qq2_dirs/192.168.1.55
qq2_dirs/192.168.1.55/host.txt
qq2_dirs/192.168.1.55/qq2_shrt.txt
qq2_dirs/192.168.1.55/out1.txt
qq2_dirs/192.168.1.55/.qq2_shrt.txt.swp
qq2_dirs/192.168.1.187
qq2_dirs/192.168.1.187/host.txt
qq2_dirs/192.168.1.187/qq2_shrt.txt
qq2_dirs/192.168.1.187/out1.txt
qq2_dirs/192.168.1.96
qq2_dirs/192.168.1.96/host.txt
qq2_dirs/192.168.1.96/qq2_shrt.txt
qq2_dirs/192.168.1.96/out1.txt
qq2_dirs/file_list.txt
```
- and the file_list.txt looks like:
    - the strings like sku1_csx_brc will be used in the charting code to identify that a chart is for 'sku1_csx_brc'

```
somedir:~$ cat qq2_dirs/file_list.txt 
sku1_csx_brc qq2_dirs/192.168.1.119/qq2_shrt.txt
sku1_csx_mlx qq2_dirs/192.168.1.55/qq2_shrt.txt
sku2_icx_brc qq2_dirs/192.168.1.130/qq2_shrt.txt
sku2_icx_mlx qq2_dirs/192.168.1.187/qq2_shrt.txt
sku3_mln_brc qq2_dirs/192.168.1.168/qq2_shrt.txt
sku3_mln_mlx qq2_dirs/192.168.1.96/qq2_shrt.txt
```
## Charting Data
- need python 3.4+
- need to install xlsxwriter from John McNamara
   - see https://xlsxwriter.readthedocs.io/
   - do: pip install xlsxwriter
- Now you can create an excel spreadsheet with charts and stats with
    - edit ./qq_2_tsv.sh and change the last 'INDIR=dirname" where dirname is the dir containing your qq2_dirs subdir
    - edit OXLSX=somename.xlsx where somename is the filename for the output xlsx file
    - edit TARGET=google|excel  if target is excel then you OXLSX=somename.xlsx where somename is the filename for the output xlsx file
    - ./qq_2_tsv.sh
    - look in xlsx subdir for somename.xlsx
- if TARGET=google then you have to upload the xlsx to google sheets:
    - after uploading, open it and save it as a 'google sheets' file
    - close the xlsx in your browser
    - open the new google sheets file
    - go to the charts sheet... these charts will get fixed up by a script below
    - click the sheets menu "Extensions -> Apps scripts
        - you have to be logged in and have permissions, eventually you will get a screen that lets you paste code into "myFunction { }"
        - edit google_sheets_fixup_chart.gs and copy the lines between "function myFunction() {" and the last "}" into the google sheets "myFuntion{ }"
        - click save
        - click run # this can take a while to run. You should eventually see the 1st chart get transformed then the next chart, etc then the next row of charts, and so on.


--------------------------------------------------------------------------------

