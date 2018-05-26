#!/usr/bin/env bash
# Author: Reginald Sands
: <<'END' 
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
<< 'END'

END
# create a root passwd
echo -n "Enter ldap root passwd: "
read passwd
if ($passwd == 0);
  then
    echo "Enter ldap root passwd: "
  else
    rootpw = $(slappasswd -s $passwd -n)
    echo rootpw: $rootpw > /etc/openldap/passwd
fi

# Generate a x509 certificate valid for 365 days
openssl req -new -x509 -nodes -out /etc/openldap/certs/cert.pem \
-keyout /etc/openldap/certs/priv.pem -days 365

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

