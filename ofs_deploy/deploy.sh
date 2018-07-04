#!/bin/bash

#
# (c) 2017-2018 syscl
# Auto deploy enviroment on Hadoop v2.x with OrangeFS 2.x and HDFS
#
# Project: Performance tunning for OrangeFS on Hadoop (Advance Operating Systems/Data Intensive Computing)
#

#================================= GLOBAL VARS ==================================

#
# The script expects '0.5' but non-US localizations use '0,5' so we export
# LC_NUMERIC here (for the duration of the deploy.sh) to prevent errors.
#
export LC_NUMERIC="en_US.UTF-8"

#
# Prevent non-printable/control characters.
#
unset GREP_OPTIONS
unset GREP_COLORS
unset GREP_COLOR

#
# Display style setting.
#
BOLD="\033[1m"
RED="\033[1;31m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
OFF="\033[m"

#
# Define two status: 0 - Success, Turn on,
#                    1 - Failure, Turn off
#
kBASHReturnSuccess=0
kBASHReturnFailure=1
#
# gDebug use to control debug 
#           kBASHReturnFailure - quiet
#           kBASHReturnSuccess - verbose 
#
gDebug=${kBASHReturnFailure}

#
# Located repository.
#
gREPO=$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)
gKernelVersion=$(uname -r)
# get major part of the kernel (e.g. 4.xx)
gKernelMajor=$(printf ${gKernelVersion:0:1})
gKernelMinor=$(printf ${gKernelVersion:2:2} |sed 's/\.//g')
# orangeFS (ofs) will use kernel module greater than 4.6
gKernelMajorEdge="4"
gKernelMinorEdge="6"
#
# check if we need to build pvfs kernel module (pvfs2.ko)
#
# default is true 
#
gNeedBuildPVFS=kBASHReturnSuccess
if [[ ${gKernelMajor} -ge ${gKernelMajorEdge} && ${gKernelMinor} -ge ${gKernelMinorEdge} ]]; then
    #
    # kernel >= 4.6 use modprobe orangefs instead of insert kernel module
    #
    gNeedBuildPVFS=kBASHReturnFailure
fi

#
# Path and filename setup
#
gMyIPAddr=$(ifconfig eth0 |grep 'inet addr' |cut -d: -f2 |awk '{print $1}')
gNodeAliasConfTar="/etc/hosts"
HADOOP_HOME=/opt/`ls /opt |grep -i hadoop`
gHadoopPath="${HADOOP_HOME}"
gHadoopVersion=$(${gHadoopPath}/bin/hadoop version |grep Hadoop |sed 's/Hadoop //')
gOFSPath="/opt/orangefs"
# Target DataNode will enlarge to 1, 2, ...
gDataNodeCount=0
gInetAddr=$(printf ${gMyIPAddr} |cut -d"." -f1-3)
# Head Endpoint for clients
# will be setup later
gDataNodeHeadAdr=""
# All Nodes Alias Settings
gNodeAliasConfSrc="${gREPO}/etc/hosts"
gNodeAliasConfPart="${gNodeAliasConfSrc}_part"
# NameNode & DataNode config generate path
gNameNodeConfSrc="${gREPO}/etc/NameNode"
gDataNodeConfSrc="${gREPO}/etc/DataNode"

#
# Define target website
#
gTargetWeb=https://github.com/syscl/DistributedOS

#
#--------------------------------------------------------------------------------
#

function _PRINT_MSG()
{
    local message=$1

    case "$message" in
      OK*    ) local message=$(echo $message | sed -e 's/.*OK://')
               echo -e "[  ${GREEN}OK${OFF}  ] ${message}."
               ;;

      FAILED*) local message=$(echo $message | sed -e 's/.*://')
               echo -e "[${RED}FAILED${OFF}] ${message}."
               ;;

      ---*   ) local message=$(echo $message | sed -e 's/.*--->://')
               echo -e "[ ${GREEN}--->${OFF} ] ${message}"
               ;;

      NOTE*  ) local message=$(echo $message | sed -e 's/.*NOTE://')
               echo -e "[ ${RED}Note${OFF} ] ${message}."
               ;;
    esac
}

#
#--------------------------------------------------------------------------------
#

