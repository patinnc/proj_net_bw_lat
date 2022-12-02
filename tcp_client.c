// based on https://www.geeksforgeeks.org/tcp-server-client-implementation-in-c/
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include <string.h>
#include <signal.h>
#include <sys/types.h>          /* See NOTES */
#include <sys/socket.h>
#include <netinet/tcp.h>

#define MAX 1024
#define NMAX 1024
#define PORT 8080
#define SA struct sockaddr

// below sets flag to query if we are on client or server. 1 is client, 2 is server
#define CLNT_SRVR 1

double tm_run = 0.0;
double bw_max = 0.0;
char host_ip[256];
char *odir = NULL;
int port_rd=8000;
int port_wr=8000;
int verbose = 0;
int outstanding_requests[]={1,1,2};
int msg_size = MAX;
int opt_do_lat = 1;
int total_messages = 0;
int tcp_nodelay = -1;
int tcp_nodelay_who = 0;
int tcp_nodelay_val = 1;
int tcp_cork = -1;
int tcp_cork_who = 0;
int tcp_cork_val = 1;
int tcp_quickack = -1;
int tcp_quickack_who = 0;
int tcp_quickack_val = 1;
int tcp_maxseg = -1;
int tcp_maxseg_who = 0;
int tcp_maxseg_val = -1;
int tcp_lkfor_len[] = {0, 0, 0, 0, 0};
char *tcp_lkfor[] = {"nodelay=", "cork=", "quickack=", "maxseg=", "no_lat"};
double partial_msgs_rd= 0;
double partial_bytes_rd= 0;
double partial_msgs_wr= 0;
double partial_bytes_wr= 0;

volatile int got_quit=0;

static void sighandler(int sig)
{
        got_quit=1;
}

// Function designed for chat between client and server.
double get_dclock(void)
{
	struct timespec tp;
	clock_gettime(CLOCK_MONOTONIC, &tp);
	return (double)(tp.tv_sec) + 1e-9 * (double)(tp.tv_nsec);
}
extern char *optarg;
extern int optind, opterr, optopt;

static int compare (const void * a, const void * b)
{
  if (*(double*)a > *(double*)b) return 1;
  else if (*(double*)a < *(double*)b) return -1;
  else return 0;  
}

static int parse_tcp_val(char *tmp_str, char *do_what)
{
   char *vpos;
   int voff, ret_val=-1, slen;

   vpos = strchr(tmp_str, 'v');
   if (vpos != NULL) {
      slen = strlen(tmp_str);
      voff = (int)(vpos - tmp_str);
      printf("%s.%d %s str= %s, voff= %d slen= %d\n", __FILE__, __LINE__, do_what, tmp_str, voff, slen);
      if (voff < slen) {
         ret_val = atoi(vpos+1);
         printf("%s.%d tcp_maxseg str= %s, val= %d\n", __FILE__, __LINE__, vpos+1,  ret_val);
      }
   }
   return ret_val;
}

