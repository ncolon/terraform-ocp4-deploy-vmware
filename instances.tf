#################################
# Configure the VMware vSphere Provider
##################################
provider "vsphere" {
  version        = "~> 1.1"
  vsphere_server = "${var.vsphere_server}"

  # if you have a self-signed cert
  allow_unverified_ssl = "${var.allow_unverified_ssl}"
}

data "vsphere_virtual_machine" "rhel_template" {
  name          = "${var.rhel_template}"
  datacenter_id = "${var.vsphere_datacenter_id}"
}

data "vsphere_virtual_machine" "rhcos_template" {
  name          = "${var.rhcos_template}"
  datacenter_id = "${var.vsphere_datacenter_id}"
}


##################################
#### Create the Bootsrtap VM
##################################
resource "vsphere_virtual_machine" "bootstrap" {
  count = "${var.datastore_id != "" ? (var.bootstrap_complete ? 0 : 1) : 0}"

  depends_on = [
    "module.createignition.module_completed"
  ]

  folder = "${var.folder_path}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${var.vsphere_resource_pool_id}"

  name     = "${lower(var.cluster_name)}-bootstrap"
  num_cpus = "${var.bootstrap["vcpu"]}"
  memory   = "${var.bootstrap["memory"]}"

  #scsi_controller_count = 1
  #scsi_type = "lsilogic-sas"

  ####
  # Disk specifications
  ####
  datastore_id = "${var.datastore_id}"
  guest_id     = "${data.vsphere_virtual_machine.rhcos_template.guest_id}"
  scsi_type    = "${data.vsphere_virtual_machine.rhcos_template.scsi_type}"

  disk {
    label            = "${lower(var.cluster_name)}-bootstrap-boot.vmdk"
    size             = "${var.boot_disk["disk_size"] != "" ? var.boot_disk["disk_size"] : data.vsphere_virtual_machine.rhcos_template.disks.0.size}"
    eagerly_scrub    = "${var.boot_disk["eagerly_scrub"] != "" ? var.boot_disk["eagerly_scrub"] : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
    thin_provisioned = "${var.boot_disk["thin_provisioned"] != "" ? var.boot_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
    keep_on_remove   = false
    unit_number      = 0
  }
  disk {
    label            = "${lower(var.cluster_name)}-bootstrap-disk1.vmdk"
    size             = "${var.additional_disk["disk_size"]}"
    eagerly_scrub    = "${var.additional_disk["eagerly_scrub"] != "" ? var.additional_disk["eagerly_scrub"] : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
    thin_provisioned = "${var.additional_disk["thin_provisioned"] != "" ? var.additional_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
    keep_on_remove   = false
    unit_number      = 1
  }

  ####
  # Network specifications
  ####
  network_interface {
    network_id   = "${var.private_network_id}"
    adapter_type = "${data.vsphere_virtual_machine.rhcos_template.network_interface_types[0]}"
  }

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhcos_template.id}"
  }

  extra_config = {
    # TODO: this requires CPU reservation
    # "sched.cpu.latencySensitivity" = "high"
    "sched.cpu.latencySensitivity" = "normal"
  }

  vapp {
    properties = {
      "guestinfo.ignition.config.data"          = "${base64encode(data.ignition_config.bootstrap_ign.rendered)}"
      "guestinfo.ignition.config.data.encoding" = "base64"
    }
  }
}


