#! /bin/bash
for i in $(head -n 1000 top-1m.csv); 
do
	wget --timeout 5 --tries 1 -r https://`echo $i | cut -d ',' -f 2` -P $HOSTNAME;
    sleep 5
done