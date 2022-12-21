    BEGIN {
      rc = 0;
      if ((tm+0) == 0) { printf("need to pass elapsed_time arg -v tm=XXX\n"); rc=1;exit(rc);}
      lkfor[++imx] = "_ucast_frames:"; sv_nm[imx] = "frameK/s"; sv_fctr[imx] = 1e-3/tm;
      lkfor[++imx] = "_drops:";        sv_nm[imx] = "drops/s";  sv_fctr[imx] = 1/tm;
      lkfor[++imx] = "_discards:";     sv_nm[imx] = "discards/s";  sv_fctr[imx] = 1/tm;
      lkfor[++imx] = "_err:";          sv_nm[imx] = "rx/tx_err/s";  sv_fctr[imx] = 1/tm;
      lkfor[++imx] = "_errors:";       sv_nm[imx] = "rx/tx_errors/s";  sv_fctr[imx] = 1/tm;
      lkfor[++imx] = "tpa_aborts:";    sv_nm[imx] = "tpa_aborts/s";  sv_fctr[imx] = 1/tm;
      lkfor[++imx] = "_total_discard_pkts:"; sv_nm[imx] = "tot_discard_pkts/s";  sv_fctr[imx] = 1/tm;
      lkfor[++imx] = "_err_frames:"; sv_nm[imx] = "any_err_frames/s";  sv_fctr[imx] = 1/tm;
    }
    {
      if ($0 == "") {next;}
      if (FILENAME != fl_prev) {
        fl++;
        fl_prev = FILENAME;
      }
      if (substr($1, 1,1) == "[") {
        kp = 2;
        vp = 3;
      } else {
        kp = 1;
        vp = 2;
      }
      key = $(kp);
      val = $(vp)+0;
      for (i=1; i <= imx; i++) {
        if (index(key, lkfor[i]) > 0) {
          v[fl,i] += val;
          break;
        }
      }
      #v[fl] += $2;
     #printf("argind= %d argc= %s fl= %s v= %s\n", ARGIND, ARGC, fl, $1);
    }
    END{
      if (rc != 0) { printf("got awk err rc= %s\n", rc); exit(rc);}
      for (i=1; i <= imx; i++) {
        mtrc = sv_nm[i];
        fctr = sv_fctr[i];
        if ((fctr+0) == 0) { fctr = 1.0;}
        printf("%s= %.3f\n", mtrc, fctr*(v[2,i]-v[1,i]));
      }
    }
