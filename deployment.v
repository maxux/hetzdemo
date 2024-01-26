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

	//
	// prepare mode
	//
	if os.args.len > 1 && os.args[1] == "prepare" {
		if user == "" || pass == "" {
			println("Missing API username and password, please set environment:")
			println(" - hetzner_user: api username")
			println(" - hetzner_pass: api password")

			exit(1)
		}

		if os.args.len < 3 {
			println("Missing target server name")
			exit(1)
		}

		name := os.args[2]
		println("[+] preparing server: $name")

		he := vhetzner.new(user, pass, base)
		he.server_prepare(name)!

		exit(0)
	}

	//
	// deployment mode
	//

	sm := vserver.new()
	
	// stopping existing raid
	println("[+] stopping raid")
	md := sm.raid_stop()!
	// println(md)

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
	diskmap := sm.disk_main_layout(main)!

	println("[+] creating extra btrfs storage")
	for disk in disks {
		if disk == main {
			// skip main disk
			continue
		}

		sm.disk_create_btrfs(disk)!
	}

	println("[+] preparing machine for nixos installation")
	sm.nixos_prepare(diskmap)!

	sshkey := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG7QGDSTCf+VgBLNVsdFMLYD7siK4McKy7fPkMqVZihx maxux@workx0"
	sm.nixos_install("/dev/$main", sshkey)!

	sm.nixos_finish()!
}
