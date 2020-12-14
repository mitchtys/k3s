variable ssh_key_pem {
  description = "ssh pem/private key to use for connecting/setting up vm's"
  type        = string
}

variable hosts {
  description = "string/string map of host->ip's to use for setup"
  type        = map(string)
}

# TODO: Get this from the len(var.hosts)
variable size {
  description = "cluster size"
  type        = number
}

variable enabled {
  description = "If this module should or should not be enabled"
  type        = bool
  default     = false
}

locals {
  ssh_key_pem  = var.ssh_key_pem
  hosts        = var.hosts
  enabled      = var.enabled
  count        = var.enabled ? var.size : 0
  worker_count = var.enabled ? (var.size - 1) : 0
}

resource "null_resource" "setup_master" {
  # We only connect to the first host and use the existing ssh_setup for root do
  # do stuff between nodes.
  #
  # Note: I can change this, this is just to move things along faster for a
  # poc/mvp.
  connection {
    host        = values(local.hosts)[0]
    private_key = local.ssh_key_pem
    type        = "ssh"
    user        = "root"
  }

  # Temp hack, right now only one k8s thing at a time on a node
  provisioner "remote-exec" {
    inline = [<<-FIN
      set -e
      if ! command -v k3s ; then
        curl -sfL https://get.k3s.io | sh -s - --disable=traefik
      fi
      FIN
    ]
  }
}

resource "null_resource" "setup_workers" {
  count = local.worker_count
  depends_on = [
    null_resource.setup_master
  ]

  # We only connect to the first host and use the existing ssh_setup for root do
  # do stuff between nodes.
  #
  # Note: I can change this, this is just to move things along faster for a
  # poc/mvp.
  connection {
    host        = values(local.hosts)[count.index+1]
    private_key = local.ssh_key_pem
    type        = "ssh"
    user        = "root"
  }

  provisioner "remote-exec" {
    inline = [<<-FIN
      set -e
      if ! command -v k3s; then
        token=$(ssh ${values(local.hosts)[0]} "cat /var/lib/rancher/k3s/server/node-token")
        curl -sfL https://get.k3s.io | K3S_URL=https://${keys(local.hosts)[0]}:6443 K3S_TOKEN=$token sh -
      fi
    FIN
    ]
  }
}


# Let kubectl work
resource "null_resource" "k3s_env" {
  count = local.count
  depends_on = [
    null_resource.setup_master,
    null_resource.setup_workers
  ]

  connection {
    host        = values(local.hosts)[count.index]
    private_key = local.ssh_key_pem
    type        = "ssh"
    user        = "root"
  }

  provisioner "remote-exec" {
    inline = [<<-FIN
      echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' > /etc/profile.d/k3s.sh
    FIN
    ]
  }
}
