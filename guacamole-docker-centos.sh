#!/bin/bash

# Check if user is root or sudo
if ! [ $(id -u) = 0 ]; then echo "Please run this script as sudo or root"; exit 1 ; fi

# Version number of Guacamole to install
GUACVERSION="1.4.0"

# Initialize variable values
installTOTP=""
installLDAP=""

# This is where we'll store persistent data for guacamole
INSTALLFOLDER="/opt/guacamole"

# This is where we'll store persistent data for mysql
MYSQLDATAFOLDER="/opt/mysql"

# Make folders!
mkdir -p ${INSTALLFOLDER}/install_files
mkdir ${INSTALLFOLDER}/extensions
mkdir ${MYSQLDATAFOLDER}

cd ${INSTALLFOLDER}/install_files

# Get script arguments for non-interactive mode
while [ "$1" != "" ]; do
    case $1 in
        -m | --mysqlpwd )
            shift
            mysqlpwd="$1"
            ;;
        -g | --guacpwd )
            shift
            guacpwd="$1"
            ;;
        -t | --totp )
            installTOTP=true
    esac
    shift
done

# Get MySQL root password and Guacamole User password
if [ -n "$mysqlpwd" ] && [ -n "$guacpwd" ]; then
        mysqlrootpassword=$mysqlpwd
        guacdbuserpassword=$guacpwd
else
    echo
    while true
    do
        read -s -p "Enter a MySQL ROOT Password: " mysqlrootpassword
        echo
        read -s -p "Confirm MySQL ROOT Password: " password2
        echo
        [ "$mysqlrootpassword" = "$password2" ] && break
        echo "Passwords don't match. Please try again."
        echo
    done
    echo
    while true
    do
        read -s -p "Enter a Guacamole User Database Password: " guacdbuserpassword
        echo
        read -s -p "Confirm Guacamole User Database Password: " password2
        echo
        [ "$guacdbuserpassword" = "$password2" ] && break
        echo "Passwords don't match. Please try again."
        echo
    done
    echo
fi

if [[ -z "${installTOTP}" ]]; then
    # Prompt the user if they would like to install TOTP MFA, default of no
    echo -e -n "${CYAN}MFA: Would you like to install TOTP? (y/N): ${NC}"
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        installTOTP=true
    else
        installTOTP=false
    fi
fi

if [[ -z "${installLDAP}" ]]; then
    # Prompt the user if they would like to configure LDAP authentication in addition to MySQL, default of no
    echo -e -n "${CYAN}MFA: Would you like to configure LDAP authentication in addition to MySQL? (y/N): ${NC}"
    read LDAP_PROMPT
    if [[ ${LDAP_PROMPT} =~ ^[Yy]$ ]]; then
        installLDAP=true
        read -p "Enter LDAP host IP or FQDN: " LDAP_URL_VAL
        echo
        read -p "Enter LDAP port: " LDAP_PORT_VAL
        echo
        read -p "Select LDAP encryption method ( none | ssl | starttls ): " LDAP_ENC_VAL
        echo
        read -p "Enter LDAP user base DN: " LDAP_USER_BASE_DN_VAL
        echo
        read -p "Enter LDAP search bind DN: " LDAP_SEARCH_BIND_DN_VAL
        echo
        read -s -p "Enter LDAP search bind password: " LDAP_SEARCH_BIND_PASSWORD_VAL
        echo
    else
        installLDAP=false
    fi
fi


# Update and install wget if it's missing
yum -y update
yum -y install wget

# Check if mysql client already installed
if [ -x "$(command -v mysql)" ]; then
    echo "mysql detected!"
else
    # Install mysql-client
    yum -y install mysql
    if [ $? -ne 0 ]; then
        echo "Failed to install prerequisites: mysql"
        echo "Try manually isntalling this prerequisite and try again"
        exit
    fi
fi

# Check if docker already installed
if [ -x "$(command -v docker)" ]; then
    echo "docker detected!"
else
    echo "Installing docker"
    # Try to install docker from the official repo
    yum install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum -y install docker-ce docker-ce-cli containerd.io
    if [ $? -ne 0 ]; then
        echo "Failed to install docker via official repo"
        echo "Trying to install docker from https://get.docker.com"
        wget -O get-docker.sh https://get.docker.com
        chmod +x ./get-docker.sh
        ./get-docker.sh
        if [ $? -ne 0 ]; then
            echo "Failed to install docker from https://get.docker.com"
            exit
        fi
    fi
    systemctl enable docker
    systemctl start docker
fi

# Set SERVER to be the preferred download server from the Apache CDN
SERVER="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUACVERSION}"

# Download Guacamole authentication extensions
wget -O guacamole-auth-jdbc-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-jdbc-${GUACVERSION}.tar.gz
if [ $? -ne 0 ]; then
    echo "Failed to download guacamole-auth-jdbc-${GUACVERSION}.tar.gz"
    echo "${SERVER}/binary/guacamole-auth-jdbc-${GUACVERSION}.tar.gz"
    exit
fi