static int parse_tcp_args(char *str)
{
   int i, fld_beg=1, j, k, mm, len, ret_val, tst_rc;
   int hx_val =0, got_c, got_s, who;
   char *hx_end;
   char *arg;
   char tmp_str[256];

   len=strlen(str);
   if (len >= sizeof(tmp_str)) {
      printf("%s.%d len of input -D string is %d and is bigger than tmp_str size= %d. Error. fix code\n", __FILE__, __LINE__, len, (int)(sizeof(tmp_str)));
      exit(1);
   }

   if (sizeof(tcp_lkfor)/sizeof(tcp_lkfor[0]) != sizeof(tcp_lkfor_len)/sizeof(tcp_lkfor_len[0])) {
      printf("%s.%d len of array tcp_lkfor_len != len of array lkfo. Error. fix code\n", __FILE__, __LINE__);
      exit(1);
   }
   for (i=0; i < sizeof(tcp_lkfor)/sizeof(tcp_lkfor[0]); i++) {
     tcp_lkfor_len[i] = strlen(tcp_lkfor[i]);
   }
     
   for (i=0; i < len; i++) {
     if (i==0 || fld_beg == 1) {
       for (mm=0; mm < sizeof(tcp_lkfor)/sizeof(tcp_lkfor[0]); mm++) {
        //tst_rc = memcmp(str+i, tcp_lkfor[mm], tcp_lkfor_len[mm]); // not really safe without the ck for len I think
        //printf("mm= %d, i= %d len= %d, lkfor= %s str= %s len-i= %d lkfor_len= %d tst_rc= %d  at %s %d\n", mm, i, len, tcp_lkfor[mm], str+i, len-i, tcp_lkfor_len[mm], tst_rc,  __FILE__, __LINE__);
        if ((len-i) >= tcp_lkfor_len[mm] && memcmp(str+i, tcp_lkfor[mm], tcp_lkfor_len[mm]) == 0) {
          fld_beg = 0;
          j = i+tcp_lkfor_len[mm];
          arg = str+j;
          k = 0;
          printf("%s.%d start tcp_opt str= %s\n", __FILE__, __LINE__, arg);
          if (strcmp(tcp_lkfor[mm], "no_lat") == 0) {
            opt_do_lat = 0;
            printf("got tcp_opt no_lat at %s %d\n", __FILE__, __LINE__);
            continue;
          }
          bzero(tmp_str, sizeof(tmp_str));
          for (; j <= len; j++) {
            printf("%s.%d ck str= %s for ,\n", __FILE__, __LINE__, arg+k);
            if (arg[k] == ',' || arg[k] == 0) {
              tmp_str[k] = 0;
              printf("%s.%d ck got cma tmp_str= %s\n", __FILE__, __LINE__, tmp_str);
              break;
            } else {
              tmp_str[k] = arg[k];
            }
            k++;
          }
          hx_val = 0;
          got_c = 0;
          got_s = 0;
          who = 0;
          // assume string like 0x1c_csv1
          // -1 meeans don't mess with tcp_nodelay. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
          if (strlen(tmp_str) > 4 && strncmp(tmp_str, "0x", 2) == 0 && strchr(tmp_str, '_') != NULL) {
            hx_val = (int)strtol(tmp_str, &hx_end, 16);
            hx_end++;
            if (strchr(hx_end, 'c') != NULL) { got_c = 1; }
            if (strchr(hx_end, 's') != NULL) { got_s = 1; }
          } else {
            hx_val = (int)strtol(tmp_str, &hx_end, 10);
            if (strchr(hx_end, 'c') != NULL) { got_c = 1; }
            if (strchr(hx_end, 's') != NULL) { got_s = 1; }
          } 
          if (got_c == 1) { who |= 1;}
          if (got_s == 1) { who |= 2;}
          if (who == 0) { who = 3; }
          if (strcmp(tcp_lkfor[mm], "nodelay=") == 0) {
            // det is -1:  no chg to TCP_NODELAY. optionally add c|s|cs suffix to only do the chng on client, server or both respectively.
            tcp_nodelay = hx_val;
            tcp_nodelay_who = who;
            ret_val = parse_tcp_val(tmp_str, tcp_lkfor[mm]);
            if (ret_val != -1) {
               tcp_nodelay_val = ret_val;
            }
            printf("%s.%d %s where= %d, who= %d setto= %d\n", __FILE__, __LINE__, tcp_lkfor[mm], tcp_nodelay, tcp_nodelay_who, tcp_nodelay_val);
            continue;
          }
          if (strcmp(tcp_lkfor[mm], "cork=") == 0) {
            // -1 meeans don't mess with tcp_cork. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
            // det is -1:  no chg to TCP_NODELAY. optionally add c|s|cs suffix to only do the chng on client, server or both respectively.
            tcp_cork = hx_val;
            tcp_cork_who = who;
            ret_val = parse_tcp_val(tmp_str, tcp_lkfor[mm]);
            if (ret_val != -1) {
               tcp_cork_val = ret_val;
            }
            printf("%s.%d %s where= %d, who= %d setto= %d\n", __FILE__, __LINE__, tcp_lkfor[mm], tcp_cork, tcp_cork_who, tcp_cork_val);
            continue;
          }
          if (strcmp(tcp_lkfor[mm], "quickack=") == 0) {
            // -1 meeans don't mess with tcp_quickack. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
            // det is -1:  no chg to TCP_NODELAY. optionally add c|s|cs suffix to only do the chng on client, server or both respectively.
            tcp_quickack = hx_val;
            tcp_quickack_who = who;
            ret_val = parse_tcp_val(tmp_str, tcp_lkfor[mm]);
            if (ret_val != -1) {
               tcp_quickack_val = ret_val;
            }
            printf("%s.%d %s where= %d, who= %d setto= %d\n", __FILE__, __LINE__, tcp_lkfor[mm], tcp_quickack, tcp_quickack_who, tcp_quickack_val);
            continue;
          }
          if (strcmp(tcp_lkfor[mm], "maxseg=") == 0) {
            char *vpos;
            int   voff, slen;
            tcp_maxseg = hx_val;
            tcp_maxseg_who = who;
            printf("%s.%d tcp_maxseg str= %s, val= %d, who= %d\n", __FILE__, __LINE__, tmp_str, tcp_maxseg, tcp_maxseg_who);
            ret_val = parse_tcp_val(tmp_str, tcp_lkfor[mm]);
            if (ret_val != -1) {
               tcp_maxseg_val = ret_val;
            }
            printf("%s.%d %s where= %d, who= %d setto= %d\n", __FILE__, __LINE__, tcp_lkfor[mm], tcp_maxseg, tcp_maxseg_who, tcp_maxseg_val);
            continue;
          }
        }
       }
     }
     if (str[i] == ',') {
       fld_beg = 1;
     }
   }
   return 0;
}


