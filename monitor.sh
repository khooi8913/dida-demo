device=$HOSTNAME
sar_out="/tmp/${device}.out"

echo "Start SAR in background mode"
sar -n DEV 1 10000 > $sar_out &

# create database
curl -XPOST 'http://localhost:8086/query' --data-urlencode "q=CREATE DATABASE "${device}""

ifaces=( $(ip addr list | awk -F': ' '/^[0-9]/ && $2 != "lo" && $2 != "eth0" {print $2}'))

# usage: extract INTF
function monitor_net(){
    intf=`echo $1 | cut -d '@' -f 1`
    while true
    do
        output=$(cat $sar_out | grep -i $intf)
        retval=$(echo $?)

        if [ $retval -ne 0 ]
        then
            echo "An error occurred"
            rx=0
            tx=0
        else
            rx=$(tail $sar_out | grep $intf | tail -n1 | awk '{print $5}')
            rx=`echo "$rx*8" | bc`
            tx=$(tail $sar_out | grep $intf | tail -n1 | awk '{print $6}')
            tx=`echo "$tx*8" | bc`
        fi

        echo $device $intf "transmitted" $tx "received" $rx
        curl -i -XPOST "http://172.17.0.1:8086/write?db=${device}" --data-binary "${intf}_rx,received=kbps value=${rx}" 
        curl -i -XPOST "http://172.17.0.1:8086/write?db=${device}" --data-binary "${intf}_tx,sent=kbps value=${tx}"
        sleep 1s
    done
}

for iface in ${ifaces[@]}
do
    monitor_net $iface &
done
wait