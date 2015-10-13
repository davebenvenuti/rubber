namespace :rubber do
  required_task :create_load_balancer do
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

  required_task :destroy_load_balancer do
  end
end