function _tidy_exec()
{
    if [ $gDebug -eq 0 ];
      then
        #
        # Using debug mode to output all the details.
        #
        _PRINT_MSG "DEBUG: $2"
        $1
      else
        #
        # Make the output clear.
        #
        $1 >/tmp/report 2>&1 && RETURN_VAL=${kBASHReturnSuccess} || RETURN_VAL=${kBASHReturnFailure}

        if [ "${RETURN_VAL}" == ${kBASHReturnSuccess} ];
          then
            _PRINT_MSG "OK: $2"
          else
            _PRINT_MSG "FAILED: $2"
            cat /tmp/report
        fi

        rm /tmp/report &> /dev/null
    fi
}

#
#--------------------------------------------------------------------------------
#

function _getDataNodeCount()
{
    #
    # min DataNode Count at least 1 
    #
    local gMinDataNodeCount=1
    printf "Enter number of slave(s)"
    read -p ": " gDataNodeCount
    while [[ ${gDataNodeCount} -lt ${gMinDataNodeCount} ]]
    do
        printf "Enter ${RED}valid${OFF} number(>=${gMinDataNodeCount}) of slave(s)"
        read -p ": " gDataNodeCount
    done
    _PRINT_MSG "OK: There are ${gDataNodeCount} slave(s)"
    printf "Enter last ipv4 digit of head slave"
    read -p ": " lipv4 
    gDataNodeHeadAdr=${lipv4}
    _PRINT_MSG "OK: The head DataNode IPv4: ${gInetAddr}.${lipv4}"
    # With above procedures, we can now generate IPv4 for all DataNodes 
}

#
#--------------------------------------------------------------------------------
#

function _detachSlave()
{
    #
    # number of slaves that are on pvfs2 services*
    # 
    # notice: gDataNodeCount = liveDataNodeCount + stopDataNodeCount
    #
    local liveDataNodeCount=$1
    local stopDataNodeCount=$((gDataNodeCount-liveDataNodeCount))

    #
    # notice slaves to detach
    #
    for ((i=0; i<stopDataNodeCount; i++))  
    do
		if [[ "$i" != "2" ]]; then
			ssh ${gInetAddr}.$((gDataNodeHeadAdr+i)) -tt 'sudo pkill -f pvfs2' 2>/dev/null
		fi
    done
}

#
#--------------------------------------------------------------------------------
#

function _attachSlave()
{
    local liveDataNodeCount=$1
    #
    # attach slave to orangefs
    #
    for ((i=liveDataNodeCount-1; i>=0; i--))  
    do
		if [[ "$i" != "2" ]]; then
			ssh ${gInetAddr}.$((gDataNodeHeadAdr+i)) -tt 'sudo /opt/orangefs/sbin/pvfs2-client' 2>/dev/null
		fi
    done
}

#
#--------------------------------------------------------------------------------
#

function _setBufBlckSz()
{
	local liveDataNodeCount=$1
	#
	# get number of size
	#
	local gBlockSize=$2
	local gBufferSize=$3
	gTarCoreSiteXMLPath="${gREPO}/etc/core-site-${gBlockSize}-${gBufferSize}.xml"
	#
	# copy to Jobtracker first
	# 
	cp "${gTarCoreSiteXMLPath}" "${gHadoopPath}/etc/hadoop/core-site.xml"
	for ((i=0; i<liveDataNodeCount; i++))
	do
		scp "${gTarCoreSiteXMLPath}" ${gInetAddr}.$((gDataNodeHeadAdr+i)):${gHadoopPath}/etc/hadoop/core-site.xml
	done
}

#
#--------------------------------------------------------------------------------
#

