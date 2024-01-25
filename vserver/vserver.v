module vserver

import os
// import json
// import maxux.vssh

struct ServerManager {
	root string
}

pub fn new() ServerManager {
	sm := ServerManager{}
	return sm
}

pub fn (s ServerManager) raid_stop() !bool {
	if !os.exists("/proc/mdstat") {
		return false
	}

	md := os.read_file("/proc/mdstat")!
	lines := md.split_into_lines()

	for line in lines {
		if line.contains("active") {
			dev := line.split(" ")[0]
			println("[+] stopping raid device: $dev")

			r := os.execute("mdadm --stop /dev/$dev")
			if r.exit_code != 0 {
				println(r.output)
			}
		}
	}

	return true
}

pub fn (s ServerManager) disks_list() ![]string {
	blocks := os.ls("/sys/class/block")!
	mut disks := []string{}

	for block in blocks {
		if os.is_link("/sys/class/block/$block/device") {
			// discard cdrom
			events := os.read_file("/sys/class/block/$block/events")!
			if events.contains("eject") {
				continue
			}

			// that should be good
			disks << block
		}
	}

	return disks
}

pub fn (s ServerManager) disk_erase(disk string) bool {
	// make it safe via wipefs
	r := os.execute("wipefs -a /dev/$disk")
	if r.exit_code != 0 {
		println(r.output)
		return false
	}

	return true
}

pub fn (s ServerManager) disk_partitions(disk string) ![]string {
	mut files := os.ls("/sys/class/block/$disk")!
	mut parts := []string{}

	files.sort()
	for file in files {
		if file.starts_with(disk) {
			parts << file
		}
	}

	return parts
}

pub fn (s ServerManager) disk_main_layout(disk string) !bool {
	os.execute("parted /dev/$disk mklabel msdos")
	os.execute("parted -a optimal /dev/$disk mkpart primary 0% 768MB")
	os.execute("parted -a optimal /dev/$disk mkpart primary 768MB 100GB")
	os.execute("parted -a optimal /dev/$disk mkpart primary linux-swap 100GB 104GB")
	os.execute("parted -a optimal /dev/$disk mkpart primary 104GB 100%")

	os.execute("partprobe")

	parts := s.disk_partitions(disk)!
	if parts.len < 4 {
		return error("partitions found doesn't match expected map")
	}

	boot := "/dev/" + parts[0]
	root := "/dev/" + parts[1]
	swap := "/dev/" + parts[2]
	more := "/dev/" + parts[3]

	println("[+] partition map:")
	println("[+]   /       -> $root  [ext2]")
	println("[+]   /boot   -> $boot  [ext4]")
	println("[+]   [swap]  -> $swap  [swap]")
	println("[+]   [extra] -> $more  [btrfs]")

	println("[+] creating boot partition")
	os.execute("mkfs.ext2 $boot")

	println("[+] creating root partition")
	os.execute("mkfs.ext4 $root")

	println("[+] creating swap partition")
	os.execute("mkswap $swap")

	println("[+] creating storage partition")
	os.execute("mkfs.btrfs -f $more")

	return true
}

