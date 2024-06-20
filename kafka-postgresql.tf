# Infrastructure for Yandex Cloud Managed Service for PostgreSQL and Managed Service for Apache Kafka®
#
# RU: https://yandex.cloud/ru/docs/data-transfer/tutorials/mkf-to-mpg
# EN: https://yandex.cloud/en/docs/data-transfer/tutorials/mkf-to-mpg
#
# Configure the parameters of the source and target clusters:

locals {
  pg_version  = "" # Desired version of PostgreSQL. For available versions, see the documentation main page: https://yandex.cloud/en/docs/managed-postgresql/.
  pg_password = "" # PostgreSQL admin's password
  kf_version  = "" # Desired version of Apache Kafka®. For available versions, see the documentation main page: https://yandex.cloud/en/docs/managed-kafka/.
  kf_password = "" # Apache Kafka® user's password

  # Specify these settings ONLY AFTER the clusters are created. Then run "terraform apply" command again.
  # You should set up endpoints using the GUI to obtain their IDs
  kf_source_endpoint_id = "" # Set the source endpoint ID
  transfer_enabled      = 0  # Set to 1 to enable the transfer

  # The following settings are predefined. Change them only if necessary.

  # Managed Service for PostgreSQL:
  mpg_network_name        = "mpg_network"        # Name of the network for the PostgreSQL cluster
  mpg_subnet_name         = "mpg_subnet-a"       # Name of the subnet for the PostgreSQL cluster
  mpg_security_group_name = "mpg_security_group" # Name of the security group for the PostgreSQL cluster
  pg_cluster_name         = "mpg-cluster"        # Name of the PostgreSQL cluster
  pg_username             = "pg-user"            # Username of the PostgreSQL cluster
  pg_db_name              = "db1"                # Name of the PostgreSQL database

  # Managed Service for Apache Kafka®:
  mkf_network_name        = "mkf_network"        # Name of the network for the Apache Kafka® cluster
  mkf_subnet_name         = "mkf_subnet-a"       # Name of the subnet for the Apache Kafka® cluster
  mkf_security_group_name = "mkf_security_group" # Name of the security group for the Apache Kafka® cluster
  kf_cluster_name         = "mkf-cluster"        # Name of the Apache Kafka® cluster
  kf_topic                = "sensors"            # Name of the Apache Kafka® topic
  kf_username             = "mkf-user"           # Username of the Apache Kafka® cluster

  # Data Transfer:
  target_endpoint_name    = "pg-target-tf"     # Name of the target endpoint for the Managed Service for PostgreSQL
  transfer_name           = "mkf-mpg-transfer" # Name of the transfer from the Managed Service for Apache Kafka® to the Managed Service for PostgreSQL
}

# Network infrastructure

resource "yandex_vpc_network" "mpg_network" {
  description = "Network for Managed Service for PostgreSQL"
  name        = local.mpg_network_name
}

resource "yandex_vpc_network" "mkf_network" {
  description = "Network for Managed Service for Apache Kafka®"
  name        = local.mkf_network_name
}

resource "yandex_vpc_subnet" "mpg_subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone for PostgreSQL"
  name           = local.mpg_subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mpg_network.id
  v4_cidr_blocks = ["10.128.0.0/18"]
}

resource "yandex_vpc_subnet" "mkf_subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone for Apache Kafka®"
  name           = local.mkf_subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mkf_network.id
  v4_cidr_blocks = ["10.129.0.0/24"]
}

