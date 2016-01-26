# If you run this outside of vagrant. Run these commands first.
# You must also ensure that the machine is resolvable by it's fully qualified name.
#
# puppet module install puppetlabs-stdlib
# puppet module install puppetlabs-inifile
# puppet module install puppetlabs-motd
# puppet module install saz-ssh


$packages = [
  'confluent-kafka-2.11.7',
  'confluent-schema-registry',
  'java-1.8.0-openjdk-headless',
  'krb5-workstation',
  'krb5-libs',
]

$sasl_port = 9095

$listeners = [
  'PLAINTEXT://:9092',
  "SASL_PLAINTEXT://:${sasl_port}"
]
$kerberos_realm = upcase($::domain)
$kerberos_master_password = 'password123'

$keytab_root = '/etc/security/keytabs'

$zookeeper_principal = "zookeeper/${fqdn}@${kerberos_realm}"
$zookeeper_keytab = "${keytab_root}/zookeeper.keytab"
$kafka_principal = "kafka/${fqdn}@${kerberos_realm}"
$kafka_keytab = "${keytab_root}/kafka.keytab"
$kafkaclient_principal = "kafkaclient/${fqdn}@${kerberos_realm}"
$kafkaclient_keytab = "${keytab_root}/kafkaclient.keytab"

$kafkaclient_keytab_source = "file:///vagrant/keytabs/kafkaclient.keytab"
$kafka_keytab_source       = "file:///vagrant/keytabs/kafka.keytab"
$zookeeper_keytab_source   = "file:///vagrant/keytabs/zookeeper.keytab"

$log_dir='/var/lib/kafka'

define property_setting(
  $ensure,
  $value,
  $path
) {
  ini_setting{$name:
    ensure  => $ensure,
    path    => $path,
    setting => $name,
    value   => $value
  }
}

package{'epel-release':
  ensure => 'installed'
} ->
service{'iptables':
  ensure => 'stopped',
  enable => false
} ->
yumrepo{'confluent':
  ensure   => 'present',
  descr    => 'Confluent repository for 2.0.x packages',
  baseurl  => 'http://packages.confluent.io/rpm/2.0',
  gpgcheck => 1,
  gpgkey   => 'http://packages.confluent.io/rpm/2.0/archive.key',
} ->
package{$packages:
  ensure => 'installed'
} ->
file{$keytab_root:
  ensure => directory,
} ->
file { $kafka_keytab:
  ensure  => present,
  source  => $kafka_keytab_source,
  mode    => '0644',  #Never do this in production
} ->
file { $zookeeper_keytab:
  ensure  => present,
  source  => $zookeeper_keytab_source,
  mode    => '0644',  #Never do this in production
} ->
file { $kafkaclient_keytab:
  ensure  => present,
  source  => $kafkaclient_keytab_source,
  mode    => '0644',  #Never do this in production
} ->
file{'/etc/krb5.conf':
  ensure  => 'present',
  content => "[libdefaults]
    default_realm = ${kerberos_realm}
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    forwardable = true
    udp_preference_limit = 1000000
    default_tkt_enctypes = des-cbc-md5 des-cbc-crc des3-cbc-sha1
    default_tgs_enctypes = des-cbc-md5 des-cbc-crc des3-cbc-sha1
    permitted_enctypes = des-cbc-md5 des-cbc-crc des3-cbc-sha1

[realms]
    ${kerberos_realm} = {
        kdc = kdc.example.com:88
        admin_server = kdc.example.com:749
        default_domain = ${::domain}
    }

[domain_realm]
    .${::domain} = ${kerberos_realm}
     ${::domain} = ${kerberos_realm}

[logging]
    kdc = FILE:/var/log/krb5kdc.log
    admin_server = FILE:/var/log/kadmin.log
    default = FILE:/var/log/krb5lib.log
"
} ->
file{'/etc/kafka/kafka_server_jaas.conf':
  ensure  => present,
  content => "KafkaServer {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab=\"${kafka_keytab}\"
    principal=\"${kafka_principal}\";
};

