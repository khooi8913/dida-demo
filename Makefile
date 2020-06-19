setup:
	# make sure that we have the latest images
	docker pull khooi8913/debian_networking:sysstat
	docker pull khooi8913/bmv2:sysstat
	docker pull khooi8913/grafana:dida

	# spin up the containers
	docker run -it --privileged -d -t --name host1 -v $(PWD):/root khooi8913/debian_networking:sysstat /bin/bash
	docker run -it --privileged -d -t --name host2 -v $(PWD):/root khooi8913/debian_networking:sysstat /bin/bash
	docker run -it --privileged -d -t --name attacker -v $(PWD):/root khooi8913/debian_networking:sysstat /bin/bash
	docker run -it --privileged -d -t --name internet -v $(PWD):/root khooi8913/debian_networking:sysstat /bin/bash
	docker run -it --privileged -d -t --name access -v $(PWD):/root khooi8913/bmv2:sysstat /bin/bash
	docker run -it --privileged -d -t --name border -v $(PWD):/root khooi8913/bmv2:sysstat /bin/bash
	docker run -it -d -t --name grafana -p 3000:3000 khooi8913/grafana:dida 

	# remove the existing interface
	docker exec host1 ip link delete eth0
	docker exec host2 ip link delete eth0
	docker exec attacker ip link delete eth0
	# docker exec access ip link delete eth0
	# docker exec border ip link delete eth0

	# create new interfaces and connect them
	sudo ./connect_containers_veth.sh access host1 port1 veth0
	sudo ./connect_containers_veth.sh access host2 port2 veth0
	sudo ./connect_containers_veth.sh access border port3 port1
	sudo ./connect_containers_veth.sh border internet port2 internet1
	sudo ./connect_containers_veth.sh internet attacker internet2 veth0

	# host mac addr configuration
	docker exec host1 ip link set veth0 address 00:00:00:00:00:01
	docker exec host2 ip link set veth0 address 00:00:00:00:00:02
	docker exec attacker ip link set veth0 address 00:00:00:00:00:03

	# host ip addr configuration
	docker exec host1 ip addr add 192.168.1.1/24 dev veth0
	docker exec host2 ip addr add 192.168.1.2/24 dev veth0
	docker exec attacker ip addr add 192.168.1.3/24 dev veth0
	
	# host default route configuration
	docker exec host1 ip route add default via 192.168.1.254
	docker exec host2 ip route add default via 192.168.1.254
	docker exec attacker ip route add default via 192.168.1.254

	# setup access router
	docker exec access bash -c "simple_switch -i 1@port1 -i 2@port2 -i 3@port3 access.json &"

	# setup border router
	docker exec border bash -c "simple_switch -i 1@port1 -i 2@port2 border.json &"
	
	# setup internet router
	docker exec internet ip link add name br0 type bridge
	docker exec internet ip link set br0 address 00:00:00:00:00:AA
	docker exec internet ip link set br0 up
	docker exec internet ip link set internet1 master br0
	docker exec internet ip link set internet2 master br0
	docker exec internet ip addr add 192.168.1.254/24 dev br0
	docker exec internet iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

	# static arp entries
	docker exec host1 arp -s 192.168.1.2 00:00:00:00:00:02
	docker exec host1 arp -s 192.168.1.3 00:00:00:00:00:03
	docker exec host1 arp -s 192.168.1.254 00:00:00:00:00:AA
	docker exec host2 arp -s 192.168.1.1 00:00:00:00:00:01
	docker exec host2 arp -s 192.168.1.3 00:00:00:00:00:03
	docker exec host2 arp -s 192.168.1.254 00:00:00:00:00:AA
	docker exec attacker arp -s 192.168.1.1 00:00:00:00:00:01
	docker exec attacker arp -s 192.168.1.2 00:00:00:00:00:02
	docker exec attacker arp -s 192.168.1.254 00:00:00:00:00:AA
	docker exec internet arp -s 192.168.1.1 00:00:00:00:00:01
	docker exec internet arp -s 192.168.1.2 00:00:00:00:00:02
	docker exec internet arp -s 192.168.1.3 00:00:00:00:00:03

	# disable offloading
	docker exec host1 ethtool -K veth0 rx off tx off
	docker exec host2 ethtool -K veth0 rx off tx off
	docker exec attacker ethtool -K veth0 rx off tx off

	# configure access and border
	docker exec access bash -c "simple_switch_CLI < access.config"
	docker exec border bash -c "simple_switch_CLI < border.config"

	# monitor
	docker exec access bash -c "HOSTNAME=access; bash monitor.sh > /tmp/monitor.log &"
	docker exec border bash -c "HOSTNAME=border; bash monitor.sh > /tmp/monitor.log &"
	docker exec internet bash -c "HOSTNAME=internet; bash monitor.sh > /tmp/monitor.log &"

	# test internet connectivity
	docker exec host1 bash -c "ping 1.1.1.1 -c 1"
	docker exec host1 bash -c "ping www.google.com -c 1"
	docker exec host2 bash -c "ping 1.1.1.1 -c 1"
	docker exec host2 bash -c "ping www.google.com -c 1"
	docker exec attacker bash -c "ping 1.1.1.1 -c 1"
	docker exec attacker bash -c "ping www.google.com -c 1"
	
	# # run iperf3
	docker exec attacker bash -c "iperf3 -s &"
	docker exec host1 bash -c "iperf3 -c 192.168.1.3"
	docker exec host2 bash -c "iperf3 -c 192.168.1.3"


teardown:
	docker stop host1 host2 attacker access border internet grafana
	docker rm host1 host2 attacker access border internet grafana
	rm -f host*.log *.out
