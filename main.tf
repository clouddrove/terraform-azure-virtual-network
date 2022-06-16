locals {
  ddos_pp_id = var.enable_ddos_pp ? azurerm_network_ddos_protection_plan.example[0].id : ""
}

module "labels" {

  source  = "clouddrove/labels/azure"
  version = "1.0.0"

  name        = var.name
  environment = var.environment
  managedby   = var.managedby
  label_order = var.label_order
  repository  = var.repository
}

resource "azurerm_virtual_network" "vnet" {
  count               = var.enable == true ? 1 : 0
  name                = "${var.name}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = length(var.address_spaces) == 0 ? [var.address_space] : var.address_spaces
  dns_servers         = var.dns_servers
  dynamic "ddos_protection_plan" {
    for_each = local.ddos_pp_id != "" ? ["ddos_protection_plan"] : []
    content {
      id     = local.ddos_pp_id
      enable = true
    }
  }
  tags = module.labels.tags
}

resource "azurerm_network_ddos_protection_plan" "example" {
  count               = var.enable_ddos_pp && var.enable == true ? 1 : 0
  name                = "${var.name}-ddospp"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = module.labels.tags
}

resource "azurerm_subnet" "subnet" {
  count               = var.enable == true ? length(var.subnet_names) : 0
  name                = "${var.name}-${var.subnet_names[count.index]}"
  resource_group_name = var.resource_group_name
  address_prefixes = [
    var.subnet_prefixes[count.index]
  ]
  virtual_network_name                           = join("", azurerm_virtual_network.vnet.*.name)
  enforce_private_link_endpoint_network_policies = lookup(var.subnet_enforce_private_link_endpoint_network_policies, var.subnet_names[count.index], false)
  service_endpoints                              = lookup(var.subnet_service_endpoints, var.subnet_names[count.index], [])

  dynamic "delegation" {
    for_each = var.delegations

    content {
      name = delegation.value["name"]

      service_delegation {
        name    = delegation.value["service_delegation_name"]
        actions = delegation.value["service_delegation_actions"]
      }
    }
  }
}

resource "azurerm_route_table" "routetable" {
  count               = var.enable && var.route_table_enabled ? 1 : 0
  name                = format("%s-route-table", module.labels.id)
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "route" {
    for_each = var.route_table
    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }
  disable_bgp_route_propagation = var.disable_bgp_route_propagation
  tags                          = module.labels.tags
}

resource "azurerm_subnet_route_table_association" "route_table_association" {
  count          = var.enable ? 1 : 0
  subnet_id      = join("", azurerm_subnet.subnet.*.id)
  route_table_id = join("", azurerm_route_table.routetable.*.id)
}

resource "azurerm_subnet_network_security_group_association" "default" {
  count                     = var.enable && var.enabled_nsg ? length(var.address_prefixes) : 0
  subnet_id                 = azurerm_subnet.subnet[count.index].id
  network_security_group_id = var.network_security_group_id
}
