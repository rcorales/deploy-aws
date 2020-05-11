ec2_instance { 'Target Agent Node EC2':
    ensure              => present,
    region              => 'us-east-2',
    image_id            => 'ami-916f59f4',
    instance_type       => 't2.micro',
    security_groups     => ['mySecurityGroup'],
    subnet              => 'subnet-a99b0ae5',
    key_name            => 'puppetmaster',
  }

ec2_securitygroup { 'mySecurityGroup':
  region      => 'us-east-2',
  ensure      => present,
  description => 'Security Group for AWS EC2 instance',
ingress     => [{
    protocol => 'tcp',
    port     => 8080,
    cidr     => '0.0.0.0/0',
  },{
    protocol => 'tcp',
    port     => 80,
    cidr     => '0.0.0.0/0',
  },{
    protocol => 'tcp',
    port     => 22,
    cidr     => '0.0.0.0/0',
 }],
  tags        => {
    tag_name  => 'mySecurityGroup',
},
}