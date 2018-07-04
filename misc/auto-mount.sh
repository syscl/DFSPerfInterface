#!/bin/sh

sudo /opt/orangefs/sbin/pvfs2-client
sudo insmod `find /opt/orangefs -name pvfs2.ko`
gMountCommand=$(cat /etc/pvfs2tab |sed 's/pvfs2.*//g')
sudo mount -t pvfs2 ${gMountCommand}

exit 0