int set_tcp_options(int sockfd, int pos, int line, char *do_what)
{
    int i, rc, flags;
    int flglen = sizeof(flags);
    int level=IPPROTO_TCP;
    rc = 0;
// get 74 MB/sec for 1 read+1write diff socckets is enable TCP_NODELAY and sock_rd != sock_wr on just the client (don't need to do it on server 
// get 30-70 MB/sec for 1 read+1write diff socckets if enable TCP_NODELAY at socket creation and sock_rd != sock_wr on just the client (don't need to do it on server 
// get 50-85 MB/sec for 1 read+1write same read+write soccket without any setsockopt 
#if 1
   for (i=0; i < sizeof(tcp_lkfor)/sizeof(tcp_lkfor[0]); i++) {
     if (strcmp(tcp_lkfor[i], "nodelay=") == 0) {
       if ((tcp_nodelay_who & CLNT_SRVR) && ((tcp_nodelay == 0 && pos == 0) || (tcp_nodelay > 0) && (tcp_nodelay & pos))) {
         flags = tcp_nodelay_val;
         if (setsockopt(sockfd, level, TCP_NODELAY, (void *)&flags, sizeof(flags))) {
           perror("ERROR: setsocketopt(), TCP_NODELAY"); 
           rc = 1;
           printf("%s.%d error on set socket called by line= %d doing %s\n", __FILE__, __LINE__, line, do_what);
         }
         flags = 0;
         flglen = sizeof(flags);
         rc = getsockopt(sockfd, level, TCP_NODELAY, &flags, &flglen);
         printf("%s.%d report on set socket %s got val= %d called by line= %d doing %s rc= %d\n", __FILE__, __LINE__, tcp_lkfor[i], flags,  line, do_what, rc);
       }
     }
     if (strcmp(tcp_lkfor[i], "cork=") == 0) {
       if ((tcp_cork_who & CLNT_SRVR) && ((tcp_cork == 0 && pos == 0) || (tcp_cork > 0) && (tcp_cork & pos))) {
         flags = tcp_cork_val; 
         if (setsockopt(sockfd, level, TCP_CORK, (void *)&flags, sizeof(flags))) {
           perror("ERROR: setsocketopt(), TCP_CORK"); 
           rc = 1;
           printf("%s.%d error on set socket called by line= %d doing %s\n", __FILE__, __LINE__, line, do_what);
         }
         flags = 0;
         flglen = sizeof(flags);
         rc = getsockopt(sockfd, level, TCP_CORK, &flags, &flglen);
         printf("%s.%d report on set socket %s got val= %d called by line= %d doing %s rc= %d\n", __FILE__, __LINE__, tcp_lkfor[i], flags,  line, do_what, rc);
       }
     }
     if (strcmp(tcp_lkfor[i], "quickack=") == 0) {
       if ((tcp_quickack_who & CLNT_SRVR) && ((tcp_quickack == 0 && pos == 0) || (tcp_quickack > 0) && (tcp_quickack & pos))) {
         flags = tcp_quickack_val;
         if (setsockopt(sockfd, level, TCP_QUICKACK, (void *)&flags, sizeof(flags))) {
           perror("ERROR: setsocketopt(), TCP_CORK"); 
           rc = 1;
           printf("%s.%d error on set socket called by line= %d doing %s\n", __FILE__, __LINE__, line, do_what);
         }
         flags = 0;
         flglen = sizeof(flags);
         rc = getsockopt(sockfd, level, TCP_QUICKACK, &flags, &flglen);
         printf("%s.%d report on set socket %s got val= %d called by line= %d doing %s rc= %d\n", __FILE__, __LINE__, tcp_lkfor[i], flags,  line, do_what, rc);
       }
     }
     if (strcmp(tcp_lkfor[i], "maxseg=") == 0) {
       if ((tcp_maxseg_who & CLNT_SRVR) && ((tcp_maxseg == 0 && pos == 0) || (tcp_maxseg > 0) && (tcp_maxseg & pos))) {
         //int level=SOL_SOCKET;
         flags = 0;
         //getsockopt(sockfd, IPPROTO_TCP, TCP_MAXSEG, &flags, &flglen);
         rc = getsockopt(sockfd, level, TCP_MAXSEG, &flags, &flglen);
         printf("%s.%d tcp_maxseg bef= %d, rc= %d\n", __FILE__, __LINE__, flags, rc);
         flags = tcp_maxseg_val; 
         if (setsockopt(sockfd, level, TCP_MAXSEG, (void *)&flags, sizeof(flags))) {
           perror("ERROR: setsocketopt(), TCP_MAXSEG"); 
           rc = 1;
           printf("%s.%d error on set socket called by line= %d doing %s\n", __FILE__, __LINE__, line, do_what);
         }
         printf("%s.%d try maxseg= %d\n", __FILE__, __LINE__, tcp_maxseg_val);
         flags = 0;
         flglen = sizeof(flags);
         //getsockopt(sockfd, IPPROTO_TCP, TCP_MAXSEG, &flags, &flglen);
         rc = getsockopt(sockfd, level, TCP_MAXSEG, &flags, &flglen);
         printf("%s.%d report on set socket %s got val= %d called by line= %d doing %s rc= %d\n", __FILE__, __LINE__, tcp_lkfor[i], flags,  line, do_what, rc);
       }
     }
   }
#endif
#if 0
    flags = 0;
    setsockopt(sockfd, IPPROTO_TCP, TCP_CORK, &flags, sizeof(flags));
    //flags = 1;
    //setsockopt(sockfd, IPPROTO_TCP, TCP_CORK, &flags, sizeof(flags));
    //flags = ~flags;
    //flags = 1;
    //setsockopt(sockfd, IPPROTO_TCP, TCP_CORK, &flags, sizeof(flags));
#endif
    return rc;
}

