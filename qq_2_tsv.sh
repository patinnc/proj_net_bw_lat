#!/usr/bin/env bash

AWK=gawk
# arg1 is qq2_dirs directory with a structure as created by "qq2_fetch.sh out1.txt"
# so if you do qq

TARGET=google # excel or google
TARGET=excel # excel or google
if [ "$TARGET" == "excel" ]; then
  HARDCODE=0 
else
  HARDCODE=1 
fi
OXLSX=tst7_3min_govPerf_${HARDCODE}.xlsx
FILES=()
TAGS=
 INDIR=qq2_dirs_20221109_govPerf
 FL=$INDIR/qq2_dirs/file_list.txt
 STR=$(cat $FL)
 FILES+=($(awk -v indir="$INDIR" '{if ($0==""){next;}; $1=""; gsub(/ /, "", $0); $1=$1;$0=$0;printf("%s/%s\n", indir, $0);}' $FL))
 TAGS=$(awk '{if ($0==""){next;}; str=str""sep""$1;sep="|";}END{printf("%s\n", str);}' $FL)
 
echo "$0.$LINENO files num= ${#FILES[@]} list=  ${FILES[@]}"
#exit 1

ck_last_rc() {
   local RC=$1
   local FROM=$2
   if [ $RC -gt 0 ]; then
      echo "$0: got non-zero RC=$RC at $LINENO. called from line $FROM" > /dev/stderr
      exit $RC
   fi
}

XLS=xlsx
if [ ! -d $XLS ]; then
  mkdir $XLS
