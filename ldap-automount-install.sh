#!/usr/bin/env bash
# Author: Reginald Sands
<<'END' 
Purpose: To install the openldap and nfs-automount
as the server side for the RHCSA ldap and autofs client configuration objective
END

# Create installation log file

mkdir ~/ldap_install.log 
logfile='~/ldap_install.log'

# install the required packages
yum install -y\
openldap \
openldap-clients \
openldap-servers \
migrationtools \
nfs-utils \
nss_pam_ldap \
autofs > $logfile 2>&1

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
echo -n "Enter ldap root passwd: " > $logfile 2>&1
read passwd 

# Check if the user as entered a passwd
if ($passwd <= 3);
  then
    echo "Enter ldap root passwd: "
  else
    rootpw = $(slappasswd -s $passwd -n)
    echo 'rootpw:' $rootpw > /etc/openldap/passwd
fi > $logfile 2>&1

## Generate a x509 certificate

# Create the public and private cert
openssl req \
-new \
-x509 \
-nodes \
-out /etc/openldap/certs/cert.pem \
-keyout /etc/openldap/certs/priv.pem \
-days 365 > $logfile 2>&1

# Secure the content of the /etc/openldap/certs directory
ldapcert='/etc/openldap/certs'
chown ldap:ldap $ldapcert/* > $logfile 2>&1
chmod 600 $ldapcert/priv.pem > $logfile 2>&1

# Prepare the LDAP database
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG > $logfile 2>&1

# Generate database files
slaptest > $logfile 2>&1

# Change LDAP database ownership:
chown ldap:ldap /var/lib/ldap/* > $logfile 2>&1

# enable and State slapd 
systemctl enable slapd > $logfile 2>&1
systemctl start slapd > $logfile 2>&1

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
ldapadd \
-Y EXTERNAL \
-H ldapi:/// \
-D "cn=config" \
-f /etc/openldap/schema/cosine.ldif > $logfile 2>&1

#* add the nis schemas
ldapadd \
-Y EXTERNAL \
-H ldapi:/// \
-D "cn=config" \
-f /etc/openldap/schema/nis.ldif > $logfile 2>&1

# create the /etc/openldap/changes.ldif

touch /etc/openldap/changes.ldif > logfile 2>&1

ed -s /etc/openldap/changes.ldif << 'EOF'
$a
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=bkln,dc=com

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,dc=bkln,dc=com

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
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=bkln,dc=com" read by * none
.
w
EOF

# Send the new configuration to the slapd server:

ldapmodify \
-Y EXTERNAL \
-H ldapi:/// \
-f /etc/openldap/changes.ldif > $logfile 2>&1

# Create the /etc/openldap/base.ldif
touch /etc/openldap/base.ldif > $logfile 2>&1

ed -s /etc/openldap/base.ldif << 'EOF'
$a
dn: dc=bkln,dc=com
dc: bkln
objectClass: top
objectClass: domain

dn: ou=People,dc=bkln,dc=com
ou: People
objectClass: top
objectClass: organizationalUnit

dn: ou=Group,dc=bkln,dc=com
ou: Group
objectClass: top
objectClass: organizationalUnit
.
w
EOF

# Build the structure of the directory service:
ldapadd \
-x \
-w redhat \
-D cn=Manager,dc=bkln,dc=com \
-f /etc/openldap/base.ldif > $logfile 2>&1

# Create a guest user directory
mkdir /home/guests > $logfile 2>&1

# Create home directory on NFS server
cp /etc/skel/.[a-z]* /home/guests/ > $logfile 2>&1
chown -R ldap:ldap /home/guests/ > $logfile 2>&1

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
useradd -d /home/guests/ldapuser01 ldapuser01 > $logfile 2>&1
useradd -d /home/guests/ldapuser02 ldapuser02 > $logfile 2>&1

# Create user passwd
echo 'iq156sr7' | passwd ldapuser01 --stdin > $logfile 2>&1
echo 'iq156sr7' | passwd ldapuser02 --stdin > $logfile 2>&1

# Edit the migrate_common.ph file

#* migrate_common file
migrate_common='/usr/share/migrationtools/migrate_common'

#* $DEFAULT_MAIL_DOMAIN = "example.com";
sed -i 's/$DEFAULT_MAIL_DOMAIN =.*/$DEFAULT_MAIL_DOMAIN = "bkln.com";/' $migrate_common > $logfile 2>&1

