# If you run this outside of vagrant. Run these commands first.
#   puppet module install puppetlabs-stdlib
#   puppet module install puppetlabs-inifile


$packages = [
  'confluent-kafka-2.11.7',
  'confluent-schema-registry',
  'java-1.8.0-openjdk-headless',
  'krb5-workstation',
  'krb5-server',
  'krb5-libs',
  'haveged'
]

$listeners = [
  'PLAINTEXT://:9092',
  'SASL_PLAINTEXT://:9095'
]
$kerberos_realm = upcase($::domain)
$kerberos_master_password = 'password123'

$zookeeper_principal = "zookeeper/${fqdn}@${kerberos_realm}"
$zookeeper_keytab = '/etc/security/keytabs/zookeeper.keytab'
$kafka_principal = "kafka/${fqdn}@${kerberos_realm}"
$kafka_keytab = '/etc/security/keytabs/kafka.keytab'
$kafkaclient_principal = "kafkaclient/${fqdn}@${kerberos_realm}"
$kafkaclient_keytab = '/etc/security/keytabs/kafkaclient.keytab'

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
service{'firewall':
  ensure => 'stopped',
  enable => false
}
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
service{'haveged':
  ensure => 'running',
  enable => true
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
        kdc = ${::fqdn}:88
        admin_server = ${::fqdn}:749
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
file{'/var/kerberos/krb5kdc/kdc.conf':
  ensure  => 'present',
  content => "default_realm = ${kerberos_realm}

[kdcdefaults]
    v4_mode = nopreauth
    kdc_ports = 0

[realms]
    ${kerberos_realm} = {
        kdc_ports = 88
        admin_keytab = /etc/kadm5.keytab
        database_name = /var/kerberos/krb5kdc/principal
        acl_file = /var/kerberos/krb5kdc/kadm5.acl
        key_stash_file = /var/kerberos/krb5kdc/stash
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        master_key_type = des3-hmac-sha1
        supported_enctypes = arcfour-hmac:normal des3-hmac-sha1:normal des-cbc-crc:normal des:normal des:v4 des:norealm des:onlyrealm des:afs3
        default_principal_flags = +preauth
    }
"
} ->
file{'/var/kerberos/krb5kdc/kadm5.acl':
  ensure  => 'present',
  content => "*/admin@${kerberos_realm}      *
"
} ->
exec{'kdb5_util create':
  command => "printf '${kerberos_master_password}\n${kerberos_master_password}\n'|   kdb5_util create -r ${kerberos_realm} -s",
  creates => '/var/kerberos/krb5kdc/principal',
  path    => [
    '/usr/sbin',
    '/usr/bin'
  ]
} ->
file{'/etc/security/keytabs':
  ensure => directory,
} ->
exec{'add kafka principal':
  command => "kadmin.local -q 'addprinc -randkey ${kafka_principal}'",
  unless  => "kadmin.local -q 'listprincs ${kafka_principal}' | grep '${kafka_principal}'",
} ->
exec{'create kafka keytab':
  command => "kadmin.local -q 'ktadd -k ${kafka_keytab} ${kafka_principal}'",
  creates => $kafka_keytab,
} ->
exec{'add zookeeper principal':
  command => "kadmin.local -q 'addprinc -randkey ${zookeeper_principal}'",
  unless  => "kadmin.local -q 'listprincs ${zookeeper_principal}' | grep '${zookeeper_principal}'",
} ->
exec{'create zookeeper keytab':
  command => "kadmin.local -q 'ktadd -k ${zookeeper_keytab} ${zookeeper_principal}'",
  creates => $zookeeper_keytab,
} ->
exec{'add kafkaclient principal':
  command => "kadmin.local -q 'addprinc -randkey ${kafkaclient_principal}'",
  unless  => "kadmin.local -q 'listprincs ${kafkaclient_principal}' | grep '${kafkaclient_principal}'",
} ->
exec{'create kafkaclient keytab':
  command => "kadmin.local -q 'ktadd -k ${kafkaclient_keytab} ${kafkaclient_principal}'",
  creates => $kafkaclient_keytab,
} ->
service{'krb5kdc':
  ensure => 'running',
  enable => true
} ->
file { '/etc/security/keytabs/kafkaclient.keytab':
  mode    => '0644',  #Never do this in production
} ->
file { '/etc/security/keytabs/kafka.keytab':
  mode    => '0644',  #Never do this in production
} ->
file { '/etc/security/keytabs/zookeeper.keytab':
  mode    => '0644',  #Never do this in production
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
  value   => 'kafka'
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
bootstrap.servers=${::fqdn}:9095
group.id=test-consumer-group
security.protocol=SASL_PLAINTEXT
sasl.kerberos.service.name=kafka
"
} ->

file{'/etc/kafka/producer_sasl.properties':
  ensure  => present,
  content => "#Managed by puppet. Save changes to a different file.
bootstrap.servers=${::fqdn}:9095
security.protocol=SASL_PLAINTEXT
sasl.kerberos.service.name=kafka
"
} ->
notify{'info':
  message => "Kerberos has been configured on this hosts.
All of the keytabs are located in /etc/security/keytabs. They are currently marked as world readable. DO NOT DO THIS IN
PRODUCTION.

kafka_client_jaas.conf is a client jaas configuration file. producer_sasl.properties and consumer_sasl.properties are
configured for kerberos. Please refer to http://docs.confluent.io/2.0.0/kafka/sasl.html#configuring-kafka-clients

RUN
sudo /usr/sbin/start-kerberos-kafka

to start zookeeper and kafka with kerberos.
",
  withpath => false
}





Exec {
  path    => [
    '/usr/sbin',
    '/usr/bin',
    '/bin'
  ]
}
