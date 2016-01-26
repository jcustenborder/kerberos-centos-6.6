
$packages = [
  'krb5-workstation',
  'krb5-server',
  'krb5-libs',
  'haveged'
]

$kerberos_realm = upcase($::domain)
$kerberos_master_password = 'password123'

$keytab_root = '/vagrant/keytabs'

$zookeeper_principal = "zookeeper/kafka.example.com@${kerberos_realm}"
$kafka_principal = "kafka/kafka.example.com@${kerberos_realm}"
$kafkaclient_principal = "kafkaclient/kafka.example.com@${kerberos_realm}"

$zookeeper_keytab = "${keytab_root}/zookeeper.keytab"
$kafka_keytab = "${keytab_root}/kafka.keytab"
$kafkaclient_keytab = "${keytab_root}/kafkaclient.keytab"

package{'epel-release':
  ensure => 'installed'
} ->
service{'iptables':
  ensure => 'stopped',
  enable => false
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
service{'kadmin':
  ensure => 'running',
  enable => true
} ->
file { $kafka_keytab:
  mode    => '0644',  #Never do this in production
} ->
file { $zookeeper_keytab:
  mode    => '0644',  #Never do this in production
} ->
file { $kafkaclient_keytab:
  mode    => '0644',  #Never do this in production
}


Exec {
  path    => [
    '/usr/sbin',
    '/usr/bin',
    '/bin'
  ]
}
