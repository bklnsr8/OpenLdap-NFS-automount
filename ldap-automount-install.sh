#!/usr/bin/env bash
# Author: Reginald Sands
<<'END' 
Purpose: To install the openldap and nfs-automount
as the server side for the RHCSA ldap and autofs client configuration objective
END

# install the required packages
yum install \
openldap \
openldap-clients \
openldap-servers \
migrationtools \
nfs-utils \
nss_pam_ldap \
autofs

<<'END'
LDAP server installation procedure:
- Create root passwd
	- Ask the user for the password
	- Check if the user as entered a password
- Generate a x509 certificate
	- Crate the public and private cert
	- Secure the content of the /etc/openldap/certs directory
- Transfer private key to the /etc/openldap/certs directory
- Prepare the LDAP database
- Generate database files
- Change LDAP database ownership:
- enable and State slapd
- 
END

## create a root passwd

# Ask the user for the password
echo -n "Enter ldap root passwd: "
read passwd

# Check if the user as entered a passwd
if ($passwd <= 3);
  then
    echo "Enter ldap root passwd: "
  else
    rootpw = $(slappasswd -s $passwd -n)
    echo 'rootpw:' $rootpw > /etc/openldap/passwd
fi

## Generate a x509 certificate

# Create the public and private cert
openssl req \
-new \
-x509 \
-nodes \
-out /etc/openldap/certs/cert.pem \
-keyout /etc/openldap/certs/priv.pem \
-days 365

# Secure the content of the /etc/openldap/certs directory
cd /etc/openldap/certs
chown ldap:ldap *
chmod 600 priv.pem

# Prepare the LDAP database
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG

# Generate database files
slaptest

# Change LDAP database ownership:
chown ldap:ldap /var/lib/ldap/*

# enable and State slapd 
systemctl enable slapd
systemctl start slapd

<<'END'
LDAP Server configuration:
 - add the cosine & nis LDAP schemas:
 - create the /etc/openldap/changes.ldif
 - Send the new configuration to the slapd server:
 - Create the /etc/openldap/base.ldif
 - Create a guest user directory
END

## LDAP Server configuration:

# add the cosine & nis LDAP schemas:

#* add the cosine schemas
ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/cosine.ldif

#* add the nis schemas
ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/nis.ldif

# create the /etc/openldap/changes.ldif
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=example,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,dc=example,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: PASSWORD

dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/cert.pem

dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/priv.pem

dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: -1

dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=example,dc=com" read by * none

# Send the new configuration to the slapd server:
ldapmodify -Y EXTERNAL -H ldapi:/// -f /etc/openldap/changes.ldif 

# Create the /etc/openldap/base.ldif
dn: dc=example,dc=com
dc: example
objectClass: top
objectClass: domain

dn: ou=People,dc=example,dc=com
ou: People
objectClass: top
objectClass: organizationalUnit

dn: ou=Group,dc=example,dc=com
ou: Group
objectClass: top
objectClass: organizationalUnit

# Build the structure of the directory service:
ldapadd -x -w redhat -D cn=Manager,dc=example,dc=com -f /etc/openldap/base.ldif

# Create a guest user directory
mkdir /home/guests

<<'END'
User Account Migration
- Create test users
- Edit the migrate_common.ph file
- Create the current users in the directory service:
	- import user accounts
	- import group accounts
END

## User Account Migration

## Create test users

# Create user accounts
useradd -d /home/guests/ldapuser01 ldapuser01
useradd -d /home/guests/ldapuser02 ldapuser02

# Create user passwd
echo 'iq156sr7' | passwd ldapuser01 --stdin
echo 'iq156sr7' | passwd ldapuser02 --stdin

# Edit the migrate_common.ph file

#* migrate_common file
migrate_common='/usr/share/migrationtools/migrate_common'

#* $DEFAULT_MAIL_DOMAIN = "example.com";
sed -i 's/$DEFAULT_MAIL_DOMAIN =.*/$DEFAULT_MAIL_DOMAIN = "example.com";/' $migrate_common

#* $DEFAULT_BASE = "dc=example,dc=com";
sed -i 's/\$DEFAULT_BASE =.*/\$DEFAULT_BASE = "dc=example,dc=com";/' $migrate_common

## Create the current users in the directory service:

# import user accounts
grep ":10[0-9][0-9]" /etc/passwd > passwd
/usr/share/migrationtools/migrate_passwd.pl passwd users.ldif
ldapadd -x -w $rootpw -D cn=Manager,dc=example,dc=com -f users.ldif

# import group accounts
grep ":10[0-9][0-9]" /etc/group > group
/usr/share/migrationtools/migrate_group.pl group groups.ldif
ldapadd -x -w redhat -D cn=Manager,dc=example,dc=com -f groups.ldif

<<'END'
Configure the LDAP server to use autofs
- Create Auto master ldap
- Create Auto Home in ldap
- Create misc in ldap
END

## Configure the LDAP server to use autofs

# Create Auto master ldap
dn: ou=auto.master,dc=lgcpu1
objectClass: top
objectClass: automountMap
ou: auto.master

dn: cn=/home,ou=auto.master,dc=lgcpu1
objectClass: automount
automountInformation: ldap:ou=auto.home,dc=lgcpu1
cn: /home

dn: cn=/share,ou=auto.master,dc=lgcpu1
objectClass: automount
automountInformation: ldap:ou=auto.misc, dc=lgcpu1
cn: /share

# Create Auto Home in ldap

# Create misc in ldap
dn: ou=auto.misc,dc=lgcpu1
objectClass: top
objectClass: automountMap
ou: auto.misc

<<'END'
Configure NFS Server
- Edit /etc/exports
- Start and enable nfs service
END

## Configure NFS Server

# Edit /etc/exports
/home/guests 192.168.10.1/24(rw)

# Start and enable nfs service
service nfs start

<<'END'
Firewall Configuration
- Add a ldap service to the firewall
- Add a nfs service to the firewall
END

## Add a ldap service to the firewall

# add ldap serivce
firewall-cmd --permanent --add-service=ldap

# add nfs service
firewall-cmd --permanent --add-service=nfs

# reload firewall
firewall-cmd --reload

