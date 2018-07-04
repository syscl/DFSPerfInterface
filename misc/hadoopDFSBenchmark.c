//
// hadoopDFSBenchmark.c
// hadoopDFSBenchmark
//
//  Created by Yating Zhou (aka syscl) on 17/11/17.
//  Copyright (c) 2017 syscl. All rights reserved.
//
// This work is licensed under the Creative Commons Attribution-NonCommercial
// 4.0 Unported License => http://creativecommons.org/licenses/by-nc/4.0
//
// compile it with: gcc hadoopDFSBenchmark.c -o dfschk -lm
//
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include "hadoopDFSBenchmark.h"
#include "syscl_lib.h"

//============================start=============================================

int main(int argc, char **argv) 
{
    int i = 0; // for C99 backward compatible
    int j = 0; // for C99 backward compatible
    int k = 0; // for C99 backward compatible
    //
    // Now let's do read/write (RW) test on DFS (e.g. HDFS, orangeFS)
    // 
    // kPerformTestOnDFS[i] => for R/W operation
    for (i = 0; i < getArrayLength(kPerformTestOnDFS); i++) {
        gTestArgs[kPerformRWTestIndex] = kPerformTestOnDFS[i];
        // kGenFileCount[j] => number of files that will be generated
        for (j = 0; j < getArrayLength(kGenFileCount); j++) {
            gTestArgs[kGenFileNrIndex] = kGenFileCount[j];
            // kFileSize[k] => size of files that will be generated
            for (k = 0; k < getArrayLength(kFileSize); k++) {
                gTestArgs[kFileSzIndex] = kFileSize[k];
                execvp2(*gTestArgs, gTestArgs);
            }
        }
    }
    return 0;
}

//==============================================================================
// execvp2(...): execvp wrapper: execute code in child process then wait
//==============================================================================

int execvp2(const char *file, char *const args[])
{
    pid_t rc;
    int ret = 0;
    if ((rc = fork()) > 0) {
        wait(NULL);
    } else if (rc == 0) {
        // child process
        ret = execvp(file, args);
    } else {
        //
        // fork failed
        //
        tslog(FAIL, "fork init failed\n");
        ret = -1;
    }
    return ret;
}

//==============================================================================
// detach(...): notify a node to detach
//==============================================================================

void detach()