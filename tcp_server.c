// based on https://www.geeksforgeeks.org/tcp-server-client-implementation-in-c/
#include <stdio.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <sys/types.h>          /* See NOTES */
#include <sys/socket.h>
#include <netinet/tcp.h>

#define MAX 1024
#define NMAX 1024
#define PORT 8080
#define SA struct sockaddr

// below sets flag to query if we are on client or server. 1 is client, 2 is server
#define CLNT_SRVR 2

double tm_run=0.0;
char host_ip[256];
char *odir = NULL;
int port_rd=8000;
int port_wr=8000;
int verbose = 0;
int outstanding_requests[]={1,1,2};
int msg_size = 1024;
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
int tcp_lkfor_len[] = {0, 0, 0, 0};
char *tcp_lkfor[] = {"nodelay=", "cork=", "quickack=", "maxseg="};
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
        int rc;
	rc = clock_gettime(CLOCK_MONOTONIC, &tp);
	return (double)(tp.tv_sec) + 1e-9 * (double)(tp.tv_nsec);
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
   int i, fld_beg=1, j, k, mm, len, ret_val;
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
        if ((len-i) > tcp_lkfor_len[mm] && memcmp(str+i, tcp_lkfor[mm], tcp_lkfor_len[mm]) == 0) {
          fld_beg = 0;
          j = i+tcp_lkfor_len[mm];
          arg = str+j;
          k = 0;
          printf("%s.%d start tcp_opt str= %s\n", __FILE__, __LINE__, arg);
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
            // -1 means don't mess with tcp_nodelay. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
            // det is -1:  no chg to TCP_NODELAY. optionally add c|s|cs suffix to only do the chng on client, server or both respectively.
            //tcp_nodelay = atoi(tmp_str); // -1 means don't mess with tcp_nodelay. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
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
            // -1 means don't mess with tcp_cork. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
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
            // -1 means don't mess with tcp_quickack. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
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
           perror("ERROR: setsocketopt(), TCP_QUICKACK"); 
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

extern char *optarg;
extern int optind, opterr, optopt;

int parse_opt(int argc, char **argv)
{
           int flags, opt, outs_rd=-1, outs_wr=-1;
           char *cma=NULL, *outs_arg=NULL;

           while ((opt = getopt(argc, argv, "vhD:d:H:o:p:s:t:")) != -1) {
               switch (opt) {
               case 'D':
                   parse_tcp_args(optarg);
                   break;
               case 'H':
                   strncpy(host_ip, optarg, sizeof(host_ip)-1);
                   break;
               case 'd':
                   odir = optarg;
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
               case 's':
                   msg_size = atof(optarg);
                   break;
               case 't':
                   tm_run = atof(optarg);
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
             printf("option -o arg either missing or invalid. must be >= 0. Can't be 0,0. syntx: -o x[,y] where x is outs_rds, y= outs_wr(def=outs_rd). ex: -o 1 or -o 1,1 or -o 2,2 or -o 2,1 or -o 10 (10 rds 10 wrs)\n");
             exit(1);
           }
           outstanding_requests[0] = outs_rd;
           outstanding_requests[1] = outs_wr;
           outstanding_requests[2] = outs_rd+outs_wr;

           if (verbose > 0) {
             printf("tm_to_run_secss= %f host= %s port_wr= %d port_rd= %d msg_size= %d outstanding_requests= %d,%d\n", tm_run, host_ip, port_rd, port_wr, msg_size, outstanding_requests[0], outstanding_requests[1]);
           }

           //if (optind >= argc) {
           //    fprintf(stderr, "Expected argument after options\n");
           //    exit(EXIT_FAILURE);
           //}
}

int func(int connfd_rd, int connfd_wr)
{
	int i=0, last_iter=0, j, n;
        double loops=0,  bytes = 0, msgs= 0, tm_dff=0.0, tm_cur, tm_beg = get_dclock(), tm_rd=0, tm_wr=0;
        double bytes_rd =0, bytes_wr= 0;
        char *sbuf = NULL, *rbuf= NULL;
        size_t buf_sz = (msg_size+1)*sizeof(char);

        //sbuf = (char *)malloc(buf_sz);
        i = posix_memalign((void **)&sbuf, sysconf(_SC_PAGESIZE), buf_sz);
        i = posix_memalign((void **)&rbuf, sysconf(_SC_PAGESIZE), buf_sz);
        //rbuf = (char *)malloc(buf_sz);
	memset(sbuf, 's', msg_size);
	memset(rbuf, 'r', msg_size);
        sbuf[msg_size] = 0;
        rbuf[msg_size] = 0;
	for (;;) {
                if (verbose > 1) {
                  tm_rd = get_dclock();
                }
                if (outstanding_requests[1] > 0) {
                for (j=0; j < outstanding_requests[1]; j++) {
		  //n = read(connfd_rd, rbuf, msg_size);
		  n = recv(connfd_rd, rbuf, msg_size, MSG_WAITALL);
                  if (n <= 0) {
                        last_iter = 1;
                        if (n < 0) {
                        perror("ERROR reading from socket");
                        printf("%s.%d server got err on read\n", __FILE__, __LINE__);
                        }
                        if (n < 0) {
                          return 1;
                        }
			break;
                    //exit(1);
                  }
#if 0
                  if (n != msg_size) {
                    int n2 = 0;
                    while(n < msg_size) {
		    //n2 = read(connfd_rd, rbuf+n, msg_size-n);
		    n2 = recv(connfd_rd, rbuf+n, msg_size-n, MSG_WAITALL);
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
                  //if (n != msg_size) {
                  // continue;
                  //}
                  }
#endif
                  if (outstanding_requests[0] == 1) {
                    set_tcp_options(connfd_rd, 1, __LINE__, "read");
                  }
#if 0
		  if ((memcmp(rbuf, "exit", 4)) == 0) {
			printf("server Exit...\n");
                        last_iter = 1;
			break;
		  }
#endif
                  //bytes += msg_size;
                  bytes += n;
                  bytes_rd += n;
                  msgs  += 1;
                  loops += 1.0;
                }
                }
                if (last_iter == 1) { break; }
                if (verbose > 1) {
                   //printf("client read  msg[%.0f] T(s)= %f\n", msgs, (lat_tm-tm_beg));
                   tm_wr = get_dclock();
                   printf("server read  msg[%.0f] T(s)= %f\n", msgs, 1e6*(tm_wr-tm_rd));
                }

                if (outstanding_requests[0] > 0) {
                for (j=0; j < outstanding_requests[0]; j++) {
		  n = write(connfd_wr, sbuf, msg_size);
                  if (n <= 0) {
                        last_iter = 1;
                        if (n = 0) {
                        perror("ERROR writing to socket");
                        printf("%s.%d server got err on write\n", __FILE__, __LINE__);
                        }
                        if (n < 0) {
                          return 1;
                        }
			break;
                    exit(1);
                  }
                  if (n != msg_size) {
                    if (verbose > 0) {
                    printf("%s.%d got client err n= %d on write, expected to get msg_size %d\n", __FILE__, __LINE__, n, msg_size);
                    }
                    partial_msgs_wr++;
                    partial_bytes_wr += msg_size - n;
                    //continue;
                  }
                  if (outstanding_requests[0] == 1) {
                    set_tcp_options(connfd_wr, 2, __LINE__, "write");
                  }
                  bytes += n;
                  bytes_wr += n;
                  msgs  += 1;
                }
                }

		// if msg contains "Exit" then server exit and chat ended.
                tm_cur = get_dclock();
                tm_dff = tm_cur - tm_beg;
                if (last_iter == 1) { break; }
                if (verbose > 1) {
                   printf("server write msg[%.0f] T(s)= %f\n", msgs, 1e6*(tm_cur-tm_wr));
                }
	}
        if (tm_dff > 0.0) {
          printf("MB/sec= %.3f elap_secs= %.3f msgs= %.0f rpsK= %.3f\n", 1e-6*bytes/tm_dff, tm_dff, msgs, 0.001*msgs/tm_dff);
          printf("rd MB/sec= %.3f wr MB/sec= %.3f\n", 1e-6*bytes_rd/tm_dff, 1e-6*bytes_wr/tm_dff);
          printf("partial_msgs rd= %.0f bytes= %.0f wr= %.0f bytes= %.0f\n", partial_msgs_rd, partial_bytes_rd, partial_msgs_wr, partial_bytes_wr);
        }
        return 0;
}




// Driver function
int main(int argc, char **argv)
{
	int flglen, flags, rc = 0, i, port, sockfd[2], connfd[]={-2, -2}, len;
	struct sockaddr_in servaddr[2], cli[2];
        struct sigaction a;
        double tm_beg, tm_rdy, tm_aft_func, tm_end;
        tm_beg = get_dclock();

        a.sa_handler = sighandler;
        a.sa_flags = 0;
        sigemptyset( &a.sa_mask );
        sigaction( SIGINT, &a, NULL );
        //signal(SIGINT, &sighandler);

        parse_opt(argc, argv);

        for (i=0; i < 2; i++) {
          if (i == 0) {
            port = port_rd;
          } else {
            if (port_rd != port_wr) {
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
           if (verbose > 0) {
             printf("%s.%d do open socket port [%d]= %d\n", __FILE__, __LINE__, i, port);
           }
	   sockfd[i] = socket(AF_INET, SOCK_STREAM, 0);
	   if (sockfd[i] == -1) {
		printf("socket creation failed...\n");
                rc = 1;
                break;
	   }
           set_tcp_options(sockfd[i], 4, __LINE__, "aft_create_socket");
#if 0
#if 1
flags = 1;
flglen = sizeof(flags);
getsockopt(sockfd[i], IPPROTO_TCP, TCP_CORK, &flags, &flglen);
printf("tcp_cork= %d\n", flags);
flags = 0;
setsockopt(sockfd[i], IPPROTO_TCP, TCP_CORK, &flags, sizeof(flags));
#endif
#if 1
flags = 0;
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

	   bzero(&servaddr[i], sizeof(servaddr[0]));

	   // assign IP, PORT
	   servaddr[i].sin_family = AF_INET;
	   servaddr[i].sin_addr.s_addr = htonl(INADDR_ANY);
	   servaddr[i].sin_port = htons(port);

           if (verbose > 0) {
             printf("%s.%d do bind socket port [%d]= %d\n", __FILE__, __LINE__, i, port);
           }
	   // Binding newly created socket to given IP and verification
	   if ((bind(sockfd[i], (SA*)&servaddr[i], sizeof(servaddr[0]))) != 0) {
                perror("bind socket ");
		printf("socket bind failed...\n");
                rc = 1;
                break;
	   }

           if (verbose > 0) {
             printf("%s.%d do listen socket port [%d]= %d\n", __FILE__, __LINE__, i, port);
           }
	   // Now server is ready to listen and verification
	   if ((listen(sockfd[i], 2)) != 0) {
                perror("listen socket ");
		printf("Listen failed...\n");
                rc = 1;
                break;
	   }
        }
        if (rc == 0) {
        if (verbose > 0) {
              printf("%s.%d rc= %d begin accept with port_rd= %d port_wr= %d rd_rd= %d wr_fd= %d\n", __FILE__, __LINE__, rc, port_rd, port_wr, connfd[0], connfd[1]);
        }
        for (i=0; i < 2; i++) {
          if (i == 1 && port_rd == port_wr) {
            connfd[1] = connfd[0];
            break;
          }
             
	  len = sizeof(cli[i]);

           if (verbose > 0) {
             printf("%s.%d do accept socket port [%d]= %d\n", __FILE__, __LINE__, i, port);
           }
	   // Accept the data packet from client and verification
           set_tcp_options(sockfd[i], 8, __LINE__, "before_accept");
	   connfd[i] = accept(sockfd[i], (SA*)&cli[i], &len);
	   if (connfd[i] < 0) {
                perror("accept socket ");
		printf("server accept failed...\n");
                rc = 1;
                break;
	   }
           if (verbose > 0) {
             printf("%s.%d accepted port[%d]= %d successfully\n", __FILE__, __LINE__, i, port);
           }
           set_tcp_options(connfd[i], 0, __LINE__, "after_connect");
        }
        }

	// Function for chatting between client and server
        if (verbose > 0) {
              printf("%s.%d rc= %d begin transactions with port_rd= %d port_wr= %d rd_rd= %d wr_fd= %d\n", __FILE__, __LINE__, rc, port_rd, port_wr, connfd[0], connfd[1]);
        }
        tm_rdy = get_dclock();
        if (rc == 0) {
	  rc = func(connfd[1], connfd[0]); // reverse order so that client agrees with port doing reads and port doing writes
        }
        tm_aft_func = get_dclock();

	// After chatting close the socket
        for (i=0; i < 2; i++) {
          if (sockfd[i] > -1) {
            if (i == 0 || port_rd != port_wr) {
	      close(sockfd[i]);
            }
            sockfd[i] = -2;
          }
        }
        tm_end = get_dclock();
        if (verbose > 0) {
           printf("%s.%d rc= %d at end with port_rd= %d port_wr= %d rd_rd= %d wr_fd= %d\n", __FILE__, __LINE__, rc, port_rd, port_wr, connfd[0], connfd[1]);
        }
        printf("%s.%d port_rd= %d tm_till_rdy= %.6f rdy_to_aft_func= %.6f tm_aft_func_to_end= %.6f tm_tot= %.6f ts_bef_func= %.6f\n",
           __FILE__, __LINE__, port_rd, tm_rdy-tm_beg, tm_aft_func-tm_rdy, tm_end-tm_aft_func, tm_end-tm_beg, tm_rdy);
        fflush(NULL);
        return rc;
}

