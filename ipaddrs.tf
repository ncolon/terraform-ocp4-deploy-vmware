# locals {
#   node_count = "${var.bastion["nodes"] + var.dns["nodes"]}"
#   gateways = ["${compact(list(var.public_gateway, var.private_gateway))}"]
# }


data "template_file" "worker_hostname" {
  count = "${var.worker["count"]}"

  template = "${format("worker%02d", count.index + 1)}"
}

data "template_file" "control_plane_hostname" {
  count = "${var.control_plane["count"]}"

  template = "${format("master%02d", count.index + 1)}"
}
