#!/bin/bash

#
# (c) 2017-2018 syscl
# Auto deploy enviroment on Hadoop v2.x with OrangeFS 2.x and HDFS
#
# Project: Performance tunning for OrangeFS on Hadoop (Advance Operating Systems)
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
#           kBASHReturnFailure - hide details
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

function _prepare()
{
    _tidy_exec "sudo add-apt-repository -y ppa:webupd8team/java" "Add Oracle JDK 8 installation source"
    _tidy_exec "sudo apt-get update" "Updating software list..." 
    # mute the confirmation with argument -y
    _tidy_exec "sudo apt install -y automake build-essential bison flex libattr1 libattr1-dev oracle-java8-installer linux-headers-$(uname -r)" "Install tool chain for orangeFS"
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
    printf "Enter number of DataNode(s)"
    read -p ": " gDataNodeCount
    while [[ ${gDataNodeCount} -lt ${gMinDataNodeCount} ]]
    do
        printf "Enter ${RED}valid${OFF} number(>=${gMinDataNodeCount}) of DataNode(s)"
        read -p ": " gDataNodeCount
    done
    _PRINT_MSG "OK: There are ${gDataNodeCount} DataNode(s)"
    printf "Enter last ipv4 digit of head DataNode"
    read -p ": " lipv4 
    gDataNodeHeadAdr=${lipv4}
    _PRINT_MSG "OK: The head DataNode IPv4: ${gInetAddr}.${lipv4}"
    # With above procedures, we can now generate IPv4 for all DataNodes 
}

#
#--------------------------------------------------------------------------------
#

function _phdfs_site()
{
	local dataNodeCount=$1
	#
	# default is kBASHReturnFailure - DataNode
	#
	local isNameNode=$2
	echo '<?xml version="1.0" encoding="UTF-8"?>'
	echo '<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>'
	echo 
	echo '<configuration>'
	echo '<property>'
	echo ' <name>dfs.replication</name>'
	echo " <value>${dataNodeCount}</value>"
	echo '</property>'
	echo '<property>' 
	if [[ ${isNameNode} == ${kBASHReturnSuccess} ]]; then
		# generate NameNode config
		echo ' <name>dfs.namenode.name.dir</name>' 
		echo ' <value>file:/usr/local/hadoop_tmp/hdfs/namenode</value>'
	else 
		echo ' <name>dfs.datanode.data.dir</name>' 
		echo ' <value>file:/usr/local/hadoop_tmp/hdfs/datanode</value>' 
	fi
	echo '</property>' 
	echo '</configuration>'
}

#
#--------------------------------------------------------------------------------
#

function _genAndSetConf()
{
    local dataNodeCount=$1
	local replica=${dataNodeCount}
    #
    # generate slaves and masters list for Hadoop
    #
    echo master > ${gNameNodeConfSrc}/masters
    rm ${gNameNodeConfSrc}/slaves 2>/dev/null
    until [  ${dataNodeCount} -le 0 ]; do
        echo "slave${dataNodeCount}" >> ${gNameNodeConfSrc}/slaves
        let dataNodeCount-=1
    done

    rm ${gDataNodeConfSrc}/* 2>/dev/null
	#
	# gen hdfs-site.xml
	#
    cp ${gNameNodeConfSrc}/* ${gDataNodeConfSrc}
	_phdfs_site ${replica} ${kBASHReturnSuccess} > ${gNameNodeConfSrc}/hdfs-site.xml
	_phdfs_site ${replica} ${kBASHReturnFailure} > ${gDataNodeConfSrc}/hdfs-site.xml

	#
	# set config on nodes
	#
	cp ${gNameNodeConfSrc}/* ${HADOOP_HOME}/etc/hadoop
	for ((n=0; n<${replica}; n++))  
    do  
		scp etc/DataNode/*  "${gInetAddr}.$((gDataNodeHeadAdr+n)):${HADOOP_HOME}/etc/hadoop" 2>&1>/dev/null
    done
}

#
#--------------------------------------------------------------------------------
#

function _setAliasOnHost()
{
    #
    # Generate host alias
    # 
    local dataNodeCount=$1
    if [ ! -f ${gNodeAliasConfTar}.bak ]; then
        sudo cp ${gNodeAliasConfTar} ${gNodeAliasConfTar}.bak
    fi
    echo "${gMyIPAddr}  master" > ${gNodeAliasConfPart} 
    for ((n=0; n<${dataNodeCount}; n++))  
    do  
        echo "${gInetAddr}.$((gDataNodeHeadAdr+n))  slave$((n+1))" >> ${gNodeAliasConfPart}
    done
	cat ${gNodeAliasConfTar}.bak ${gNodeAliasConfPart} > /tmp/hosts 
	sudo cp /tmp/hosts /etc/hosts 
}

#
#--------------------------------------------------------------------------------
#

function _setAliasOnSlave()
{
    #
    # push the executable programs to slaves for setting up the node alias on slaves 
    #
    local dataNodeCount=$1
    for ((n=0; n<${dataNodeCount}; n++))  
    do
        #
        # notice ssh did not support redirect operation
        #
		ssh ${gInetAddr}.$((gDataNodeHeadAdr+n)) -t 'sudo cp /etc/hosts.bak /etc/hosts' 2>/dev/null
		cat ${gNodeAliasConfPart} |xargs -I {} ssh ${gInetAddr}.$((gDataNodeHeadAdr+n)) -t 'sudo sed -i "\$a {}" /etc/hosts' 2>/dev/null
    done
}

#
#--------------------------------------------------------------------------------
#

function _formatNameNode()
{
    local gNameNodeDir=$(cat "${HADOOP_HOME}/etc/hadoop/hdfs-site.xml"|grep -i file|grep -v datanode|grep '<value>.*</value>'|sed 's/.*<value>file://g'|sed 's/<\/value>.*//')
    sudo rm -rf "${gNameNodeDir}"
    sudo mkdir -p "${gNameNodeDir}"
    sudo chown ${USER}:hadoop -R "${gNameNodeDir}"
    _tidy_exec "${gHadoopPath}/bin/hdfs namenode -format" "Format NameNode"
}

