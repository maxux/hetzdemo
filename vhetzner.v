module main

import os
import json
import net.http
import encoding.base64
// import maxux.vssh

struct Hetzner {
	user string
	pass string
	base string
	auth string
}

struct Subnet {
	ip string
	mask string
}

struct Server {
	server_ip string
	server_ipv6_net string
	server_number int
	server_name string
	product string
	dc string
	traffic string
	status string
	cancelled bool
	paid_until string
	ip []string
	subnet []Subnet
}

struct ServerRoot {
	server Server
}

struct Rescue {
    server_ip string
    server_ipv6_net string
    server_number int
    os string
    arch int
    active bool
    password string
    authorized_key []string
    host_key []string
}

struct RescueRoot {
	rescue Rescue
}

struct Reset {
	server_ip string
    server_ipv6_net string
    server_number int
    // type string // FIXME
    operating_status string
}

struct ResetRoot {
	reset Reset
}

struct Boot {
	rescue Rescue
}

struct BootRoot {
	boot Boot
}

pub fn new(user string, pass string, base string) Hetzner {
	challenge := user + ":" + pass
	auth := base64.encode(challenge.bytes())

	h := Hetzner{
		user: user,
		pass: pass,
		base: base
		auth: auth
	}

	return h
}

fn (h Hetzner) request_get(endpoint string) !http.Response {
	mut r := http.Request{
		url: h.base + endpoint
	}

	r.add_header(http.CommonHeader.authorization, "Basic " + h.auth)
	response := r.do()!

	return response
}

fn (h Hetzner) request_post(endpoint string, data string) !http.Response {
	mut r := http.Request{
		method: .post,
		data: data,
		url: h.base + endpoint
	}

	r.add_header(http.CommonHeader.authorization, "Basic " + h.auth)
	r.add_header(http.CommonHeader.content_type, "application/x-www-form-urlencoded")
	response := r.do()!

	return response
}

pub fn (h Hetzner) servers_list() ![]ServerRoot {
	response := h.request_get("/server")!

	if response.status_code != 200 {
		return error("could not process request: error $response.status_code $response.body")
	}

	srvs := json.decode([]ServerRoot, response.body) or {
		return error("could not process request")
	}

	return srvs
}

pub fn (h Hetzner) server_rescue(id int) !RescueRoot {
	response := h.request_post("/boot/$id/rescue", "os=linux")!

	if response.status_code != 200 {
		return error("could not process request: error $response.status_code $response.body")
	}

	rescue := json.decode(RescueRoot, response.body) or {
		return error("could not process request")
	}

	return rescue
}

pub fn (h Hetzner) server_reset(id int) !ResetRoot {
	response := h.request_post("/reset/$id", "type=hw")!

	if response.status_code != 200 {
		return error("could not process request: error $response.status_code $response.body")
	}

	rescue := json.decode(ResetRoot, response.body) or {
		return error("could not process request")
	}

	return rescue
}

pub fn (h Hetzner) server_boot(id int) !BootRoot {
	response := h.request_get("/boot/$id")!

	if response.status_code != 200 {
		return error("could not process request: error $response.status_code $response.body")
	}

	boot := json.decode(BootRoot, response.body) or {
		return error("could not process request: $err")
	}

	return boot
}


struct ServerManager {
	root string
}

pub fn newsm() ServerManager {
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

		exit(1)
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

	sm := newsm()
	
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
