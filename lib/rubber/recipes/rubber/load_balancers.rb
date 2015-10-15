namespace :rubber do
  required_task :create_load_balancer do
    env = rubber_cfg.environment.bind(nil, nil)
    cloud_env = env.cloud_providers[env.cloud_provider]

    name = get_env("NAME", "Name (alphanumeric and dashes only)", true)
    zones = get_env("ZONES", "Availability Zones (comma delimited, leave blank for VPC)", false)
    vpc_id = nil

    if zones.length == 0
      vpc_id = get_env("VPC", "VPC Id or Rubber Alias", false, nil)

      vpcs = cloud.describe_vpcs
      vpc = nil

      unless vpc_id =~ /^vpc-.*$/
        vpc_alias = vpc_id
        # Convert the alias to a vpc id
        vpc = vpcs.find { |vpc| vpc[:rubber_alias] == vpc_id }
        vpc_id = vpc[:id]
        logger.info "Using #{vpc_id} for #{vpc_alias}"
      else
        vpc = vpcs.find { |vpc| vpc[:id] == vpc_id }
      end

      default_subnet = vpc[:subnets].find { |s| s[:public] }
      default_subnet_id = default_subnet && default_subnet[:id]

      subnet_ids = get_env("SUBNET", "Subnet Ids (comma delimited)", true, default_subnet_id)
    end

    opts = {
      id: name,
    }

    if subnet_ids
      opts[:subnet_ids] = subnet_ids.split(',')
    else
      opts[:availability_zones] = zones
    end

    cloud.elb_provider.load_balancers.create opts

    ENV['LOAD_BALANCER'] = name
    add_load_balancer_listener
  end

  required_task :add_load_balancer_listener do
    load_balancer = get_env("LOAD_BALANCER", "Load balancer name/id", true)
    protocol = get_env("PROTOCOL", "Listener protocol (HTTP,HTTPS)", true, 'HTTP')
    port = get_env("PORT", "Listener port", true, "80")
    ssl_certificate_id = nil

    if protocol == 'HTTPS'
      ssl_certificate_id = get_env("SSL_CERTIFICATE", "SSL Certificate (leave blank to define new)", false)

      unless ssl_certificate_id && (ssl_certificate_id.length > 0)
        cert_file = get_env("CERT", "Path to SSL Certificate", true)
        key_file = get_env("KEY", "Path to SSL Private Key", true)
        chain_file = get_env("CHAIN", "Path to SSL Certificate Chain file (optional)", false)
        cert_name = get_env("CERT_NAME", "Certificate Name", true)

        if chain_file && (chain_file.length > 0)
          opts = { 'CertificateChain' => File.read(File.expand_path(chain_file)) }
        else
          opts = {}
        end

        r = cloud.iam_provider.upload_server_certificate(
          File.read(File.expand_path(cert_file)),
          File.read(File.expand_path(key_file)),
          cert_name,
          opts
        )

        ssl_certificate_id = r.body['ServerCertificateId']
      end
    end

    instance_protocol = get_env("INSTANCE_PROTOCOL", "Instance protocol (HTTP,HTTPS)", true, 'HTTP')
    instance_port = get_env("INSTANCE_PORT", "Instance Port", true, "80")

    opts = {
      'Protocol' => protocol,
      'LoadBalancerPort' => port,
      'InstanceProtocol' => instance_protocol,
      'InstancePort' => instance_port
    }

    if ssl_certificate_id
      opts['SSLCertificateId'] = ssl_certificate_id
    end

    cloud.elb_provider.create_load_balancer_listeners load_balancer, [opts]
  end

  required_task :describe_load_balancers do
    load_balancers = cloud.describe_load_balancers

    if load_balancers.length > 0
      puts "Load Balancers:"
      load_balancers.each do |load_balancer|
        puts "\t#{load_balancer[:name]}"
        puts "\t\t#{load_balancer[:dns_name]}"
        puts "\t\t#{load_balancer[:zones].join(',')}"
        puts "\t\t#{load_balancer[:vpc_id]}" if load_balancer[:vpc_id]
        puts "\t\tListeners:"
        load_balancer[:listeners].each do |listener|
          puts "\t\t\t#{listener[:protocol]} #{listener[:port]}:#{listener[:instance_port]}"
        end
      end
    else
      puts "No load balancers found"
    end
  end

  required_task :describe_ssl_certificates do
    certs = cloud.describe_ssl_certificates

    if certs.length > 0
      puts "SSL Certificates:"
      certs.each do |cert|
        puts "\t#{cert[:id]}\t#{cert[:name]}"
      end
    else
      puts "No SSL Certificates found"
    end
  end

  required_task :add_instances_to_load_balancer do
    instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)
    aliases = Rubber::Util::parse_aliases(instance_aliases)
    load_balancer = get_env('LOAD_BALANCER', "Load balancer name")

#    env = rubber_cfg.environment.bind(nil, nil)
    instance_ids = rubber_instances.map { |instance|
      aliases.include?(instance.name) ? instance.instance_id : nil
    }.compact

    cloud.elb_provider.register_instances_with_load_balancer(instance_ids, load_balancer)
  end

  required_task :remove_instances_from_load_balancer do
    instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)
    aliases = Rubber::Util::parse_aliases(instance_aliases)
    load_balancer = get_env('LOAD_BALANCER', "Load balancer name")

#    env = rubber_cfg.environment.bind(nil, nil)
    instance_ids = rubber_instances.map { |instance|
      aliases.include?(instance.name) ? instance.instance_id : nil
    }.compact

    cloud.elb_provider.deregister_instances_with_load_balancer(instance_ids, load_balancer)
  end
end

