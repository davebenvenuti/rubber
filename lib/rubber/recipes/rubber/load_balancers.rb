namespace :rubber do
  required_task :create_load_balancer do
    env = rubber_cfg.environment.bind(nil, nil)
    cloud_env = env.cloud_providers[env.cloud_provider]

    name = get_env("NAME", "Name (alphanumeric and dashes only): ", true)
    zones = get_env("ZONES", "Availability Zones (comma delimited): ", true, cloud_env.availability_zone)
    vpc_id = get_env("VPC", "Vpc Id: ", false, nil)
    if vpc_id
      subnet_ids = get_env("SUBNET_IDS", "Subnet Ids (comman delimited): ", true)
    end

    opts = {
      id: name,
      availability_zones: zones.split(',')
    }

    if vpc_id
      opts[:vpc_id] = vpc_id
      opts[:subnet_ids] = subnet_ids.split(',')
    end

    cloud.elb_provider.load_balancers.create opts

    ENV['LOAD_BALANCER'] = name
    add_load_balancer_listener
  end

  required_task :add_load_balancer_listener do
    load_balancer = get_env("LOAD_BALANCER", "Load balancer name/id: ", true)
    protocol = get_env("PROTOCOL", "Listener protocol (HTTP,HTTPS): ", true, 'HTTP')
    port = get_env("PORT", "Listener port: ", true, "80")

    if protocol == 'HTTPS'
      ssl_certificate_id = get_env("SSL_CERTIFICATE", "SSL Certificate (leave blank to define new): ", false)

      unless ssl_certificate_id
        cert_file = get_env("CERT", "Path to SSL Certificate: ", true)
        key_file = get_env("KEY", "Path to SSL Private Key: ", true)
        chain_file = get_env("CHAIN", "Path to SSL Certificate Chain file (optional): ", false)
        cert_name = get_env("CERT_NAME", "Name: ", true)

        if chain_file
          opts = { 'CertificateChain' => File.read(chain_file) }
        else
          opts = {}
        end

        r = cloud.iam_provider.upload_server_certificate(
          File.read(cert_file),
          File.read(key_file),
          cert_name,
          opts
        )

        ssl_certificate_id = r.body['ServerCertificateId']
      end
    end

    instance_protocol = get_env("INSTANCE_PROTOCOL", "Instance protocol (HTTP,HTTPS): ", true, 'HTTP')
    instance_port = get_env("INSTANCE_PORT", "Instance Port: ", true, "80")

    opts = {
      'Protocol' => protocol,
      'LoadBalancerPort' => port,
      'InstanceProtocol' => instance_protocol,
      'InstancePort' => instance_port
    }

    if ssl_certificate_id
      opts['SSLCertificateId'] = ssl_certificate_id
    end

    cloud.create_load_balancer_listeners load_balancer, [opts]
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
end