function _runTask()
{
    local count=$1
    #
	# get number of size
	#
	local gBlockSize=$2
	local gBufferSize=$3
    ${HADOOP_HOME}/bin/hdfs dfs -mkdir /wordcount 2>/dev/null
    ${HADOOP_HOME}/bin/hdfs dfs -put "${gREPO}/wordcount/wikidumps" /wordcount 2>/dev/null
    for ((i=1; i<count; i++))  
    do
        ${HADOOP_HOME}/bin/hdfs dfs -cp /wordcount/wikidumps /wordcount/wiki-${i} 2>/dev/null
		_PRINT_MSG "OK: Put wiki-${i} to DFS"
    done 
    ${HADOOP_HOME}/bin/hadoop jar ${HADOOP_HOME}/share/hadoop/mapreduce/hadoop-mapreduce-examples-${gHadoopVersion}.jar wordcount /wordcount /${count}-out 2>~/${count}-${gBlockSize}-${gBufferSize}-wc.log
    ${HADOOP_HOME}/bin/hdfs dfs -rm -r /*-out 2>/dev/null

    _PRINT_MSG "--->: Test OFS read on ${count} DataNodes..."
    ${HADOOP_HOME}/bin/hadoop jar "${HADOOP_HOME}/share/hadoop/mapreduce/hadoop-mapreduce-client-jobclient-${gHadoopVersion}-tests.jar" TestDFSIO -read -nrFiles ${count} -fileSize 16MB 2>~/${count}-${gBlockSize}-${gBufferSize}-ofs-read.log
    _PRINT_MSG "OK: ${count} DataNodes read $((count*16)) MB"
    #for ((i=1; i<count; i++))  
    #do
    #    ${HADOOP_HOME}/bin/hadoop jar "${HADOOP_HOME}/share/hadoop/mapreduce/hadoop-mapreduce-client-jobclient-${gHadoopVersion}-tests.jar" TestDFSIO -read -nrFiles ${i} -fileSize 16MB 2>~/${count}-ofs-read-${i}.log
    #    _PRINT_MSG "OK: ${count} DataNodes read $((i*16)) MB on ${i} files"
    #done
	${gHadoopPath}/bin/hadoop org.apache.hadoop.fs.TestDFSIO -clean 2>/dev/null

    _PRINT_MSG "--->: Test OFS write on ${count} DataNodes..."
    ${HADOOP_HOME}/bin/hadoop jar "${HADOOP_HOME}/share/hadoop/mapreduce/hadoop-mapreduce-client-jobclient-${gHadoopVersion}-tests.jar" TestDFSIO -write -nrFiles ${count} -fileSize 16MB 2>~/${count}-${gBlockSize}-${gBufferSize}-ofs-write.log
    _PRINT_MSG "OK: ${count} DataNodes write $((count*16)) MB"
    #for ((i=1; i<count; i++))  
    #do
    #    ${HADOOP_HOME}/bin/hadoop jar "${HADOOP_HOME}/share/hadoop/mapreduce/hadoop-mapreduce-client-jobclient-${gHadoopVersion}-tests.jar" TestDFSIO -write -nrFiles ${i} -fileSize 16MB 2>~/${count}-ofs-write-${i}.log
    #    _PRINT_MSG "OK: ${count} DataNodes write $((i*16)) MB on ${i} files"
    #done
	${gHadoopPath}/bin/hadoop org.apache.hadoop.fs.TestDFSIO -clean 2>/dev/null
}

#
#--------------------------------------------------------------------------------
#

function main()
{
    #
    # Get argument.
    #
    gArgv=$(echo "$@" | tr '[:lower:]' '[:upper:]')
    if [[ $# -eq 1 && "$gArgv" == "-D" || "$gArgv" == "-DEBUG" ]];
      then
        #
        # Yes, we do need debug mode.
        #
        _PRINT_MSG "NOTE: Use ${BLUE}DEBUG${OFF} mode"
        gDebug=0
      else
        #
        # No, we need a clean output style.
        #
        gDebug=1
    fi

    _getDataNodeCount
	${gHadoopPath}/bin/hdfs dfs -rm -r /wordcount 2>/dev/null
	${gHadoopPath}/bin/hdfs dfs -mkdir /wordcount 2>/dev/null
    #
    # n - number of live node for testing (from n down to 1)
    #
    for ((n=${gDataNodeCount}; n>0; n--))  
    do
        #
        # detach slaves
        #
        _detachSlave ${n}
        #
        # attach slaves 
        #
        _attachSlave ${n}
        #
        # start testing
        #
		for bufsz in 4 8 16
		do
			for blcksz in 64 128 256
			do
				_setBufBlckSz ${n} ${bufsz} ${blcksz}
				_runTask ${n} ${bufsz} ${blcksz}
			done
		done
    done 
}

#==================================== START =====================================

main "$@"

#================================================================================

exit ${RETURN_VAL}
