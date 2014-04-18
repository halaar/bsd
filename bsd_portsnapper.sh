#!/bin/sh

LOG_FILE="/var/log/00update.log"

echo "Starting updates: `date`" | tee ${LOG_FILE}
echo "***"
echo "*** Checking for patches..."
echo "***"
/usr/sbin/freebsd-update fetch | tee ${LOG_FILE}
/usr/sbin/freebsd-update install | tee ${LOG_FILE}

echo "***"
echo "*** Updating ports tree..."
echo "***"
/usr/sbin/portsnap fetch update | tee ${LOG_FILE}

echo "***"
echo "*** Checking pkgdb..."
echo "***"
/usr/local/sbin/pkgdb -aFv | tee ${LOG_FILE}

#echo "***"
#echo "*** Looking for ports to update..."
#echo "***"
#/usr/local/sbin/portversion -v -l '<' | tee ${LOG_FILE}
#/usr/local/sbin/portupgrade -aRrbv --batch | tee ${LOG_FILE}
#/usr/local/sbin/portversion -v | tee ${LOG_FILE}

echo "***"
echo "*** Checking installed ports for known security problems..."
echo "***"
/usr/local/sbin/portaudit -Fva | tee ${LOG_FILE}
echo "Finished updates: `date`" | tee ${LOG_FILE}