#* $DEFAULT_BASE = "dc=example,dc=com";
sed -i 's/\$DEFAULT_BASE =.*/\$DEFAULT_BASE = "dc=example,dc=com";/' $migrate_common > $logfile 2>&1

## Create the current users in the directory service:

# import user accounts

#* create ldap user config file
grep ":10[0-9][0-9]" /etc/passwd > /etc/openldap/localpasswd.txt > $logfile 2>&1
/usr/share/migrationtools/migrate_passwd.pl /etc/opendldap/localpasswd.txt > /etc/openldap/users.ldif > $logfile 2>&1

#* add users.ldif to LDAP
ldapadd \
-x \
-w $rootpw \
-D cn=Manager,dc=bkln,dc=com \
-f /etc/openldap/users.ldif > $logfile 2>&1

# import group accounts

#* create ldap group config file
grep ":10[0-9][0-9]" /etc/group > /etc/openldap/localgroups.txt > $logfile 2>&1
/usr/share/migrationtools/migrate_group.pl /etc/group > /etc/openldap/groups.ldif > $logfile 2>&1

#* add group.ldif to LDAP
ldapadd \
-x \
-w $rootpw \
-D cn=Manager,dc=bkln,dc=com \
-f /etc/openldap/groups.ldif > $logfile 2>&1

<<'END'
Configure the LDAP server to use autofs
- Create Auto master ldap
- Create Auto Home in ldap
- Create misc in ldap
END

## Configure the LDAP server to use autofs

# Create Auto master ldap
touch /etc/openldap/auto.master.ldif

ed -s /etc/openldap/auto.master.ldif << 'EOF'
$a
dn: ou=auto.master,dc=bkln,dc=com
objectClass: top
objectClass: automountMap
ou: auto.master

dn: cn=/home,ou=auto.master,dc=bkln,dc=com
objectClass: automount
automountInformation: ldap:ou=auto.home,dc=bkln,dc=com
cn: /home

dn: cn=/share,ou=auto.master,dc=bkln,dc=com
objectClass: automount
automountInformation: ldap:ou=auto.misc,dc=bkln,dc=com
cn: /share
.
w
EOF

#* Add auto.master.ldif to LDAP server
ldapadd \
-x \
-w $rootpw \
-D cn=Manager,dc=bkln,dc=com \
-f /etc/openldap/auto.master.ldif > $logfile 2>&1
# Create Auto Home in ldap

# Create misc in ldap
touch /etc/openldap/auto.misc.ldif

ed -s /etc/openldap/auto.misc.ldif << 'EOF'
$a
dn: ou=auto.misc,dc=bkln,dc=com
objectClass: top
objectClass: automountMap
ou: auto.misc
.
w
EOF

#* Add auto.misc.ldif to LDAP server
ldapadd \
-x \
-w $rootpw \
-D cn=Manager,dc=bkln,dc=com \
-f /etc/openldap/auto.misc.ldif > $logfile 2>&1

<<'END'
Configure NFS Server
- Edit /etc/exports
- Start and enable nfs service
END

## Configure NFS Server

# Edit /etc/exports

echo '/home/guests 192.168.10.1/24(rw)' > /etc/exports > $logfile 2>&1

# Start and enable nfs service
service nfs start > $logfile 2>&1

<<'END'
Firewall Configuration
- Add a ldap service to the firewall
- Add a nfs service to the firewall
END

## Add a ldap service to the firewall

# add ldap serivce
firewall-cmd --permanent --add-service=ldap > $logfile 2>&1

# add nfs service
firewall-cmd --permanent --add-service=nfs > $logfile 2>&1

# reload firewall
firewall-cmd --reload > $logfile 2>&1