int parse_opt(int argc, char **argv)
{
           int flags, opt, outs_rd=-1, outs_wr=-1;
           char *cma=NULL, *outs_arg=NULL;

           while ((opt = getopt(argc, argv, "vhlB:D:d:H:o:p:s:t:T:")) != -1) {
               switch (opt) {
               case 'D':
                   // -1 meeans don't mess with tcp_nodelay. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
                   // det is -1:  no chg to TCP_NODELAY. optionally add c|s|cs suffix to only do the chng on client, server or both respectively.
                   parse_tcp_args(optarg);
                   break;
               case 'B':
                   bw_max = atof(optarg);
                   break;
               case 'H':
                   strncpy(host_ip, optarg, sizeof(host_ip)-1);
                   break;
               case 'd':
                   odir = optarg;
                   break;
               case 'l':
                   opt_do_lat = 0;
                   break;
               case 's':
                   msg_size = atoi(optarg);
                   break;
               case 't':
                   tm_run = atof(optarg);
                   break;
               case 'T':
                   total_messages = atoi(optarg);
                   break;
               case 'o':
                   outs_arg = optarg;
                   cma = strchr(optarg, ',');
                   if (cma == NULL) {
                     outs_rd = atoi(optarg);
                     outs_wr = outs_rd;
                   } else {
                     outs_rd = atoi(optarg);
                     outs_wr = atoi(cma+1);
                   }
                   break;
               case 'p':
                   cma = strchr(optarg, ',');
                   if (cma == NULL) {
                     port_rd = atoi(optarg);
                     port_wr = port_rd;
                   } else {
                     port_rd = atoi(optarg);
                     port_wr = atoi(cma+1);
                   }
                   break;
               case 'v':
                   verbose++;
                   break;
               default: /* '?' */
                   fprintf(stderr, "Usage: %s -t tm_to_run_secs -H host_ [-n] name\n",
                           argv[0]);
                   exit(EXIT_FAILURE);
               }
           }
           if ((outs_rd < 0 || outs_wr < 0) || (outs_rd == 0 && outs_wr == 0)) {
             printf("option -o arg either missing or invalid. syntx: -o x[,y] where x is outs_rds, y= outs_wr(def=outs_rd). ex: -o 1 or -o 1,1 or -o 2,2 or -o 2,1 or -o 10 (10 rds 10 wrs)\n");
             exit(1);
           }
           outstanding_requests[0] = outs_rd;
           outstanding_requests[1] = outs_wr;
           outstanding_requests[2] = outs_rd+outs_wr;

           //if (verbose > 0) {
             printf("tm_to_run_secs= %f host= %s port_rd= %d port_wr= %d msg_size= %d outstanding_requests= %d,%d\n", tm_run, host_ip, port_rd, port_wr, msg_size, outstanding_requests[0], outstanding_requests[1]);
           //}

#if 0
           if (optind >= argc) {
               fprintf(stderr, "Expected argument after options\n");
               exit(EXIT_FAILURE);
           }
#endif
}

