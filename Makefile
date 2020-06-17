setup:
	# spin up the containers
	docker run -it --privileged -d -t --name host1 -v $(PWD):/root khooi8913/debian_networking:latest /bin/bash
	docker run -it --privileged -d -t --name host2 -v $(PWD):/root khooi8913/debian_networking:latest /bin/bash
	docker run -it --privileged -d -t --name attacker -v $(PWD):/root khooi8913/debian_networking:latest /bin/bash
	docker run -it --privileged -d -t --name access -v $(PWD):/root khooi8913/bmv2:latest /bin/bash
	docker run -it --privileged -d -t --name border -v $(PWD):/root khooi8913/bmv2:latest /bin/bash

	# remove the existing interface
	docker exec host1 ip link delete eth0
	docker exec host2 ip link delete eth0
	docker exec attacker ip link delete eth0
	docker exec access ip link delete eth0
	docker exec border ip link delete eth0

	# create new interfaces and connect them
	sudo ./connect_containers_veth.sh access host1 port1 veth0
	sudo ./connect_containers_veth.sh access host2 port2 veth0
	sudo ./connect_containers_veth.sh access border port3 port2

	# ip addr configuration
	docker exec host1 ip addr add 192.168.1.1/24 dev veth0
	docker exec host2 ip addr add 192.168.1.2/24 dev veth0

	# setup access router
	docker exec access simple_switch -i 1@port1 -i 2@port2 docker.json &

	# disable offloading
	docker exec host1 ethtool -K veth0 rx off tx off
	docker exec host2 ethtool -K veth0 rx off tx off

	# run iperf3
	docker exec host1 bash -c "iperf3 -s > host1.log &" &
	docker exec host2 bash -c "iperf3 -c 192.168.1.1 -t 10000 -i 0.1 > host2.log &" &
	

teardown:
	docker stop host1 host2 attacker access border
	docker rm host1 host2 attacker access border
	rm -f host*.log
