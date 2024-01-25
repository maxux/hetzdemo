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

	println("[+] request rescue mode")

	resc := he.server_rescue(srvid)!
	println(resc)
}