tar -xzf guacamole-auth-jdbc-${GUACVERSION}.tar.gz

# Download and install TOTP
if [ "${installTOTP}" = true ]; then
    wget -q --show-progress -O guacamole-auth-totp-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-totp-${GUACVERSION}.tar.gz
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to download guacamole-auth-totp-${GUACVERSION}.tar.gz" 1>&2
        echo -e "${SERVER}/binary/guacamole-auth-totp-${GUACVERSION}.tar.gz"
        exit 1
    else
        echo -e "${GREEN}Downloaded guacamole-auth-totp-${GUACVERSION}.tar.gz${NC}"
        tar -xzf guacamole-auth-totp-${GUACVERSION}.tar.gz
        echo -e "${BLUE}Moving guacamole-auth-totp-${GUACVERSION}.jar (${INSTALLFOLDER}/extensions/)...${NC}"
        cp -f guacamole-auth-totp-${GUACVERSION}/guacamole-auth-totp-${GUACVERSION}.jar ${INSTALLFOLDER}/extensions/
        echo
    fi
fi

# Download and install LDAP
if [ "${installLDAP}" = true ]; then
    wget -q --show-progress -O guacamole-auth-ldap-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-ldap-${GUACVERSION}.tar.gz
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to download guacamole-auth-ldap-${GUACVERSION}.tar.gz" 1>&2
        echo -e "${SERVER}/binary/guacamole-auth-ldap-${GUACVERSION}.tar.gz"
        exit 1
    else
        echo -e "${GREEN}Downloaded guacamole-auth-ldap-${GUACVERSION}.tar.gz${NC}"
        tar -xzf guacamole-auth-ldap-${GUACVERSION}.tar.gz
        echo -e "${BLUE}Moving guacamole-auth-ldap-${GUACVERSION}.jar (${INSTALLFOLDER}/extensions/)...${NC}"
        cp -f guacamole-auth-ldap-${GUACVERSION}/guacamole-auth-ldap-${GUACVERSION}.jar ${INSTALLFOLDER}/extensions/
        echo
    fi
fi

# Start MySQL
docker run --restart=always --detach --name=mysql -v ${MYSQLDATAFOLDER}:/var/lib/mysql --env="MYSQL_ROOT_PASSWORD=$mysqlrootpassword" --publish 3306:3306 healthcheck/mysql --default-authentication-plugin=mysql_native_password

# Wait for the MySQL Health Check equal "healthy"
echo "Waiting for MySQL to be healthy"
until [ "$(/usr/bin/docker inspect -f {{.State.Health.Status}} mysql)" == "healthy" ]; do
    sleep 0.1;
done;

# Create the Guacamole database and the user account
# SQL Code
SQLCODE="
create database guacamole_db;
create user 'guacamole_user'@'%' identified by '$guacdbuserpassword';
GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'%';
flush privileges;"

# Execute SQL Code
echo $SQLCODE | mysql -h 127.0.0.1 -P 3306 -u root -p$mysqlrootpassword

cat guacamole-auth-jdbc-${GUACVERSION}/mysql/schema/*.sql | mysql -u root -p$mysqlrootpassword -h 127.0.0.1 -P 3306 guacamole_db

docker run --restart=always --name guacd --detach guacamole/guacd:${GUACVERSION}

if [[ "${installLDAP}" = false ]]; then
    docker run --restart=always --name guacamole --detach --link mysql:mysql --link guacd:guacd -v ${INSTALLFOLDER}:/etc/guacamole -e MYSQL_HOSTNAME=127.0.0.1 -e MYSQL_DATABASE=guacamole_db -e MYSQL_USER=guacamole_user -e MYSQL_PASSWORD=$guacdbuserpassword -e GUACAMOLE_HOME=/etc/guacamole -p 8080:8080 guacamole/guacamole:${GUACVERSION}
else
    docker run --restart=always --name guacamole --detach --link mysql:mysql --link guacd:guacd -v ${INSTALLFOLDER}:/etc/guacamole -e MYSQL_HOSTNAME=127.0.0.1 -e MYSQL_DATABASE=guacamole_db -e MYSQL_USER=guacamole_user -e MYSQL_PASSWORD=$guacdbuserpassword -e GUACAMOLE_HOME=/etc/guacamole -e LDAP_URL=${LDAP_URL_VAL} -e LDAP_PORT=${LDAP_PORT_VAL} -e LDAP_ENCRYPTION_METHOD=${LDAP_ENC_VAL} -e LDAP_USER_BASE_DN=${LDAP_USER_BASE_DN_VAL} -e LDAP_SEARCH_BIND_DN=${LDAP_SEARCH_BIND_DN_VAL} -e LDAP_SEARCH_BIND_PASSWORD=${LDAP_SEARCH_BIND_PASSWORD_VAL} -p 8080:8080 guacamole/guacamole:${GUACVERSION}

# Done
echo
echo -e "Installation Complete\n- Visit: http://localhost:8080/guacamole/\n- Default login (username/password): guacadmin/guacadmin\n***Be sure to change the password***."