fi
WRK="work"
rm -rf $WRK
for ((i=0; i < ${#FILES[@]}; i++)); do
  ODIR="$WRK/$i/0"
  if [ ! -d $ODIR ]; then
    mkdir -p $WRK/$i/0
  fi
  OFILE="stats.tsv"
  if [ -e $ODIR/$OFILE ]; then
    rm $ODIR/$OFILE
  fi
done

echo "$0.$LINENO files= ${FILES[@]}"
#exit 1

CHRTS_1ST_LINE_FILE="charts_1st_line.tsv"
# check files okay
# target can be google or excel
echo $0.$LINENO $AWK -v tags="$TAGS" -v target="$TARGET" -v hardcode="$HARDCODE" -v uvx="bw" -v chrts_1st_line_file="$CHRTS_1ST_LINE_FILE" -v work_dir="$WRK" -v ofile="$OFILE" 
$AWK -v tags="$TAGS" -v target="$TARGET" -v hardcode="$HARDCODE" -v uvx="bw" -v chrts_1st_line_file="$CHRTS_1ST_LINE_FILE" -v work_dir="$WRK" -v ofile="$OFILE" -f ~/repos/60secs/get_excel_col_letter_from_number.awk --source '
  #BEGIN{printf("get_col_ltr for col 0= %s\n", get_excel_col_letter_from_number(0));
  #      printf("get_col_ltr for col 1= %s\n", get_excel_col_letter_from_number(1));}
  BEGIN{
    n_tags = split(tags, arr, "|");
    for (i=1; i <= n_tags; i++) {
      fl_tag[i] = arr[i];
      printf("fl_tag[%d]= %s\n", i, fl_tag[i]);
    }
  }
  {
    if ($0 == "") { next; }
    if (substr($1, 1, 1)  == "#") { next; }
    typ = ($1 == "QQ_HDR" ? "hdr" : "det");
    if (fl != ARGIND) {
      fl = ARGIND;
      v = ARGV[fl];
      fl_nm_full[fl] = v;
      gsub(/qq2_/,"", v);
      gsub(/.txt/,"", v);
      gsub(/_tcp2/,"", v);
      gsub(/_tcp/,"", v);
      #fl_nm_tag[fl] = v;
      fl_nm_tag[fl] = fl_tag[fl];
    }
    if (typ == "hdr") {
      grp = ++grps[fl];
      grp_mx = grp;
      lines[fl, grp] = 0;
      #insert new field before "dir" last field
      nf_old = $(NF);
      $(NF) = "pkts/interrupt";
      $(NF+1) = nf_old;
      $1 = $1;
      hdr_n = split($0, hdr_arr, " ");
      for (i=1; i <= hdr_n; i++) {
        hdr_ky_str[hdr_arr[i]] = i;
        hdr_ky_num[i] = hdr_arr[i];
      }
      col_pkt = hdr_ky_str["tot_net_kPkts/s"];
      col_int = hdr_ky_str["Int_1000/s"];
      hdr_cfg_num = hdr_ky_str["cfg"];
      hdr_cfg_cur_num = hdr_ky_str["cfg_cur"];
    }
    if (nf_prv == "") { nf_prv = NF; }
    if (NF != nf_prv) {
      cf0 = -1;
      cf1 = -1;
      for (i=1; i <= NF; i++) {
        if (index($i, "cfg_") == 1) {
          if (cf0 == -1) { cf0 = i; } else if (cf1 == -1) { cf1 = i; }
        }
      }
      if (cf0 == 8 && cf1 == 10) {
        # need to fix up line
        nf0 = NF;
        str = $0;
        j = 0;
        for (i=1; i <= cf0; i++) {
          arr[++j] = $i;
        }
        arr[++j] = 0;
        arr[++j] = 0;
        arr[++j] = 0;
        arr[++j] = $(cf1);
        arr[++j] = frq_prv;
        for (i=cf1+1; i <= NF; i++) {
          arr[++j] = $i;
        }
        for (i=1; i <= j; i++) {
          $i = arr[i];
        }
        $1 = $1;
        $0 = $0;
        nf1 = NF;
        #printf("old str= %s  nf0= %d nf1= %d\n", str, nf0, nf1);
        #printf("new str= %s\n", $0);
      } else {
        ;
        #printf("file[%d] line %d has NF= %d vs prev_NF= %d file= %s cf0= %d cf1= %d\n", ARGIND, FNR, NF, nf_prv, ARGV[ARGIND], cf0, cf1);
        #exit(1);
      }
    }
    if (typ != "hdr" && NF == (hdr_n-1)) {
      #tot_net_kPkts/s Int_1000/s
      v_pkt = $col_pkt;
      v_int = $col_int;
      if (det_did == "") {
        printf("det bef %s\n", $0);
      }
      if (index($1, "QQ_lat_") == 1) { typ_tst = "lat";}else{ typ_tst = "bw";}
      if ( v_int > 0) { v = sprintf("%.3f", v_pkt/v_int); } else { v = 0; };
      nf_old = $(NF);
      $(NF) = v;
      $(NF+1) = nf_old;
      $1 = $1;
      if (det_did == "") {
        printf("det aft %s\n", $0);
        det_did = 1;
      }
    }
    nf_prv = NF;
    if (typ == "hdr") {
      next;
    }
    ln = ++lines[fl, grp];
    if (grp <= 4) {
      gtyp = "bw";
    } else {
      gtyp = "lat";
    } 
    gtyp = typ_tst;
    cfg[fl, grp, "grp_typ"] = gtyp;
    cfg[fl, grp, "q"] = $2;
    cfg[fl, grp, "beg_cpu"] = $3;
    if (typ == "det") {
      vy = "missing_cpusTL";
      cy = hdr_ky_str[vy]+0;
      if (cy > 0 && ($cy) == 0.0) {
        vy1 = "tot_netTL";
        cy1 = hdr_ky_str[vy1]+0;
        vy2 = "ps_busyTL";
        cy2 = hdr_ky_str[vy2]+0;
        if (cy1 > 0 && cy2 > 0 && $cy1 > 0.0 && $cy2 > 0.0) {
          $cy = $cy1 - $cy2;
        }
      }
      vy = "pct_stdev_int/q";
      cy = hdr_ky_str[vy]+0;
      vy1 = "pkts/cs";
      cy1 = hdr_ky_str[vy1]+0;
      if (cy > 0 && $cy == 0.0 && cy1 > 0) {
         use_pkts_ps = 1;
      }
    }
    for (i=1; i <= NF; i++) {
      v = $i;
      if (v < 0.0) {
        v = 0.0;
      }
      sv[fl, grp, ln, i] = v;
    }
    if (typ == "det") {
      #printf("frq_col= %d str= %s\n", hdr_ky_str["freq"], $(hdr_ky_str["freq"]));
      frq_prv = $(hdr_ky_str["freq"]);
    }
  }
#title   uptime  sheet   uptime  type    line
#hdrs    16      0       610     2       -1
#ld_avg_1m       ld_avg_5m       ld_avg_15m
#1.76    1.54    1.13
#1.76    1.54    1.13
  END{
     fl_mx = fl;
     if (target == "google") {
       ch_typ = "line_markers";
     } else {
       ch_typ = "scatter_straight_markers";
     }
     vx0 = "ps_net_irq_rateK/s";
     vx1 = "tot_net_MB/s";
     if (uvx == "bw") {
      v = vx0;
      vx0 = vx1;
      vx1 = v;
     }
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "missing_cpusTL";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "tot_netTL";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "ps_net_irq_rateK/s";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "tot_net_MB/s";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "pkts/interrupt"
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "ps_net_sftirq_rateK/s";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "tot_net_kPkts/s";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "ps_cs_rateK/s";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     if (use_pkts_ps == 1) {
       chrts[ch_mx, "y"] = "pkts/cs";
     } else {
       chrts[ch_mx, "y"] = "pct_stdev_int/q";
     }
#p50 p90 p99
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "p50";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "p90";
     ++ch_mx;
     chrts[ch_mx, "x"] = vx0;
     chrts[ch_mx, "y"] = "p99";

     for (f=1; f <= fl_mx; f++) {
       outdir  = work_dir "/" (f-1) "/0/";
       descfile = outdir "/desc.txt";
       printf("%s\n", fl_nm_tag[f]) > descfile;
       close(descfile);
     }
     linest_flds[1] = "m"; # slope
     linest_flds[2] = "b"; # y intercept
     linest_flds[3] = "R2"; # r-squared
     linest_flds[4] = "max X"; # max of X values
     linest_flds[5] = "max Y"; # max of X values
     for (f=1; f <= fl_mx; f++) {
       rw = 0;
       outdir  = work_dir "/" (f-1) "/0/";
       outfile = outdir "/" ofile;
       if (1==2) {
       for (g=1; g <= grp_mx; g++) {
         vy = "missing_cpusTL";
         vx = "ps_net_irq_rateK/s";
         cy = hdr_ky_str[vy];
         cx = hdr_ky_str[vx];
         gtyp = cfg[f, g, "grp_typ"];
         q    = cfg[f, g, "q"];
         bcpu = cfg[f, g, "beg_cpu"];
         rw++;
         printf("title\t%s,%s,q%s:c%s %s vs %s\tsheet\t%s\ttype\t%s\n", fl_nm_tag[f], gtyp, q, bcpu,  hdr_ky_num[cy], hdr_ky_num[cx], fl_nm_tag[f],ch_typ) > outfile;
         rw++;
         printf("hdrs\t%s\t1\t-1\t1\t0\n", rw) > outfile;
         rw++;
         printf("%s\t%s\n", vx, vy) > outfile;
         for (i=1; i <= lines[f,g]; i++) {
           rw++;
           printf("%s\t%s\n", sv[f, g, i, cx], sv[f, g, i, cy]) > outfile;
         }
         rw+=2;
         printf("\n\n") > outfile;
       }
       }
       col_xif = get_excel_col_letter_from_number(grp_mx+2);
       col_yif = get_excel_col_letter_from_number(grp_mx+3);
       col_xv  = get_excel_col_letter_from_number(grp_mx+4);
       col_xv1 = get_excel_col_letter_from_number(grp_mx+5);
       col_yv  = get_excel_col_letter_from_number(grp_mx+6);
       col_hdr_beg = grp_mx+4;
       for (ch=1; ch <= ch_mx; ch++) {
         vy = chrts[ch, "y"];
         vx = chrts[ch, "x"];
         cy = hdr_ky_str[vy];
         cx = hdr_ky_str[vx];
         cx1 = hdr_ky_str[vx1];
         #cx1 = hdr_ky_str[vx1];
         rw++;
         #printf("title\t%s %s vs %s\tsheet\t%s\ttype\t%s\n", fl_nm_tag[f], hdr_ky_num[cy], hdr_ky_num[cx], fl_nm_tag[f], ch_typ) > outfile;
         title_row = rw;
           title_str = sprintf("%s vs %s", hdr_ky_num[cy], vx);
         if (hardcode == 1) {
           title_str = sprintf("%s %s vs %s", fl_nm_tag[f], hdr_ky_num[cy], vx);
           printf("title\t%s\tsheet\t%s\ttype\t%s\n", title_str, fl_nm_tag[f], ch_typ) > outfile;
         } else {
           str = sprintf("\"=CONCATENATE(I%d,J%d)\"\t%s %s vs \t\"=IF(charts!B1=1,\"\"%s\"\",\"\"%s\"\")\"", rw, rw, fl_nm_tag[f], hdr_ky_num[cy], vx, vx1);
           #title_str = sprintf("=%s!H%s", fl_nm_tag[f], rw);
           #printf("title\t\"%s\"\tsheet\t%s\ttype\t%s\t\t%s\n", title_str, rw, fl_nm_tag[f], ch_typ, str) > outfile;
           printf("title\t\"=%s!H%s\"\tsheet\t%s\ttype\t%s\t\t%s\n", fl_nm_tag[f], rw, fl_nm_tag[f], ch_typ, str) > outfile;
         }
         rw++;
         printf("hdrs\t%s\t1\t-1\t%s\t0\n", rw, grp_mx) > outfile;
         rw++;
         #str = sprintf("%s", vx);
         printf("%s", vx) > outfile;
         sep = "\t";
         if (f == 1 && ch == 1) {
           printf("%s\t=1", vx) > chrts_1st_line_file;
         }
         for (g=1; g <= grp_mx; g++) {
           gtyp = cfg[f, g, "grp_typ"];
           q    = cfg[f, g, "q"];
           bcpu = cfg[f, g, "beg_cpu"];
           colg[g] = sprintf("%s,q%s,c%s", gtyp,q,bcpu);
           if (hardcode == 1) {
             printf("\t%s,q%s,c%s", gtyp,q,bcpu) > outfile;
           } else {
             printf("\t\"=IF(charts!%s1=0,NA(),\"\"%s,q%s,c%s\"\")\"", get_excel_col_letter_from_number(2*(g-1)+3), gtyp,q,bcpu) > outfile;
           }
           if (f == 1 && ch == 1) {
             printf("%s%s,q%s,c%s\t=1", sep,  gtyp,q,bcpu) > chrts_1st_line_file;
             sep = "\t";
           }
         }
         if (f == 1 && ch == 1) {
             printf("\n") > chrts_1st_line_file;
             close(chrts_1st_line_file);
         }
         #printf("=%s%d", get_excel_col_letter_from_number(grp_mx+4), rw) > outfile;
         #for (g=1; g <= grp_mx; g++) {
         #  printf("\t=%s%d", get_excel_col_letter_from_number(grp_mx+4+g),rw) > outfile;
         #}
         #printf("\t\t\t\t%s", str) > outfile;
         printf("\n") > outfile;
         blnk = "\"\"\"\"";
         na = "NA()";
         blnk_na = (hardcode==1?blnk:na);
         for (gg=1; gg <= grp_mx; gg++) {
           for (i=1; i <= lines[f,gg]; i++) {
             rw++;
             #printf("%s", sv[f, gg, i, cx]) > outfile;
             if (hardcode == 1) {
                printf("+%s", sv[f, gg, i, cx]) > outfile;
             } else {
                printf("=%s%s", col_xif, rw) > outfile;
             }
             for (g=1; g <= grp_mx; g++) {
               if (g == gg) {
                 #printf("\t%s", sv[f, g, i, cy]) > outfile;
                 printf("\t=%s%s", col_yif, rw) > outfile;
               } else {
                 printf("\t") > outfile;
               }
             }
             printf("\t\t\"=IF(charts!%s$1=0,%s,IF(charts!%s$1=1,%s%s,IF(charts!%s$1=2,%s%s,%s)))\"",
                get_excel_col_letter_from_number(2*(gg-1)+3),
                blnk_na,
                get_excel_col_letter_from_number(1), col_xv,rw,
                get_excel_col_letter_from_number(1), col_xv1, rw, blnk_na) > outfile;
             printf("\t\"=IF(charts!%s$1=0,%s,%s%s)\"", get_excel_col_letter_from_number(2*(gg-1)+3), blnk_na, col_yv, rw) > outfile;
             printf("\t=%s\t=%s\t=%s", sv[f, gg, i, cx], sv[f, gg, i, cx1], sv[f, gg, i, cy]) > outfile;
             #printf("sv[%s,%s,%s,%s]= %s, ky_str= %s vx1= %s\n", f, gg, i, cx1, sv[f, gg, i, cx1], hdr_ky_str[vx1], vx1) > "/dev/stderr";
#abcd
             if (i == 1) {
                linest_stat[1] = "FALSE";
                linest_stat[2] = "FALSE";
                linest_stat[3] = "TRUE";
                v1 = rw; v2 = rw+lines[f,gg]-1;
                stats[f,ch,gg,"file"] = fl_nm_tag[f];
                stats[f,ch,gg,"title"] = title_str;
                stats[f,ch,gg,"col"] = colg[gg];
                printf("\t\t\"%s\"\t\"=%s!B%d\"\t\"%s\"", fl_nm_tag[f], fl_nm_tag[f], title_row, colg[gg]) > outfile;
                Lstr = get_excel_col_letter_from_number(11 - (8-grp_mx)); # 11 is if you have 8 groups
                Kstr = get_excel_col_letter_from_number(10 - (8-grp_mx)); # 10 is if you have 8 groups
                #if (gg==1) {printf("Lstr= %s lines[%s,%s]= %s grp_mx= %s\n", Lstr, g, gg, lines[f,gg], grp_mx) > "/dev/stderr";}
                for (ki=1; ki <= 3; ki++) {
                  v = linest_flds[ki];
                #str = sprintf("=INDEX(LINEST(%s!$L%d:$L%d,0.001*%s!$K%d:$K%d,TRUE,%s),%d)", fl_nm_tag[f], v1, v2, fl_nm_tag[f], v1, v2, linest_stat[ki], ki);
                str = sprintf("=INDEX(LINEST(%s!$%s%d:$%s%d,0.001*%s!$%s%d:$%s%d,TRUE,%s),%d)", fl_nm_tag[f], Lstr, v1, Lstr, v2, fl_nm_tag[f], Kstr, v1, Kstr, v2, linest_stat[ki], ki);
                stats[f,ch,gg,v] = str;
                printf("\t\"%s\"", str) > outfile;
                }
                v = linest_flds[4];
                str = sprintf("=MAX(%s!$%s%d:$%s%d)", fl_nm_tag[f], Kstr, v1, Kstr, v2);
                stats[f,ch,gg,v] = str;
                printf("\t\"%s\"", str) > outfile;
                v = linest_flds[5];
                str = sprintf("=MAX(%s!$%s%d:$%s%d)", fl_nm_tag[f], Lstr, v1, Lstr, v2);
                stats[f,ch,gg,v] = str;
                printf("\t\"%s\"", str) > outfile;
             }
             printf("\n") > outfile;
           }
         }
         rw+=2;
         printf("\n\n") > outfile;
       }
       close(outfile);
     }
#abcd
       rw = 1;
       outdir  = work_dir "/" 0 "/0/";
       outfile = outdir "/sum.tsv";
       printf("title\tsum\tsheet\tsum\ttype\tcopy\n") > outfile;
       rw++;
       printf("hdrs\t%s\t0\t-1\t5\n", rw+1) > outfile;
       #printf("\n") > outfile;
       did_1st=0;
       for (ch=1; ch <= ch_mx; ch++) {
         for (f=1; f <= fl_mx; f++) {
           if (ch != ch_prv) {
           printf("\n") > outfile;
           printf("%s\t%s", stats[f,ch,1,"file"], stats[f,ch,1,"title"]) > outfile;
           for (ki=1; ki <= 5; ki++) {
           for (g=1; g <= grp_mx; g++) {
                printf("\t%s", stats[f,ch,g,"col"]) > outfile;
           }
           printf("\t") > outfile;
           }
           printf("\n") > outfile;
           rw++;
           ch_prv = ch;
           }
           printf("%s\t%s", stats[f,ch,1,"file"], stats[f,ch,1,"title"]) > outfile;
           for (ki=1; ki <= 5; ki++) {
           for (g=1; g <= grp_mx; g++) {
                #printf("\t%s", stats[f,ch,g,"col"]) > outfile;
                #for (ki=1; ki <= 1; ki++) {
                  v = linest_flds[ki];
                  #stats[f,ch,g,v] = str;
                  printf("\t\"%s\"", stats[f,ch,g,v]) > outfile;
                #}
           }
           printf("\t") > outfile;
           }
           printf("\n") > outfile;
           rw++;
         }
       }
       close(outfile);
  }
  ' ${FILES[@]}
  ck_last_rc $? $LINENO

find work -name "*.tsv" -exec ls -l {} \;
TSVS=($(find $WRK -name "*.tsv"))
TSVS2=($(find $WRK -name "stats.tsv"))
INP="$WRK/tsv_2_xlsx.inp"
: > $INP
printf "%s\t$XLS/$OXLSX\n" "-o"  >> $INP
for ((i=0; i < ${#TSVS2[@]}; i++)); do
  #printf "%s\tnet\n" "-p"  >> $INP
  printf "%s\t1,1\n" "-s" >> $INP
  #printf "%s\n" "-A" >> $INP
  DFILE=$WRK/$i/0/desc.txt
  printf "%s\t$DFILE\n" "-d"  >> $INP
  if [ -e $WRK/$i/0/sum.tsv ]; then
    printf "$WRK/$i/0/sum.tsv\n" >> $INP
  fi
  printf "$WRK/$i/0/$OFILE\n" >> $INP
  printf "\n" >> $INP
done
  python3 ~/repos/60secs/tsv_2_xlsx.py  -a .  -O "drop_summary,chart_sheet,all_charts_one_row,match_itp_muttley_interval,add_all_to_summary,sheet_for_file{muttley5.json=endpoints},sheet_limit{endpoints;cols_max;75},%cpu_like_top,sum_file_no_formula,get_max_val,get_perf_stat_max_val,xlsx_add_line_from_file_to_charts_sheet{$CHRTS_1ST_LINE_FILE}" -f $INP
echo "$0.$LINENO bye:"
exit 0

####