#if 1
#define DO_LAT
#endif
#ifdef DO_LAT
uint64_t lat_idx=0, lat_idx_max, lat_idx_miss=0;
double lat_tm, *lat_beg;
float *lat_arr;

static void add_lat_data(double tm_beg, double tm_end)
{
  float lat_dff;
   
  lat_dff = (float)(tm_end - tm_beg);
  if (lat_idx < lat_idx_max) {
    lat_arr[lat_idx] = lat_dff;
    lat_idx++;
  } else {
    lat_idx_miss++;
  }
}
#endif

int func(int sockfd_rd, int sockfd_wr)
{
	int i, j, n, last_iter=0, min_of_outs=-1;
        double tm_rd0, tm_rd1, tm_rd2, tm_wr0, tm_wr1, tm_wr2, bytes_prev, bytes_dff, tm_rd_wr;
        double bytes_rd =0, bytes_wr= 0;
        double bw_max_bytes= 1e6*bw_max, bytes = 0, msgs= 0, tm_dff=0, tm_cur, tm_beg, loops=0;
        char *sbuf = NULL, *rbuf= NULL;
        size_t buf_sz = (msg_size+1)*sizeof(char);
        struct timespec req;
        double sleep_ns, tot_sleep_secs=0.0;

        if (outstanding_requests[0] < outstanding_requests[1]) {
          min_of_outs = outstanding_requests[0];
        } else {
          min_of_outs = outstanding_requests[1];
        }
        printf("%s.%d min_of_outs= %d out_st[0]= %d out_st[1]= %d\n", __FILE__, __LINE__, min_of_outs, outstanding_requests[0], outstanding_requests[1]);
        if (min_of_outs == 0) {
          if (outstanding_requests[0] == 0) {
            min_of_outs = outstanding_requests[1];
          }
          if (outstanding_requests[1] == 0) {
            min_of_outs = outstanding_requests[0];
          }
          printf("%s.%d min_of_outs= %d out_st[0]= %d out_st[1]= %d\n", __FILE__, __LINE__, min_of_outs, outstanding_requests[0], outstanding_requests[1]);
        }

        //sbuf = (char *)malloc((msg_size+1)*sizeof(char));
        //rbuf = (char *)malloc((msg_size+1)*sizeof(char));
        i = posix_memalign((void **)&sbuf, sysconf(_SC_PAGESIZE), buf_sz);
        i = posix_memalign((void **)&rbuf, sysconf(_SC_PAGESIZE), buf_sz);
#ifdef DO_LAT
        if (opt_do_lat == 1) {
        lat_idx_max = outstanding_requests[2] *  tm_run * 1000000;
        lat_beg = (double *)malloc((outstanding_requests[2]+1)*sizeof(double));
        lat_arr = (float *)malloc((lat_idx_max+1)*sizeof(float));
        }
#endif

	memset(sbuf, 's', msg_size);
	memset(rbuf, 'r', msg_size);
        sbuf[msg_size] = 0;
        rbuf[msg_size] = 0;
        tm_beg = get_dclock();
	for (;;) {
#define DBG_2
#ifdef DBG_2
                tm_wr0 = get_dclock();
                bytes_prev = bytes;
#endif
                if (outstanding_requests[1] > 0) {
                for (j=0; j < outstanding_requests[1]; j++) {
#ifdef DO_LAT
                  if (opt_do_lat == 1) {
                    lat_beg[j] = get_dclock();
                  }
#endif
		  n = write(sockfd_wr, sbuf, msg_size);
                  if (n < 0) {
                    perror("ERROR writing to socket");
                    printf("%s.%d got client err on write\n", __FILE__, __LINE__);
                    return 0;
                    //exit(1);
                  }
                  if (n == 0) {
                    printf("%s.%d got client err n=0 on write\n", __FILE__, __LINE__);
                    break;
                  }
                  if (n != msg_size) {
                    if (verbose > 1) {
                       printf("%s.%d got client err n= %d on write, expected to get msg_size %d\n", __FILE__, __LINE__, n, msg_size);
                    }
                    partial_msgs_wr++;
                    partial_bytes_wr += msg_size - n;
                    //break;
                  }
                  if (outstanding_requests[1] == 1) {
                    set_tcp_options(sockfd_wr, 2, __LINE__, "write");
                  }
#ifdef DO_LAT
                  if (opt_do_lat == 1) {
                  if (outstanding_requests[0] == 0) {
                    lat_tm = get_dclock();
                    if (j < min_of_outs) {
                      add_lat_data(lat_beg[j], lat_tm);
                    }
                  }
                  }
#endif
                    
                  bytes += n;
                  bytes_wr += n;
                  if (last_iter == 1) { break;}
#ifdef DO_LAT
                  if (opt_do_lat == 1) {
                  if (verbose > 1) {
                   printf("client write msg[%.0f] T(s)= %f\n", msgs, (lat_beg[j]-tm_beg));
                  }
                  }
#endif
                  msgs++;
                  if (total_messages > 0 && msgs >= total_messages) {
                     last_iter = 1;
                     break;
                  }
                }
                }
#ifdef DBG_2
                tm_wr1 = get_dclock();
                tm_wr2 = tm_wr1 - tm_wr0;
                if (verbose > 1) {
                printf("tm_wr msg= %.0f tm(us)= %.3f tm(us)/out= %.3f\n", msgs, 1e6*tm_wr2, 1e6*tm_wr2/(double)(outstanding_requests[1]));
                }
#endif
                if (last_iter == 1) { break;}
#ifdef DBG_2
                tm_rd0 = get_dclock();
#endif
                if (outstanding_requests[0] > 0) {
                for (j=0; j < outstanding_requests[0]; j++) {
#ifdef DO_LAT
                  if (opt_do_lat == 1) {
                  if (outstanding_requests[1] == 0) {
                    lat_beg[j] = get_dclock();
                  }
                  }
#endif
		  n = recv(sockfd_rd, rbuf, msg_size, MSG_WAITALL);
		  //n = read(sockfd_rd, rbuf, msg_size);
                  if (n < 0) {
                    perror("ERROR reading from socket");
                    printf("%s.%d got client err on read\n", __FILE__, __LINE__);
                    return 1;
                    //exit(1);
                  }
                  if (n == 0) {
                    printf("%s.%d got client err n=0 on read\n", __FILE__, __LINE__);
                    break;
                  }
#if 0
#if 0
                  if (n != msg_size) {
                    partial_msgs_rd++;
                    partial_bytes_rd += n;
                  }
#else
                  if (n != msg_size) {
                    int n2 = 0;
                    while(n < msg_size) {
		    //n2 = recv(sockfd_rd, rbuf+n, msg_size-n, MSG_WAITALL);
		    n2 = read(sockfd_rd, rbuf+n, msg_size-n);
                    partial_msgs_rd++;
                    partial_bytes_rd += n2;
                    if (n2 <= 0) {
                        last_iter = 1;
                        if (n2 < 0) {
                        perror("ERROR reading from socket");
                        printf("%s.%d server got err on read\n", __FILE__, __LINE__);
                        }
                        if (n2 < 0) {
                          return 1;
                        }
			break;
                        //exit(1);
                    }
                    n += n2;
                    }
                    if (verbose > 0) {
                    printf("%s.%d got client err n= %d on read, expected to get msg_size %d\n", __FILE__, __LINE__, n, msg_size);
                    }
                    if (n != msg_size) {
                      break;
                    }
                  }
#endif
#endif
                  if (outstanding_requests[0] == 1) {
                    set_tcp_options(sockfd_rd, 1, __LINE__, "read");
                  }
#ifdef DO_LAT
                  if (opt_do_lat == 1) {
                  lat_tm = get_dclock();
                  if (j < min_of_outs) {
                    add_lat_data(lat_beg[j], lat_tm);
                  }
                  if (verbose > 1) {
                   //printf("client read  msg[%.0f] T(s)= %f\n", msgs, (lat_tm-tm_beg));
                   printf("client read  msg[%.0f] T(s)= %f\n", msgs, 1e6*(lat_tm-tm_rd0));
                  }
                  }
#endif
                  //bytes += msg_size;
                  bytes += n;
                  bytes_rd += n;
                  msgs++;
                  if (total_messages > 0 && msgs >= total_messages) {
                     last_iter = 1;
                     break;
                  }
                }
                }
#ifdef DBG_2
                tm_rd1 = get_dclock();
                tm_rd2 = tm_rd1 - tm_rd0;
                if (verbose > 1) {
                printf("tm_rd msg= %.0f tm(us)= %.3f tm(us)/out= %.3f\n", msgs, 1e6*tm_rd2, 1e6*tm_rd2/(double)(min_of_outs));
                }
                if (bw_max > 0) {
                  bytes_dff = bytes - bytes_prev;
                  //tm_rd_wr = tm_rd1 - tm_wr0;
                  tm_rd_wr = tm_rd1 - tm_beg;
                  //sleep_ns = bytes_dff / bw_max_bytes - tm_rd_wr;
                  sleep_ns = bytes / bw_max_bytes - tm_rd_wr;
                  if (sleep_ns > 0.0) {
                     tot_sleep_secs += sleep_ns;
                     req.tv_sec = (int)sleep_ns;
                     sleep_ns -= req.tv_sec;
                     sleep_ns *= 1e9;
                     req.tv_nsec = sleep_ns;
                     nanosleep(&req, NULL);
                  }
                }
#endif
                if (last_iter == 1) { break; }
                tm_cur = get_dclock();
                tm_dff = tm_cur - tm_beg;
                if (tm_run > 0.0 && tm_dff > tm_run) {
                   break;
                   strcpy(sbuf, "exit");
                   last_iter = 1;
                }
	}
        //if (tot_sleep_secs > 0.0) {
          printf("tcp_client.x tot_sleep_secs= %f\n", tot_sleep_secs);
        //}
        if (tm_dff > 0) {
          printf("MB/sec= %.3f elap_secs= %.3f msgs= %.0f rpsK= %.3f\n", 1e-6*bytes/tm_dff, tm_dff, msgs, 0.001*msgs/tm_dff);
          printf("rd MB/sec= %.3f wr MB/sec= %.3f\n", 1e-6*bytes_rd/tm_dff, 1e-6*bytes_wr/tm_dff);
          printf("partial_msgs rd= %.0f bytes= %.0f wr= %.0f bytes= %.0f\n", partial_msgs_rd, partial_bytes_rd, partial_msgs_wr, partial_bytes_wr);
#ifdef DO_LAT
          if (opt_do_lat == 1) {
          tm_rd1 = get_dclock();
          printf("lat_idx_used= %.0f of max=  %.0f missed= %.0f\n", (double)lat_idx, (double)lat_idx_max, (double)lat_idx_miss);
          //qsort(lat_arr, lat_idx, sizeof(lat_arr[0]), compare); // doesn't take too long
          FILE* lat;
          char filename[256];
          char *udir = (odir == NULL ? "tmp" : odir);
          int n = sprintf(filename, "%s/tcp_client_%d_latency.txt", udir, port_rd);
          lat = fopen(filename, "w+");
          if (lat == NULL) { printf("tcp_client.x failed to open latency file %s\n", filename); }
          else {
#if 1
            size_t fl_wr_bytes = fwrite(lat_arr, sizeof(lat_arr[0]), lat_idx, lat);
            printf("wrote %.0f items for size= %.0f bytes at %s %d\n", (double)lat_idx, (double)(lat_idx)*(double)sizeof(lat_arr[0]), __FILE__, __LINE__);
#else
            uint64_t k;
            for (k=0; k < lat_idx; k++) {
               fprintf(lat, "%f\n", 1e6*lat_arr[k]);
            }
#endif
            fclose(lat);
          }
          tm_rd2 = get_dclock();
          printf("writing latency data took %.5f seconds for file= %s at %s %d\n", tm_rd2-tm_rd1, filename, __FILE__, __LINE__);
          } else {
            printf("skip latency data due to -l option at %s %d\n", __FILE__, __LINE__);
          }
#endif
        }
        return 0;
}

