#!/usr/bin/env bash

<< 'END'
Author: Reginald Sands
Purpose: To install both the OpenLDAP services as well as user automount
END

<< 'END'
Step 1: Installation
- Install the required packages
END

# Install the required packages
yum install -y \
openldap \
openldap-clients \
openldap-servers \
migrationtools

<< 'END'
Step 2: config file creation
- Create the /etc/openldap/passwd file
- Create Certs to add to /etc/openldap/cert
	- change /etc/openldap/cert permissions
- Prepare LDAP database
	- Generate database files
	- Change LDAP database ownership
	- Enable and Start slapd service
	- Add the cosine schemas
	- Add the nis schemas
- Create the /etc/openldap/changes.ldif file
	- Create the /etc/openldap/config directory
	- Send changes.ldif to the slapd servers
- Create the /etc/openldap/certinfo.ldif file
	- Send certinfo.ldif to the slapd servers
- Create the /etc/openldap/base.ldif file
	- Build the structure of the directory services

END

# Create the /etc/openldap/passwd file
slappasswd -s redhat -n > /etc/openldap/passwd

# Create Certs to add to /etc/openldap/cert
openssl req \
-new \
-x509 \
-nodes \
-out /etc/openldap/certs/cert.pem \
-keyout /etc/openldap/certs/priv.pem \
-days 365

#* change /etc/openldap/cert permissions
chown \
-R \
ldap:ldap \
/etc/openldap/certs

chmod \
600 \
/etc/openldap/certs/priv.pem
# Prepare LDAP database
cp \
/usr/share/openldap-servers/DB_CONFIG.example \
/var/lib/ldap/DB_CONFIG

#* Generate database files
slaptest
#* Change LDAP database ownership
chown \
-R \
ldap:ldap \
/var/lib/ldap/

#* Enable and start the slapd service
systemctl \
enable \
slapd

systemctl \
start \
slapd

#* Add the cosine schemas
ldapadd \
-Y EXTERNAL \
-H ldapi:/// \
-D "cn=config" \
-f /etc/openldap/schema/cosine.ldif

#* Add the nis schemas
ldapadd \
-Y EXTERNAL \
-H ldapi:/// \
-D "cn=config" \
-f /etc/openldap/schema/nis.ldif

# Create the /etc/openldap/changes.ldif file
mkdir /etc/openldap/config
touch /etc/openldap/config/changes.ldif
ed -s /etc/openldap/config/changes.ldif << 'EOF'
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
olcRootPW: {SSHA}l8A+0c+lRcymtWuIFbbc3EJ1PRZz9mGg

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

#* Send changes.ldif to the slapd servers
ldapmodify \
-Y EXTERNAL \
-H ldapi:/// \
-f /etc/openldap/config/changes.ldif

# Create the /etc/opendldap/config/certinfo.ldif
touch /etc/openldap/config/certinfo.ldif
ed -s /etc/openldap/config/certinfo.ldif << 'EOF'
$a
dn: cn=config
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/cert.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/priv.pem
.
w
EOF

#* Send certinfo.ldif to the slapd servers
ldapmodify \
-Y EXTERNAL \
-H ldapi:/// \
-f /etc/openldap/config/certinfo.ldif

# Create the /etc/openldap/base.ldif file
touch /etc/openldap/config/base.ldif
ed -s /etc/openldap/config/base.ldif << 'EOF'
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

#* Build the structure of the directory services
ldapadd \
-x \
-w redhat \
-D cn=Manager,dc=bkln,dc=com \
-f /etc/openldap/config/base.ldif

<< 'END'
Step 3: User Account Migration
- Create two users for testing
	- Create ldap user directory
	- Create test users
- edit the /usr/share/migrationtools/migrate_common.ph
- Create the current users in the directory
	- Create users config file
	- Create groups config file

END

# Create two users for testing

#* Create ldap user directory
mkdir /home/guests

#* Create test users
useradd -d /home/guests/ldapuser01 ldapuser01
echo 'redhat' | passwd ldapuser01 --stdin

useradd -d /home/guests/ldapuser02 ldapuser02
echo 'redhat' | passwd ldapuser02 --stdin