#
#--------------------------------------------------------------------------------
#

function _cleanDataNode()
{
    local dataNodeCount=$1
    #
    # now execute code remotely
    #
    for ((n=0; n<${dataNodeCount}; n++))  
    do 
		ssh ${gInetAddr}.$((gDataNodeHeadAdr+n)) -t 'sudo rm -rf /usr/local/hadoop_tmp/hdfs/datanode' 2>/dev/null
		_PRINT_MSG "OK: Clean up DataNode@${gInetAddr}.$((gDataNodeHeadAdr+n))" 
    done 
}

#
#--------------------------------------------------------------------------------
#

function _runTask()
{
    local count=$1
    ${HADOOP_HOME}/bin/hdfs dfs -mkdir /wordcount 2>/dev/null
    ${HADOOP_HOME}/bin/hdfs dfs -put "${gREPO}/wordcount/wikidumps" /wordcount
    for ((i=1; i<count; i++))  
    do
        ${HADOOP_HOME}/bin/hdfs dfs -cp /wordcount/wikidumps /wordcount/wiki-${i} 2>/dev/null
		_PRINT_MSG "OK: Put wiki-${i} to DFS"
    done 
    ${HADOOP_HOME}/bin/hadoop jar ${HADOOP_HOME}/share/hadoop/mapreduce/hadoop-mapreduce-examples-${gHadoopVersion}.jar wordcount /wordcount /${count}-out 2>~/${count}-dn-wc.log
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
    #
    # n - number of node for testing (from n down to 1)
    #
    for ((n=${gDataNodeCount}; n>0; n--))  
    do
        #
        # Notify all Nodes to stop first
        #
        _tidy_exec "${HADOOP_HOME}/sbin/stop-all.sh" "Stop all Hadoop services on all nodes"  
        #
        # generate config for nodes
        #
        _genAndSetConf ${n}
		#
        # set Alias name on NameNode
        #
        _setAliasOnHost ${n}
        #
        # push remote executable code for DataNode
        #
        _setAliasOnSlave ${n}
        #
        # format NameNode for same Evaluation
        # 
        _formatNameNode
        #
        # clean DataNode for a new ID to avoid errors 
        #
        _cleanDataNode ${n}
        #
        # Now let's get started
        #
        _tidy_exec "${HADOOP_HOME}/sbin/start-dfs.sh" "Start dfs"
        _tidy_exec "${HADOOP_HOME}/sbin/start-yarn.sh" "Start yarn"
        #
        # start testing
        #
        _runTask ${n}
    done 
}

#==================================== START =====================================

main "$@"

#================================================================================

exit ${RETURN_VAL}
