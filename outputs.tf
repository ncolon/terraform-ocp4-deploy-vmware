output "control_plane_private_ip" {
  value = "${var.control_plane_private_ip}"
}
output "worker_ip_address" {
  value = "${var.worker_ip_address}"
}

output "module_completed" {
  value = "${join(",", concat(
    vsphere_virtual_machine.bootstrap.*.id,
    vsphere_virtual_machine.bootstrap_ds_cluster.*.id,
    vsphere_virtual_machine.control_plane.*.id,
    vsphere_virtual_machine.control_plane_ds_cluster.*.id,
    vsphere_virtual_machine.worker.*.id,
    vsphere_virtual_machine.worker_ds_cluster.*.id,
  ))}"
}