int main(int argc, char **argv)
{
	int flglen, flags, rc = 0, i, port, sockfd[]={-2, -2}; // , connfd[2];
	struct sockaddr_in servaddr[2]; //, cli;
        struct sigaction a;
        double tm_beg, tm_rdy, tm_aft_func, tm_end;
        tm_beg = get_dclock();

#if 0
        a.sa_handler = sighandler;
        a.sa_flags = 0;
        sigemptyset( &a.sa_mask );
        sigaction( SIGINT, &a, NULL );
#else
        signal(SIGINT, &sighandler);
#endif

	parse_opt(argc, argv);;

        for (i=0; i < 2; i++) {
          if (i == 0) {
            port = port_rd;
          } else {
            if (port_wr != port_rd) {
              port = port_wr;
            } else {
              sockfd[1] = sockfd[0];
              break;
            }
          }
          if (verbose > 0) {
             printf("%s.%d beg open port port[%d]= %d\n", __FILE__, __LINE__, i, port);
          }
	  // socket create and verification
	  sockfd[i] = socket(AF_INET, SOCK_STREAM, 0);
	  if (sockfd[i] == -1) {
		printf("socket creation failed...\n");
                rc = 1;
                break;
	  }
          set_tcp_options(sockfd[i], 4, __LINE__, "aft_create_socket");
 
	  bzero(&servaddr[i], sizeof(servaddr[0]));

	  // assign IP, PORT
	  servaddr[i].sin_family = AF_INET;
	  servaddr[i].sin_addr.s_addr = inet_addr(host_ip);
	  servaddr[i].sin_port = htons(port);

          set_tcp_options(sockfd[i], 8, __LINE__, "before_connect");
	  // connect the client socket to server socket
	  if (connect(sockfd[i], (SA*)&servaddr[i], sizeof(servaddr[0])) != 0) {
		printf("connection with the server failed...\n");
                rc = 1;
                break;
	  }
          if (verbose > 0) {
             printf("%s.%d opened rc= %d port[%d]= %d successfully\n", __FILE__, __LINE__, rc, i, port);
          }
#if 0
#if 1
flags = 1;
flglen = sizeof(flags);
getsockopt(sockfd[i], IPPROTO_TCP, TCP_CORK, &flags, &flglen);
printf("bef tcp_cork= %d\n", flags);
flags = 0;
setsockopt(sockfd[i], IPPROTO_TCP, TCP_CORK, &flags, sizeof(flags));
#endif
#if 1
flags = 1;
flglen = sizeof(flags);
getsockopt(sockfd[i], IPPROTO_TCP, TCP_QUICKACK, &flags, &flglen);
printf("bef quickack= %d\n", flags);
#endif
#if 1
flags = 1;
setsockopt(sockfd[i], IPPROTO_TCP, TCP_QUICKACK, &flags, sizeof(flags));
#endif

#endif
#if 0
          flags =1; 
          if (setsockopt(sockfd[i], IPPROTO_TCP, TCP_NODELAY, (void *)&flags, sizeof(flags))) { perror("ERROR: setsocketopt(), TCP_NODELAY"); exit(0); }; 
#endif
          set_tcp_options(sockfd[i], 0, __LINE__, "setup");
        }

	// function for chat
        if (verbose > 0) {
           printf("%s.%d rc= %d begin transactions with port_rd= %d port_wr= %d rd_rd= %d wr_fd= %d\n", __FILE__, __LINE__, rc, port_rd, port_wr, sockfd[0], sockfd[1]);
        }
        tm_rdy = get_dclock();
        if (rc == 0) {
	  rc = func(sockfd[0], sockfd[1]);
        }
        tm_aft_func = get_dclock();

	// close the socket
        for (i=0; i < 2; i++) {
          if (sockfd[i] > -1) {
            if (i == 0 || port_rd != port_wr) {
	      close(sockfd[i]);
            }
            sockfd[i] = 2;
          }
        }
        tm_end = get_dclock();
        if (verbose > 0) {
           printf("%s.%d rc= %d at end with port_rd= %d port_wr= %d rd_rd= %d wr_fd= %d\n", __FILE__, __LINE__, rc, port_rd, port_wr, sockfd[0], sockfd[1]);
        }
        printf("%s.%d port_rd= %d tm_till_rdy= %.6f rdy_to_aft_func= %.6f tm_aft_func_to_end= %.6f tm_tot= %.6f ts_bef_func= %.6f\n",
           __FILE__, __LINE__, port_rd, tm_rdy-tm_beg, tm_aft_func-tm_rdy, tm_end-tm_aft_func, tm_end-tm_beg, tm_rdy);

        fflush(NULL);
        return rc;
}

