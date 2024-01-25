module main

import os
import vhetzner
import vserver

fn main() {
	mut base := os.getenv("hetzner_base")
	user := os.getenv("hetzner_user")
	pass := os.getenv("hetzner_pass")

	if base == "" {
		base = "https://robot-ws.your-server.de"
	}

	if user == "" || pass == "" {
		println("Missing API username and password, please set environment:")
		println(" - hetzner_user: api username")
		println(" - hetzner_pass: api password")

		// exit(1)
	}

	if os.args.len < 2 {
		println("Missing target server name")
		exit(1)
	}

	/*
	name := os.args[1]
	println("[+] checking for server $name")

	he := new(user, pass, base)
	srvs := he.servers_list()!

	// println(srvs)
	mut srvid := 0

	for s in srvs {
		if s.server.server_name == name {
			print(s)
			srvid = s.server.server_number
		}
	}

	if srvid == 0 {
		panic("could not find server")
	}
	*/

	/*
	println("[+] request rescue mode")

	resc := he.server_rescue(srvid)!
	println(resc)
	*/

	/*
	println("[+] fetching server information")
	boot := he.server_boot(srvid)!
	println(boot)
	*/

	sm := vserver.new()
	
	// stopping existing raid
	println("[+] stopping raid")
	md := sm.raid_stop()!
	println(md)

	// listing disks
	println("[+] listing disks")
	disks := sm.disks_list()!
	println(disks)

	for disk in disks {
		println("[+] erasing disk: $disk")
		sm.disk_erase(disk)
	}

	main := disks[0]
	println("[+] creating main layout on disk: $main")
	sm.disk_main_layout(main)!
}
