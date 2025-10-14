variable "control_plane_nodes" {
  description = "List of control-plane nodes with id, name, ip"
  type        = list(object({ id = number, name = string, ip = string }))
  default     = [{ id = 800, name = "talos-cp1", ip = "192.168.0.235" }]
}
