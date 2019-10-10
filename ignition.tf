resource "null_resource" "dependency" {
  triggers = {
    all_dependencies = "${join(",", var.dependson)}"
  }
}

locals {
  mask         = "${var.private_netmask}"
  gw           = "${var.private_gateway}"
  ignition_url = "${var.ignition_url != "" ? "${var.ignition_url}" : "http://${element(var.bastion_private_ip, 0)}"}"
}

data "ignition_file" "bootstrap_hostname" {
  filesystem = "root"
  path       = "/etc/hostname"
  mode       = "420"

  content {
    content = "bootstrap.${var.cluster_name}.${lower(var.private_domain)}"
  }
}

data "ignition_file" "bootstrap_static_ip" {
  filesystem = "root"
  path       = "/etc/sysconfig/network-scripts/ifcfg-ens192"
  mode       = "420"

  content {
    content = <<EOF
TYPE=Ethernet
BOOTPROTO=none
NAME=ens192
DEVICE=ens192
ONBOOT=yes
IPADDR=${element(var.bootstrap_ip_address, 0)}
PREFIX=${local.mask}
GATEWAY=${local.gw}
DOMAIN=${lower(var.cluster_name)}.${var.private_domain}
DNS1=${element(var.dns_private_ip, 0)}
SEARCH="${lower(var.cluster_name)}.${lower(var.private_domain)} ${lower(var.private_domain)}"
EOF
  }
}

data "ignition_file" "control_plane_hostname" {
  count = "${var.control_plane["count"]}"

  filesystem = "root"
  path       = "/etc/hostname"
  mode       = "420"

  content {
    content = "${element(data.template_file.control_plane_hostname.*.rendered, count.index)}.${lower(var.cluster_name)}.${lower(var.private_domain)}"
  }
}

data "ignition_file" "control_plane_static_ip" {
  count = "${var.control_plane["count"]}"

  filesystem = "root"
  path       = "/etc/sysconfig/network-scripts/ifcfg-ens192"
  mode       = "420"

  content {
    content = <<EOF
TYPE=Ethernet
BOOTPROTO=none
NAME=ens192
DEVICE=ens192
ONBOOT=yes
IPADDR=${element(var.control_plane_private_ip, count.index)}
PREFIX=${local.mask}
GATEWAY=${local.gw}
DOMAIN=${lower(var.cluster_name)}.${var.private_domain}
DNS1=${element(var.dns_private_ip, 0)}
SEARCH="${lower(var.cluster_name)}.${lower(var.private_domain)} ${lower(var.private_domain)}"
EOF
  }
}

data "ignition_file" "resolv_conf" {
  filesystem = "root"
  path       = "/etc/resolv.conf"
  mode       = "644"

  content {
    content = <<EOF
nameserver ${element(var.dns_private_ip, 0)}
search ${var.cluster_name}.${var.private_domain}
EOF
  }
}


data "ignition_file" "worker_hostname" {
  count = "${var.worker["count"]}"

  filesystem = "root"
  path       = "/etc/hostname"
  mode       = "420"

  content {
    content = "${element(data.template_file.worker_hostname.*.rendered, count.index)}.${lower(var.cluster_name)}.${lower(var.private_domain)}"
  }
}

data "ignition_file" "worker_static_ip" {
  count = "${var.worker["count"]}"

  filesystem = "root"
  path       = "/etc/sysconfig/network-scripts/ifcfg-ens192"
  mode       = "420"

  content {
    content = <<EOF
TYPE=Ethernet
BOOTPROTO=none
NAME=ens192
DEVICE=ens192
ONBOOT=yes
IPADDR=${element(var.worker_ip_address, count.index)}
PREFIX=${local.mask}
GATEWAY=${local.gw}
DOMAIN=${lower(var.cluster_name)}.${var.private_domain}
DNS1=${element(var.dns_private_ip, 0)}
SEARCH="${lower(var.cluster_name)}.${lower(var.private_domain)} ${lower(var.private_domain)}"
EOF
  }
}

data "ignition_systemd_unit" "restart" {
  name = "restart.service"

  content = <<EOF
[Unit]
ConditionFirstBoot=yes
[Service]
Type=idle
ExecStart=/sbin/reboot
[Install]
WantedBy=multi-user.target
EOF
}

data "ignition_config" "bootstrap_ign" {
  append {
    source = "${local.ignition_url}/bootstrap.ign"
  }

  systemd = [
    "${data.ignition_systemd_unit.restart.id}",
  ]

  files = [
    "${data.ignition_file.bootstrap_hostname.id}",
    "${data.ignition_file.bootstrap_static_ip.id}",
    "${data.ignition_file.resolv_conf.id}"
  ]
}

data "ignition_config" "control_plane_ign" {
  count = "${var.control_plane["count"]}"

  append {
    source = "${local.ignition_url}/master.ign"
  }

  systemd = [
    "${data.ignition_systemd_unit.restart.id}",
  ]

  files = [
    "${data.ignition_file.control_plane_hostname.*.id[count.index]}",
    "${data.ignition_file.control_plane_static_ip.*.id[count.index]}",
    "${data.ignition_file.resolv_conf.id}"
  ]
}

data "ignition_config" "worker_ign" {
  count = "${var.worker["count"]}"

  append {
    source = "${local.ignition_url}/worker.ign"
  }

  systemd = [
    "${data.ignition_systemd_unit.restart.id}",
  ]

  files = [
    "${data.ignition_file.worker_hostname.*.id[count.index]}",
    "${data.ignition_file.worker_static_ip.*.id[count.index]}",
    "${data.ignition_file.resolv_conf.id}"
  ]
}

