require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:ec2_vpc_routetable).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws
  confine feature: :retries

  mk_resource_methods
  remove_method :tags=

  def self.instances
    regions.collect do |region|
      begin
        response = ec2_client(region).describe_route_tables()
        tables = []
        response.data.route_tables.each do |table|
          hash = route_table_to_hash(region, table)
          tables << new(hash) if has_name?(hash)
        end
        tables
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  read_only(:region, :vpc, :routes)

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name] # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov if resource[:region] == prov.region
      end
    end
  end

  def self.route_to_hash(region, route)
    if route.gateway_id
      gateway_name = route.state == 'active' ? gateway_name_from_id(region, route.gateway_id) : nil
      hash = {
        'destination_cidr_block' => route.destination_cidr_block,
        'gateway' => gateway_name,
      }
      gateway_name.nil? ? nil : hash
    elsif route.vpc_peering_connection_id
      peering_name = route.state == 'active' ? peering_name_from_id(region, route.vpc_peering_connection_id) : nil
      hash = {
        'destination_cidr_block' => route.destination_cidr_block,
        'peering_connection' => peering_name,
      }
      peering_name.nil? ? nil : hash
    end
  end

  def self.route_table_to_hash(region, table)
    name = extract_name_from_tag(table)
    return {} unless name
    routes = table.routes.collect do |route|
      route_to_hash(region, route)
    end.compact
    {
      name: name,
      id: table.route_table_id,
      vpc: vpc_name_from_id(region, table.vpc_id),
      ensure: :present,
      routes: routes,
      region: region,
      tags: remove_name_from_tags(table),
    }
  end

  def exists?
    Puppet.debug("Checking if Route table #{name} exists in #{target_region}")
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.info("Creating Route table #{name} in #{target_region}")
    ec2 = ec2_client(target_region)

    routes = resource[:routes]
    routes = [routes] unless routes.is_a?(Array)

    vpc_response = ec2.describe_vpcs(filters: [
      {name: "tag:Name", values: [resource[:vpc]]},
    ])
    fail "Multiple VPCs with name #{resource[:vpc]}" if vpc_response.data.vpcs.count > 1
    fail "No VPCs with name #{resource[:vpc]}" if vpc_response.data.vpcs.empty?

    response = ec2.create_route_table(
      vpc_id: vpc_response.data.vpcs.first.vpc_id,
    )
    id = response.data.route_table.route_table_id
    with_retries(:max_tries => 5) do
      ec2.create_tags(
        resources: [id],
        tags: extract_resource_name_from_tag,
      )
    end
    routes.each do |route|
      route_config = {
        route_table_id: id,
        destination_cidr_block: route['destination_cidr_block'],
      }

      if !route['gateway'].nil?
        internet_gateway_response = ec2.describe_internet_gateways(filters: [
          {name: 'tag:Name', values: [route['gateway']]},
        ])
        found_internet_gateway = !internet_gateway_response.data.internet_gateways.empty?

        unless found_internet_gateway
          vpn_gateway_response = ec2.describe_vpn_gateways(filters: [
            {name: 'tag:Name', values: [route['gateway']]},
          ])
          found_vpn_gateway = !vpn_gateway_response.data.vpn_gateways.empty?
        end

        route_config[:gateway_id] = if found_internet_gateway
            internet_gateway_response.data.internet_gateways.first.internet_gateway_id
          elsif found_vpn_gateway
            vpn_gateway_response.data.vpn_gateways.first.vpn_gateway_id
          else
            nil
          end

      elsif !route['peering_connection'].nil?
          vpc_peering_connection_response = ec2.describe_vpc_peering_connections(filters: [
            {name: 'tag:Name', values: [route['peering_connection']]},
          ])
          found_peering_connection = !vpc_peering_connection_response.data.vpc_peering_connections.empty?

        route_config[:vpc_peering_connection_id] = if found_peering_connection
            vpc_peering_connection_response.data.vpc_peering_connections.first.vpc_peering_connection_id
          else
            nil
          end
      end
      ec2.create_route(route_config) if route_config[:gateway_id] or route_config[:vpc_peering_connection_id]
    end
    @property_hash[:ensure] = :present
  end

  def destroy
    Puppet.info("Deleting Route table #{name} in #{target_region}")
    ec2_client(target_region).delete_route_table(route_table_id: @property_hash[:id])
    @property_hash[:ensure] = :absent
  end
end
