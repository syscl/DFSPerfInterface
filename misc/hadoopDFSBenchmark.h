//
// hadoopDFSBenchmark.h
// hadoopDFSBenchmark
//
//  Created by Yating Zhou (aka syscl) on 17/11/17.
//  Copyright (c) 2017 syscl. All rights reserved.
//
// This work is licensed under the Creative Commons Attribution-NonCommercial
// 4.0 Unported License => http://creativecommons.org/licenses/by-nc/4.0

#ifndef __hadoopDFSBenchmark_H__
#define __hadoopDFSBenchmark_H__

#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>


// Perform R/W Test
#define kPerformRWTestIndex 4
char *kPerformTestOnDFS[] = { "-write", "-read" };

//
// Number of files Index
// Number of files that will be generated
// Change it if you want
//
#define kGenFileNrIndex     6
char *kGenFileCount[] = { "16", "32", "64" };

// FileSize Index
#define kFileSzIndex        8
// Size of files that will be generated
// Change the arrays if you want 
char *kFileSize[]     = { "1MB", "2MB", "4MB" };
// Result path Index
#define kResultFileIndex    10

//
// Argument list
//
char *gTestArgs[] = {
    "/opt/hadoop-2.8.2/bin/hadoop",
    "jar",
    "/opt/hadoop-2.8.2/share/hadoop/mapreduce/hadoop-mapreduce-client-jobclient-2.8.2-tests.jar",
    "TestDFSIO",
    NULL,
    "-nrFiles",
    NULL,
    "-fileSize", 
    NULL,
    "-resFile", 
    "/tmp/HadoopDFSBenchmarkResult.log",
    NULL
};

// private function declare here
static int execvp2(const char *file, char *const args[]);
//static void detach()

#endif
