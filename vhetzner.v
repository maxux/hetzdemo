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

pub fn (h Hetzner) servers_list() ![]ServerRoot {
	mut r := http.Request{
		url: h.base + "/server"
	}

	r.add_header(http.CommonHeader.authorization, "Basic " + h.auth)
	response := r.do()!

	if response.status_code != 200 {
		return error("could not process request: error $response.status_code")
	}

	srvs := json.decode([]ServerRoot, response.body) or {
		eprintln("Failed to decode json, error: ${err}")
		return error("could not process request")
	}

	return srvs
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

	println("Initializing")

	he := new(user, pass, base)
	s := he.servers_list()!
	println(s)

}
