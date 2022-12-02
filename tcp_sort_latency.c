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
#include <sys/stat.h>


#define MAX 1024
#define NMAX 1024
#define PORT 8080
#define SA struct sockaddr

// below sets flag to query if we are on client or server. 1 is client, 2 is server
#define CLNT_SRVR 1

double tm_run = 0.0;
double bw_max = 0.0;
int verbose = 0;

double pxx_arr[]={10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 99.5, 99.9, 99.999, 100};
char  *pxx_pct[]={"10", "20", "30", "40", "50", "60", "70", "80", "90", "95", "99", "99.5", "99.9", "99.999", "100"};

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
static char *opt_file_in = NULL;
static char *opt_file_out = NULL;

static int compare (const void * a, const void * b)
{
  if (*(float*)a > *(float*)b) return 1;
  else if (*(float*)a < *(float*)b) return -1;
  else return 0;  
}

int parse_opt(int argc, char **argv)
{
    int opt;
           while ((opt = getopt(argc, argv, "vhi:o:")) != -1) {
               switch (opt) {
               case 'i':
                   // -1 meeans don't mess with tcp_nodelay. 0 means do it at socket creation. 1 means do it each write. 2 means do it each read 3 means both rd+wr
                   // det is -1:  no chg to TCP_NODELAY. optionally add c|s|cs suffix to only do the chng on client, server or both respectively.
                   opt_file_in = optarg;
                   break;
               case 'o':
                   opt_file_out = optarg;
                   break;
               case 'v':
                   verbose++;
                   break;
               default: /* '?' */
                   fprintf(stderr, "Usage: %s -i binary_input_file [ -o output_pXX_stat_file ]\n", argv[0]);
                   fprintf(stderr, "  reads, sorts binary input file and computes pXX stats to either stdout or a -o output_file\n");
                   exit(EXIT_FAILURE);
               }
           }

}

uint64_t lat_idx=0, lat_idx_max, lat_idx_miss=0, lat_sz=0;
double lat_tm, *lat_beg;
float *lat_arr;

#if 0
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

int read_sort_compute_pxx(char *file_in, char *file_out)
{
    double tm_rd1, tm_rd2, tm_srt1, tm_srt2, sz;
    FILE* lat;
    int i, rc;
    char filename[256];
    struct stat buf;
    int64_t idx;

    tm_rd1 = get_dclock();
    rc = stat(file_in, &buf);
    if (rc == -1) {
        perror("error on stat of file: ");
        printf("err on stat of file= %s at %s %d\n", file_in, __FILE__, __LINE__);
        exit(1);
    }
 
    if (buf.st_size == 0) { printf("err on fstat. file size= 0 at %s %d\n", __FILE__, __LINE__); exit(1);}
    lat = fopen(file_in, "r");
    if (lat == NULL) {
        printf("%s.%d failed to open latency file %s\n", __FILE__, __LINE__, file_in);
        exit(1);
    }

    lat_sz = (uint64_t)buf.st_size;
    size_t lat_floats = lat_sz / sizeof(float);
    printf("file size= %.0f bytes with %.0f floats at %s %d\n", (double)lat_sz, (double)lat_floats, __FILE__, __LINE__);

    size_t p50_i = lat_floats / 2;
    lat_arr = (float *)malloc(lat_sz+sizeof(lat_arr[0]));
    if (lat_arr == NULL) {
        printf("failed to alloc array at %s %d\n", __FILE__, __LINE__);
        exit(1);
    }
    size_t fl_rd_bytes = fread(lat_arr, sizeof(lat_arr[0]), lat_floats, lat);
    fclose(lat);
    tm_rd2 = get_dclock();
    tm_srt1 = tm_rd2;
    qsort(lat_arr, lat_floats, sizeof(lat_arr[0]), compare); // doesn't take too long
    tm_srt2 = get_dclock();
    
    //printf("latency pct= %s latency(usecs)= %s\n", lat_lkup[i], $1);
    //printf("lat_idx_used= %.0f of max=  %.0f missed= %.0f\n", (double)lat_idx, (double)lat_idx_max, (double)lat_idx_miss);
    for (i=0; i < sizeof(pxx_arr)/sizeof(pxx_arr[0]); i++) {
      idx = 0.01 * pxx_arr[i]*(lat_floats-1);
      if (idx < 0) { idx = 0;}
      if (idx > (lat_floats-1)) { idx = lat_floats-1;}
      printf("latency pct= %s latency(usecs)= %.4f\n", pxx_pct[i], 1e6*lat_arr[idx]);
    }
    printf("did_sort min= %f p50= %f max= %f at %s %d\n", 1e6*lat_arr[0], 1e6*lat_arr[p50_i], 1e6*lat_arr[lat_floats-1], __FILE__, __LINE__);

    printf("latency data: reading file took %.5f secs, sorting took %.5f seconds for file= %s at %s %d\n", tm_rd2-tm_rd1, tm_srt2-tm_srt1,  file_in, __FILE__, __LINE__);
    return 0;
}

int main(int argc, char **argv)
{
        struct sigaction a;
        int rc = 0;

        signal(SIGINT, &sighandler);

	parse_opt(argc, argv);;

        if (opt_file_in == NULL) {
            printf("need to specify -i input_latency_binary_file [ -o output file ]. missing input file at %s %d\n", __FILE__, __LINE__);
            exit(1);
        }
        read_sort_compute_pxx(opt_file_in, opt_file_out);

        printf("finished with rc= %d at %s %d\n", rc, __FILE__, __LINE__);
        return rc;
}