Client {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab=\"${kafka_keytab}\"
    principal=\"${kafka_principal}\";
};
"
} ->
file{ '/etc/kafka/kafka_client_jaas.conf':
  ensure  => present,
  content => "KafkaClient {
    com.sun.security.auth.module.Krb5LoginModule required
    useKeyTab=true
    storeKey=true
    keyTab=\"${kafkaclient_keytab}\"
    principal=\"${kafkaclient_principal}\";
};
"
} ->
file{'/etc/kafka/zookeeper_jaas.conf':
  ensure  => present,
  content => "Server {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  keyTab=\"${zookeeper_keytab}\"
  storeKey=true
  useTicketCache=false
  principal=\"${zookeeper_principal}\";
};
"
} ->
property_setting{'zookeeper.connect':
  ensure  => present,
  path    => '/etc/kafka/server.properties',
  value   => "${::fqdn}:2181"
} ->
property_setting{'listeners':
  ensure  => present,
  path    => '/etc/kafka/server.properties',
  value   => join($listeners, ',')
} ->
property_setting{'log.dirs':
  ensure  => present,
  path    => '/etc/kafka/server.properties',
  value   => $log_dir
} ->
property_setting{'sasl.kerberos.service.name':
  ensure  => present,
  path    => '/etc/kafka/server.properties',
  value   => 'kafka'
} ->
property_setting{'zookeeper.set.acl':
  ensure  => present,
  path    => '/etc/kafka/server.properties',
  value   => true
} ->
file{$log_dir:
  ensure => directory
} ->
property_setting{'authProvider.1':
  ensure  => present,
  path    => '/etc/kafka/zookeeper.properties',
  value   => 'org.apache.zookeeper.server.auth.SASLAuthenticationProvider'
} ->
property_setting{'jaasLoginRenew':
  ensure  => present,
  path    => '/etc/kafka/zookeeper.properties',
  value   => 3600000
} ->
file{'/usr/sbin/start-kerberos-kafka':
  ensure  => present,
  mode    => '0755',
  content => "export KAFKA_HEAP_OPTS='-Xmx256M -Djava.security.auth.login.config=/etc/kafka/zookeeper_jaas.conf'
/usr/bin/zookeeper-server-start /etc/kafka/zookeeper.properties &
sleep 5
export KAFKA_HEAP_OPTS='-Xmx256M -Djava.security.auth.login.config=/etc/kafka/kafka_server_jaas.conf'
/usr/bin/kafka-server-start /etc/kafka/server.properties &
"
} ->

file{'/etc/kafka/consumer_sasl.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
bootstrap.servers=${::fqdn}:${sasl_port}
group.id=test-consumer-group
security.protocol=SASL_PLAINTEXT
sasl.kerberos.service.name=kafka
"
} ->

file{'/etc/kafka/producer_sasl.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
bootstrap.servers=${::fqdn}:${sasl_port}
security.protocol=SASL_PLAINTEXT
sasl.kerberos.service.name=kafka
"
} ->
class{'::motd':
  content => "Kerberos has been configured on this hosts.
All of the keytabs are located in /etc/security/keytabs. They are currently marked as world readable (0644). DO NOT DO THIS IN
PRODUCTION.

kafka_client_jaas.conf is a client jaas configuration file. producer_sasl.properties and consumer_sasl.properties are
configured for kerberos. Please refer to http://docs.confluent.io/2.0.0/kafka/sasl.html#configuring-kafka-clients

Console Producer:
export KAFKA_HEAP_OPTS='-Xmx512M -Djava.security.auth.login.config=/etc/kafka/kafka_client_jaas.conf'

echo \"Hello world\" | kafka-console-producer --producer.config /etc/kafka/producer_sasl.properties --broker-list '${::fqdn}:${sasl_port}' --topic foo

Console Consumer:
kafka-console-consumer --consumer.config /etc/kafka/consumer_sasl.properties --new-consumer --bootstrap-server '${::fqdn}:${sasl_port}' --topic foo --from-beginning

RUN
sudo /usr/sbin/start-kerberos-kafka
to start zookeeper and kafka with kerberos.
"
} ->
class{'ssh':
  storeconfigs_enabled => false,
  server_options => {
    'PrintMotd'            => 'yes',
    'PermitRootLogin'      => 'yes',
    'UseDNS'               => 'no',
    'UsePAM'               => 'yes',
    'X11Forwarding'        => 'yes',
    'GSSAPIAuthentication' => 'no'
  }
}

Exec {
  path    => [
    '/usr/sbin',
    '/usr/bin',
    '/bin'
  ]
}