resource "null_resource" "openshift_installer" {
  depends_on = [
    "null_resource.dependency",
  ]

  connection {
    type        = "ssh"
    host        = "${element(var.bastion_public_ip, 0)}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${var.ssh_private_key}"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "wget -r -l1 -np -nd https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ -P /tmp -A 'openshift-install-linux-4*.tar.gz'",
      "tar zxvf /tmp/openshift-install-linux-4*.tar.gz -C /tmp",
    ]
  }
}

resource "null_resource" "openshift_client" {
  depends_on = [
    "null_resource.dependency"
  ]

  connection {
    type        = "ssh"
    host        = "${element(var.bastion_public_ip, 0)}"
    user        = "${var.ssh_user}"
    password    = "${var.ssh_password}"
    private_key = "${var.ssh_private_key}"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "wget -r -l1 -np -nd https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ -P /tmp -A 'openshift-client-linux-4*.tar.gz'",
      "sudo tar zxvf /tmp/openshift-client-linux-4*.tar.gz -C /usr/local/bin",
    ]
  }
}

module "createignition" {
  source = "github.com/ibm-cloud-architecture/terraform-ansible-runplaybooks.git"

  ansible_playbook_dir = "${path.module}/playbooks"
  ansible_playbooks = [
    "playbooks/ignition.yaml"
  ]

  dependson = [
    "null_resource.dependency.id",
    "${null_resource.openshift_client.id}",
    "${null_resource.openshift_installer.id}",
  ]

  ssh_user        = "${var.ssh_user}"
  ssh_password    = "${var.ssh_password}"
  ssh_private_key = "${var.ssh_private_key}"

  bastion_ip_address      = "${element(var.bastion_public_ip, 0)}"
  bastion_ssh_user        = "${var.ssh_user}"
  bastion_ssh_password    = "${var.ssh_password}"
  bastion_ssh_private_key = "${var.ssh_private_key}"

  node_ips       = "${var.bastion_private_ip}"
  node_hostnames = "${var.bastion_private_ip}"

  triggerson = {
    node_ips = "${join(",", var.bastion_private_ip)}"
  }

  ansible_vars = {
    "private_domain"        = "${var.private_domain}"
    "control_plane_count"   = "${var.control_plane_count}"
    "cluster_name"          = "${var.cluster_name}"
    "cluster_network_cidr"  = "${var.cluster_network_cidr}"
    "host_prefix"           = "${var.host_prefix}"
    "service_network_cidr"  = "${var.service_network_cidr}"
    "openshift_pull_secret" = "${chomp(file(var.openshift_pull_secret))}"
    "ssh_public_key"        = "${chomp(var.ssh_public_key)}"
    "dns_private_ip"        = "${element(var.dns_private_ip, 0)}"
    "bootstrap_url"         = "http://${element(var.bootstrap_ip_address, 0)}:22624"
    "replaced_url"          = "https://api-int.${var.cluster_name}.${var.private_domain}:22623"
    "public_dns_servers"    = "${join(",", var.public_dns_servers)}"
  }
  # ansible_verbosity = "-vvv"
}

module "deploy" {
  source = "github.com/ibm-cloud-architecture/terraform-ansible-runplaybooks.git"

  ansible_playbook_dir = "${path.module}/playbooks"
  ansible_playbooks = [
    "playbooks/deploy.yaml"
  ]

  dependson = [
    "null_resource.dependency.id",
    "${null_resource.openshift_client.id}",
    "${null_resource.openshift_installer.id}",
    "${join(",", concat(
        vsphere_virtual_machine.bootstrap_ds_cluster.*.id,
        vsphere_virtual_machine.bootstrap.*.id,
        vsphere_virtual_machine.control_plane.*.id,
        vsphere_virtual_machine.control_plane_ds_cluster.*.id,
        vsphere_virtual_machine.worker.*.id,
        vsphere_virtual_machine.worker_ds_cluster.*.id,
      ))}"
  ]

  ssh_user        = "${var.ssh_user}"
  ssh_password    = "${var.ssh_password}"
  ssh_private_key = "${var.ssh_private_key}"

  bastion_ip_address      = "${element(var.bastion_public_ip, 0)}"
  bastion_ssh_user        = "${var.ssh_user}"
  bastion_ssh_password    = "${var.ssh_password}"
  bastion_ssh_private_key = "${var.ssh_private_key}"

  node_ips       = "${var.bastion_private_ip}"
  node_hostnames = "${var.bastion_private_ip}"

  triggerson = {
    node_ips = "${join(",", var.bastion_private_ip)}"
  }

  ansible_vars = {
    "private_domain"        = "${var.private_domain}"
    "control_plane_count"   = "${var.control_plane_count}"
    "cluster_name"          = "${var.cluster_name}"
    "cluster_network_cidr"  = "${var.cluster_network_cidr}"
    "host_prefix"           = "${var.host_prefix}"
    "service_network_cidr"  = "${var.service_network_cidr}"
    "openshift_pull_secret" = "${chomp(file(var.openshift_pull_secret))}"
    "ssh_public_key"        = "${chomp(var.ssh_public_key)}"
    "dns_private_ip"        = "${element(var.dns_private_ip, 0)}"
    "bootstrap_url"         = "http://${element(var.bootstrap_ip_address, 0)}:22624"
    "replaced_url"          = "https://api-int.${var.cluster_name}.${var.private_domain}:22623"
  }
  cleanup = false
  # ansible_verbosity = "-vvv"
}