##################################
#### Create the Control Plane VM
##################################
resource "vsphere_virtual_machine" "control_plane" {
  count            = "${var.datastore_id != "" ? var.control_plane["count"] : 0}"

  depends_on = [
    "module.createignition.module_completed"
  ]

  folder = "${var.folder_path}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${var.vsphere_resource_pool_id}"

  name     = "${element(data.template_file.control_plane_hostname.*.rendered, count.index)}"
  num_cpus = "${var.control_plane["vcpu"]}"
  memory   = "${var.control_plane["memory"]}"

  #scsi_controller_count = 1
  #scsi_type = "lsilogic-sas"

  ####
  # Disk specifications
  ####
  datastore_id = "${var.datastore_id}"
  guest_id     = "${data.vsphere_virtual_machine.rhcos_template.guest_id}"
  scsi_type    = "${data.vsphere_virtual_machine.rhcos_template.scsi_type}"

  disk {
    label            = "${format("${lower(var.cluster_name)}-master%02d-boot.vmdk", count.index + 1)}"
    size             = "${var.boot_disk["disk_size"] != "" ? var.boot_disk["disk_size"] : data.vsphere_virtual_machine.rhcos_template.disks.0.size}"
    eagerly_scrub    = "${var.boot_disk["eagerly_scrub"] != "" ? var.boot_disk["eagerly_scrub"] : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
    thin_provisioned = "${var.boot_disk["thin_provisioned"] != "" ? var.boot_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
    keep_on_remove   = false
    unit_number      = 0
  }

  disk {
    label            = "${format("${lower(var.cluster_name)}-master%02d_disk1.vmdk", count.index + 1)}"
    size             = "${var.additional_disk["disk_size"]}"
    eagerly_scrub    = "${var.additional_disk["eagerly_scrub"] != "" ? var.additional_disk["eagerly_scrub"] : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
    thin_provisioned = "${var.additional_disk["thin_provisioned"] != "" ? var.additional_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
    keep_on_remove   = false
    unit_number      = 1
  }

  ####
  # Network specifications
  ####
  network_interface {
    network_id   = "${var.private_network_id}"
    adapter_type = "${data.vsphere_virtual_machine.rhcos_template.network_interface_types[0]}"
  }

  # TODO: in openshift 4, the bootstrap node generates a certificate for the api endpoint 10 minutes in the future, which means
  # the node will fail getting its config from the machine config server for 10 minutes until the certificate
  # becomes valid, delaying its boot and setup of static IP address.  disable the wait for an IP address to show up.  
  # because the installer synchronously waits for bootstrap to finish, we should catch any errors there.
  # going to have to ask red hat about this ...
  wait_for_guest_net_timeout = 0

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhcos_template.id}"
  }

  extra_config = {
    # TODO: this requires CPU reservation
    # "sched.cpu.latencySensitivity" = "high"
    "sched.cpu.latencySensitivity" = "normal"
  }

  vapp {
    properties = {
      "guestinfo.ignition.config.data"          = "${base64encode(element(data.ignition_config.control_plane_ign.*.rendered, count.index))}"
      "guestinfo.ignition.config.data.encoding" = "base64"
    }
  }
}


##################################
#### Create the Worker VMs
##################################
resource "vsphere_virtual_machine" "worker" {
  count            = "${var.datastore_id != "" ? var.worker["count"] : 0}"

  depends_on = [
    "module.createignition.module_completed"
  ]
  folder = "${var.folder_path}"

  #####
  # VM Specifications
  ####
  resource_pool_id = "${var.vsphere_resource_pool_id}"

  name     = "${element(data.template_file.worker_hostname.*.rendered, count.index)}"
  num_cpus = "${var.worker["vcpu"]}"
  memory   = "${var.worker["memory"]}"

  #scsi_controller_count = 1
  #scsi_type = "lsilogic-sas"

  ####
  # Disk specifications
  ####
  datastore_id = "${var.datastore_id}"
  guest_id     = "${data.vsphere_virtual_machine.rhcos_template.guest_id}"
  scsi_type    = "${data.vsphere_virtual_machine.rhcos_template.scsi_type}"

  disk {
    label            = "${format("${lower(var.cluster_name)}-worker%02d-boot.vmdk", count.index + 1)}"
    size             = "${var.boot_disk["disk_size"] != "" ? var.boot_disk["disk_size"] : data.vsphere_virtual_machine.rhcos_template.disks.0.size}"
    eagerly_scrub    = "${var.boot_disk["eagerly_scrub"] != "" ? var.boot_disk["eagerly_scrub"] : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
    thin_provisioned = "${var.boot_disk["thin_provisioned"] != "" ? var.boot_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
    keep_on_remove   = false
    unit_number      = 0
  }

  disk {
    label            = "${format("${lower(var.cluster_name)}-worker%02d_disk1.vmdk", count.index + 1)}"
    size             = "${var.additional_disk["disk_size"]}"
    eagerly_scrub    = "${var.additional_disk["eagerly_scrub"] != "" ? var.additional_disk["eagerly_scrub"] : data.vsphere_virtual_machine.rhcos_template.disks.0.eagerly_scrub}"
    thin_provisioned = "${var.additional_disk["thin_provisioned"] != "" ? var.additional_disk["thin_provisioned"] : data.vsphere_virtual_machine.rhcos_template.disks.0.thin_provisioned}"
    keep_on_remove   = false
    unit_number      = 1
  }

  ####
  # Network specifications
  ####
  network_interface {
    network_id   = "${var.private_network_id}"
    adapter_type = "${data.vsphere_virtual_machine.rhcos_template.network_interface_types[0]}"
  }

  # TODO: in openshift 4, the bootstrap node generates a certificate for the api endpoint 10 minutes in the future, which means
  # the node will fail getting its config from the machine config server for 10 minutes until the certificate
  # becomes valid, delaying its boot and setup of static IP address.  disable the wait for an IP address to show up.  
  # because the installer synchronously waits for bootstrap to finish, we should catch any errors there.
  # going to have to ask red hat about this ...
  wait_for_guest_net_timeout = 0

  ####
  # VM Customizations
  ####
  clone {
    template_uuid = "${data.vsphere_virtual_machine.rhcos_template.id}"
  }

  vapp {
    properties = {
      "guestinfo.ignition.config.data"          = "${base64encode(element(data.ignition_config.worker_ign.*.rendered, count.index))}"
      "guestinfo.ignition.config.data.encoding" = "base64"
    }
  }
}
