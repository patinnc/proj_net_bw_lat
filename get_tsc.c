
#include <stdio.h>
#include <inttypes.h>
#include <stdint.h>
#ifdef __x86_64__
    // do x64 stuff
#include <x86intrin.h>
#endif

#include <time.h>

static uint64_t get_tsc_cpu_node(uint32_t *cpu, uint32_t *node) {
  uint32_t aux=0;
  uint64_t tsc = 0;
#ifdef __x86_64__
  tsc = __rdtscp(&aux);
  *node = ((aux >> 12) & 0xf);
  *cpu  = (aux & 0xfff);
#elif __aarch64__
  //int rc;
  //rc = getcpu(cpu, &node);
  *cpu = mygetcpu();
  *node = 0;
  tsc = get_arm_cyc();
#endif
  return tsc;
}

int main(int argc, char **argv) {
   uint32_t cpu, node, cpu1;
   int i, switches=0, iters=0;
   uint64_t tsc0, tsc, tsc1;
   int64_t tsc_dff, tsc_dff_cumu=0;
   struct timespec tp;

     tsc0 = get_tsc_cpu_node(&cpu, &node);
   for (i=0; i < 20000000; i++) {
     tsc = get_tsc_cpu_node(&cpu, &node);
     //printf("cpu= %d node= %d\n", cpu, node);
     clock_gettime(CLOCK_MONOTONIC, &tp);
     tsc1 = get_tsc_cpu_node(&cpu1, &node);
     if (cpu1 != cpu) {
        switches++;
        tsc_dff = (int64_t)(tsc1) - (int64_t)(tsc);
        printf("switch %d cpu %d -> %d tsc_dff= %.3f\n", switches, cpu, cpu1, (double)tsc_dff);
        tsc_dff_cumu += tsc_dff;
        cpu = cpu1;
     }
     iters++;
   }
   printf("switches= %d iters= %d\n", switches, iters);
   printf("tsc_dff_cumu(ns)= %f\n", 1e9*(double)(tsc_dff_cumu));
   printf("svg tsc_dff= %.3f\n", (double)(tsc1-tsc0)/(double)(iters));
   return 0;
}

