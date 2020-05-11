# This will create a set of instances, load balancers and security groups in the
# specified AWS region.

ec2_securitygroup { 'test-sg':
  region => 'us-east-2',
}

ec2_instance { 'test-instance':
  region            => 'us-east-2',
  availability_zone => 'us-east-2a',
}

elb_loadbalancer { 'test-lb':
  region => 'us-east-2',
}

ec2_securitygroup { 'lb-sg': 
  ensure      => present,
  description => 'Security group for load balancer',
  ingress     => [{
    protocol => 'tcp',
    port     => 80,
    cidr     => '0.0.0.0/0'
  }],
}

ec2_securitygroup { 'web-sg':
  ensure      => present,
  description => 'Security group for web servers',
  ingress     => [{
    security_group => 'lb-sg',
  },{
    protocol => 'tcp',
    port     => 22,
    cidr     => '0.0.0.0/0'
  }],
}

ec2_securitygroup { 'db-sg':
  ensure      => present,
  description => 'Security group for database servers',
  ingress     => [{
    security_group => 'web-sg',
  },{
    protocol => 'tcp',
    port     => 22,
    cidr     => '0.0.0.0/0'
  }],
}

#  In the "VPC dashboard", click "Subnets".
#  Then, copy the "Subnet ID" of the subnet for the availability zone.
#  Then, click where the Name/Tag for that subnet goes, which should be blank, and paste in the "Subnet ID" as the Name.
#  Then, paste the Subnet ID/Name in the puppet code for the subnet.

ec2_instance { ['web-1', 'web-2']:
  ensure          => present,
  image_id        => 'ami-af8b30cf', # EU 'ami-b8c41ccf',
  subnet          => '10.10.10.0/24',
  security_groups => ['web-sg'],
  instance_type   => 't2.micro',
  tenancy         => 'default',
  tags            => {
    department => 'engineering',
    project    => 'cloud',
    created_by => $::id,
  }
}

ec2_instance { 'db-1':
  ensure          => present,
  image_id        => 'ami-af8b30cf', # EU 'ami-b8c41ccf',
  subnet          => '10.10.11.0/24',
  security_groups => ['db-sg'],
  instance_type   => 't2.micro',
  monitoring      => true,
  tenancy         => 'default',
  tags            => {
    department => 'engineering',
    project    => 'cloud',
    created_by => $::id,
  },
  block_devices => [
    {
      device_name => '/dev/sda1',
      volume_size => 8,
    }
  ]
}

elb_loadbalancer { 'lb-1':
  ensure             => present,
  availability_zones => ['us-east-2a'],
  instances          => ['web-1', 'web-2'],
  listeners          => [{
    protocol           => 'tcp',
    load_balancer_port => 80,
    instance_protocol  => 'tcp',
    instance_port      => 80,
  }],
}
