# docker-swarm-kernel-fix
This is a quick and dirty fix for the Docker Swarm issue that we had in 2022, passed a certain Linux kernel version.

During the repairing of some of the well known and regular CSCS backend storage crashes, last Monday, we discovered that the MIP worker nodes which had to be rebooted can't connect to the consul (exareme-keystore) on the master node anymore, resulting in a MIP federation to stay in a "crashed" status.

Long story short, starting from Linux 5.4.0-105, the Docker Swarm networks stopped working properly.
Actually, from within the Docker Swarm overlay network (from within a container), we can do *ICMP* queries to other nodes, but the other types of connections (at least *TCP*) don't work anymore.
So far, none of our investigations to find the real cause was successful, and as usual, as we don't have time to find out what's going on, we decided to do a quick and very dirty fix, by "locking" the kernel version to the last working one, **5.4.0-104**.

This is only required for the Docker Swarm nodes, which are the **master** and the **worker** ones.

This repository contains some useful scripts to check and "fix" the issue.

First of all, when the services are running, at least on the master, the *mip* script can give us some useful informations about the Docker Swarm services IP addresses.
On the **master** node, the following command will give us details, like the *exareme-keystore* service's IP address:

```
mip --verbose-level 4 status
```

Let's say that this IP is 10.20.30.40.

Now, from a worker node (with a **running** *exareme* container), we can run the following command (which is in this repository) to check the connection:

```
./docker_swarm_comm_check.sh 10.20.30.40:8500
```

If the result is not "ok", it should be "FAIL!". This means that the kernel is not anymore compatible with the Docker Swarm networking.
Then, we have to fix the kernel with the following command, as well from within this repository:

```
sudo ./kernel_version_fix.sh
```

This will install the latest compatible kernel packages, and also uninstall the other ones, that we (supposedly) don't want anymore. Also, it will mark the working kernel packages for **hold**.
At last, if we're currently running on an incompatible kernel version, the script will find the Grub menu tag to mark the **5.4.0-104** kernel to be the next to be booted.
Then, we have to reboot.
When the machine is back online, it should run the **5.4.0-104** kernel version. We can check it with "uname -r".
We can also run the fixing script once again, to finish the job (like removing the kernel we were previously running on):

```
sudo ./kernel_version_fix.sh
```

When everything is fine, the last line of the output should be "System OK".

Then, we can check the connection again:

```
./docker_swarm_comm_check.sh 10.20.30.40:8500
```

This time, the output should be "ok".

This fix is temporary, and hopefully, or Docker Swarm will be fixed in a future version, or we will have finished our current journey to a working Kubernetes based MIP federation.