resource "yandex_vpc_security_group" "mpg_security_group" {
  description = "Security group for Managed Service for PostgreSQL"
  network_id  = yandex_vpc_network.mpg_network.id
  name        = local.mpg_security_group_name

  ingress {
    description    = "Allow incoming traffic from the Internet"
    protocol       = "TCP"
    port           = 6432
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "mkf_security_group" {
  description = "Security group for Managed Service for Apache Kafka®"
  network_id  = yandex_vpc_network.mkf_network.id
  name        = local.mkf_security_group_name

  ingress {
    description    = "Allow incoming traffic from the port 9091"
    protocol       = "TCP"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Infrastructure for the Managed Service for PostgreSQL cluster

resource "yandex_mdb_postgresql_cluster" "mpg-cluster" {
  description        = "Managed Service for PostgreSQL cluster"
  name               = local.pg_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mpg_network.id
  security_group_ids = [yandex_vpc_security_group.mpg_security_group.id]

  config {
    version = local.pg_version
    resources {
      resource_preset_id = "s2.micro" # 2 vCPU, 8 GB RAM
      disk_type_id       = "network-ssd"
      disk_size          = "20" # GB
    }
  }

  host {
    zone             = "ru-central1-a"
    subnet_id        = yandex_vpc_subnet.mpg_subnet-a.id
    assign_public_ip = true # Required for connection from the Internet
  }
}

# User of the Managed service for the PostgreSQL cluster
resource "yandex_mdb_postgresql_user" "pg-user" {
  cluster_id = yandex_mdb_postgresql_cluster.mpg-cluster.id
  name       = local.pg_username
  password   = local.pg_password
}

# Database of the Managed service for the PostgreSQL cluster
resource "yandex_mdb_postgresql_database" "mpg-db" {
  cluster_id = yandex_mdb_postgresql_cluster.mpg-cluster.id
  name       = local.pg_db_name
  owner      = yandex_mdb_postgresql_user.pg-user.name
  depends_on = [
    yandex_mdb_postgresql_user.pg-user
  ]
}

# Infrastructure for the Managed Service for Apache Kafka® cluster

resource "yandex_mdb_kafka_cluster" "mkf-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  environment        = "PRODUCTION"
  name               = local.kf_cluster_name
  network_id         = yandex_vpc_network.mkf_network.id
  security_group_ids = [yandex_vpc_security_group.mkf_security_group.id]

  config {
    assign_public_ip = true # Required for connection from the Internet
    brokers_count    = 1
    version          = local.kf_version
    kafka {
      resources {
        disk_size          = 10 # GB
        disk_type_id       = "network-ssd"
        resource_preset_id = "s2.micro"
      }
    }

    zones = ["ru-central1-a"]
  }

  depends_on = [
    yandex_vpc_subnet.mkf_subnet-a
  ]
}

# Topic of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_topic" "sensors" {
  cluster_id         = yandex_mdb_kafka_cluster.mkf-cluster.id
  name               = local.kf_topic
  partitions         = 1
  replication_factor = 1
}

# User of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "mkf-user" {
  cluster_id = yandex_mdb_kafka_cluster.mkf-cluster.id
  name       = local.kf_username
  password   = local.kf_password
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

# Data Transfer infrastructure

resource "yandex_datatransfer_endpoint" "pg_target" {
  description = "Target endpoint for the Managed Service for PostgreSQL cluster"
  count       = local.transfer_enabled
  name        = local.target_endpoint_name
  settings {
    postgres_target {
      connection {
        mdb_cluster_id = yandex_mdb_postgresql_cluster.mpg-cluster.id
      }
      database = yandex_mdb_postgresql_database.mpg-db.name
      user     = yandex_mdb_postgresql_user.pg-user.name
      password {
        raw = local.pg_password
      }
    }
  }
}

resource "yandex_datatransfer_transfer" "mkf-mpg-transfer" {
  description = "Transfer from the Managed Service for Apache Kafka® to the Managed Service for PostgreSQL"
  count       = local.transfer_enabled
  name        = local.transfer_name
  source_id   = local.kf_source_endpoint_id
  target_id   = yandex_datatransfer_endpoint.pg_target[count.index].id
  type        = "INCREMENT_ONLY" # Data replication from the source Managed Service for Apache Kafka® topic to the target Managed Service for PostgreSQL cluster
}
