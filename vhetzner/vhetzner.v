module vhetzner

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


pub fn (h Hetzner) server_prepare(name string) !bool {
	srvs := h.servers_list()!

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

	println("[+] request rescue mode")
	resc := h.server_rescue(srvid)!
	println(resc)

	println("[+] fetching server information")
	boot := h.server_boot(srvid)!
	println(boot)

	reset := h.server_reset(srvid)!
	println(reset)

	return true
}