# edit the /usr/share/migrationtools/migrate_common.ph
cp /usr/share/migrationtools/migrate_common.ph /usr/share/migrationtools/migrate_common.ph.orig

sed -i '0,/^$DEFAULT_MAIL_DOMAIN.*;/s//$DEFAULT_MAIL_DOMAIN = "bkln.com";/' /usr/share/migrationtools/migrate_common.ph

sed -i '0,/^$DEFAULT_BASE.*;/s//$DEFAULT_BASE = "dc=bkln,dc=com";/' /usr/share/migrationtools/migrate_common.ph

# Create the current users in the directory

#* Create users config file
grep ":10[0-9][0-9]" /etc/passwd > /etc/openldap/passwd

perl /usr/share/migrationtools/migrate_passwd.pl /etc/openldap/passwd /etc/openldap/config/users.ldif

ldapadd \
-x \
-w redhat \
-D cn=Manager,dc=bkln,dc=com \
-f /etc/openldap/config/users.ldif

#* Create groups config file
grep ":10[0-9][0-9]" /etc/group > /etc/openldap/group

perl /usr/share/migrationtools/migrate_group.pl /etc/openldap/group /etc/openldap/config/groups.ldif

ldapadd \
-x \
-w redhat \
-D cn=Manager,dc=bkln,dc=com \
-f /etc/openldap/config/groups.ldif


<< 'END'
Step 4: Firewall Configuration
- Add a new service to the firewall (ldap: port tcp 389)
- Reload  the firewall configuration
- Edit the /etc/rsyslog.conf file and add the following line:
- Restart the rsyslog service
END

# Add a new service to the firewall (ldap: port tcp 389)
firewall-cmd \
--permanent \
--add-service=ldap

# Reload  the firewall configuration
firewall-cmd \
--reload

# Edit the /etc/rsyslog.conf file and add the following line
ed -s /etc/rsyslog.conf << 'EOF'
$a
local4.* /var/log/ldap.log
.
w
EOF

# Restart the rsyslog service
systemctl \
restart \
rsyslog

<< 'END'
Step 5: NFS Server Configuration\
- Install the file-server package group
- Add a new service to the firewall
  - add nfs service
  - add mountd service
  - add rpc-bind service
  - firewall reload
- Enable and start daemons
  - enable and start rpcbind
  - enable and start nfs-server
END

# Install the file-server package group
yum groupinstall -y \
file-server

# Add a new service to the firewall
#* add nfs service
firewall-cmd --permanent --add-service=nfs

#* add mountd service
firewall-cmd --permanent --add-service=mountd

#* add rpc-bind service
firewall-cmd --permanent --add-service=rpc-bind

#* firewall reload
firewall-cmd --reload

# Enable and Start daemons
#* enable and start rpcbind
systemctl enable rpcbind && systemctl start rpcbind

#* enable and start nfs-server
systemctl enable nfs-server && systemctl start nfs-server

<< 'END'
Step 6: SELinux Configuration
- Assign the correct SELinux contexts to the new directories:
  - install setroubleshoot-server
  - set the fcontext for /home/guests
  - restore context of /home/guests
- Assign the correct setting to the SELinux booleans:
  - set nfs_export_all_rw boolean to on
  - set nfs_export_all_ro boolean to on
  - set use_nfs_home_dirs boolean to on
END

# Assign the correct SELinux contexts to the new directories:
#* install setroubleshoot-server
yum install -y \
setroubleshoot-server

#* set the fcontext for /home/guests
semanage fcontext -a -t public_content_rw_t "/home/guests(/.*)?"

#* restore context of /home/guests
restorecon -R /home/guests

# Assign the correct setting to the SELinux booleans:
#* set nfs_export_all_rw boolean to on
setsebool -P nfs_export_all_rw on

#* set nfs_export_all_ro boolean to on
setsebool -P nfs_export_all_ro on

#* set use_nfs_home_dirs boolean to on
setsebool -P use_nfs_home_dirs on

<< 'END'
Step 7: NFS configure directories to share
- Edit the /etc/exports file
- Export the directories
- restart nfs-server
END

# Edit the /etc/exports file
echo "/home/guests *(rw,no_root_squash)" >> /etc/exports

# Export the directories
exportfs -avr

# restart nfs-server
systemctl restart nfs-server 


