#!/bin/bash

set -m
set -e

VOLUME_HOME="/var/lib/mysql"
CONF_FILE="/etc/mysql/conf.d/my.cnf"
LOG="/var/log/mysql/error.log"

# Set permission of config file
chmod 644 ${CONF_FILE}
chmod 644 /etc/mysql/conf.d/mysqld_charset.cnf

StartMySQL ()
{
    /usr/bin/mysqld_safe ${EXTRA_OPTS} > /dev/null 2>&1 &
    # Time out in 1 minute
    LOOP_LIMIT=60
    for (( i=0 ; ; i++ )); do
        if [ ${i} -eq ${LOOP_LIMIT} ]; then
            echo "Time out. Error log is shown as below:"
            tail -n 100 ${LOG}
            exit 1
        fi
        echo "=> Waiting for confirmation of MySQL service startup, trying ${i}/${LOOP_LIMIT} ..."
        sleep 1
        mysql -uroot -e "status" > /dev/null 2>&1 && break
    done
}

CreateMySQLUser()
{
    if [ "$MYSQL_PASS" = "**Random**" ]; then
        unset MYSQL_PASS
    fi

    PASS=${MYSQL_PASS:-$(pwgen -s 12 1)}
    _word=$( [ ${MYSQL_PASS} ] && echo "preset" || echo "random" )
    echo "=> Creating MySQL user ${MYSQL_USER} with ${_word} password"

    mysql -uroot -e "CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '$PASS'"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION"
    echo "=> Done!"
    echo "========================================================================"
    echo "You can now connect to this MySQL Server using:"
    echo ""
    echo "    mysql -u$MYSQL_USER -p$PASS -h<host> -P<port>"
    echo ""
    echo "Please remember to change the above password as soon as possible!"
    echo "MySQL user 'root' has no password but only allows local connections"
    echo "========================================================================"
}

OnCreateDB()
{
    if [ "$ON_CREATE_DB" = "**False**" ]; then
        unset ON_CREATE_DB
    else
        echo "Creating MySQL database workspace"
        mysql -uroot -e "CREATE DATABASE IF NOT EXISTS workspace"
        echo "Database created!"
    fi
}

ImportSql()
{
    for FILE in ${STARTUP_SQL}; do
        echo "=> Importing SQL file create.sql"
        if [ "$ON_CREATE_DB" ]; then
            mysql -uroot "workspace" < "create.sql"
        else
            mysql -uroot < "create.sql"
        fi
    done
}

# Main
if [ ${REPLICATION_MASTER} == "**False**" ]; then
    unset REPLICATION_MASTER
fi

if [ ${REPLICATION_SLAVE} == "**False**" ]; then
    unset REPLICATION_SLAVE
fi

# Initialize empty data volume and create MySQL user
if [[ ! -d $VOLUME_HOME/mysql ]]; then
    echo "=> An empty or uninitialized MySQL volume is detected in $VOLUME_HOME"
    echo "=> Installing MySQL ..."
    if [ ! -f /usr/share/mysql/my-default.cnf ] ; then
        cp /etc/mysql/my.cnf /usr/share/mysql/my-default.cnf
    fi
    mysql_install_db || exit 1
    touch /var/lib/mysql/.EMPTY_DB
    echo "=> Done!"
else
    echo "=> Using an existing volume of MySQL"
fi

# Set MySQL REPLICATION - MASTER
if [ -n "${REPLICATION_MASTER}" ]; then
    echo "=> Configuring MySQL replication as master (1/2) ..."
    if [ ! -f /replication_set.1 ]; then
        RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})"
        echo "=> Writting configuration file '${CONF_FILE}' with server-id=${RAND}"
        sed -i "s/^#server-id.*/server-id = ${RAND}/" ${CONF_FILE}
        sed -i "s/^#log-bin.*/log-bin = mysql-bin/" ${CONF_FILE}
        touch /replication_set.1
    else
        echo "=> MySQL replication master already configured, skip"
    fi
fi

# Set MySQL REPLICATION - SLAVE
if [ -n "${REPLICATION_SLAVE}" ]; then
    echo "=> Configuring MySQL replication as slave (1/2) ..."
    if [ -n "${MYSQL_PORT_3306_TCP_ADDR}" ] && [ -n "${MYSQL_PORT_3306_TCP_PORT}" ]; then
        if [ ! -f /replication_set.1 ]; then
            RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})"
            echo "=> Writting configuration file '${CONF_FILE}' with server-id=${RAND}"
            sed -i "s/^#server-id.*/server-id = ${RAND}/" ${CONF_FILE}
            sed -i "s/^#log-bin.*/log-bin = mysql-bin/" ${CONF_FILE}
            touch /replication_set.1
        else
            echo "=> MySQL replication slave already configured, skip"
        fi
    else
        echo "=> Cannot configure slave, please link it to another MySQL container with alias as 'mysql'"
        exit 1
    fi
fi


echo "=> Starting MySQL ..."
StartMySQL
tail -F $LOG &

# Create admin user and pre create database
if [ -f /var/lib/mysql/.EMPTY_DB ]; then
    echo "=> Creating admin user ..."
    CreateMySQLUser
    OnCreateDB
    rm /var/lib/mysql/.EMPTY_DB
fi


# Import Startup SQL
echo "=> Initializing DB"

mysql -u root -e "CREATE TABLE workspace.agent( name varchar(45) DEFAULT NULL,running varchar(45) DEFAULT NULL,ip varchar(145) DEFAULT NULL,id int(11) NOT NULL AUTO_INCREMENT,date varchar(45) DEFAULT NULL,PRIMARY KEY (id) ) ENGINE=InnoDB AUTO_INCREMENT=4414 DEFAULT CHARSET=latin1;"
mysql -u root -e "CREATE TABLE workspace.log(log varchar(200) DEFAULT NULL,id int NOT NULL AUTO_INCREMENT, PRIMARY KEY(id)) ENGINE=InnoDB AUTO_INCREMENT=886 DEFAULT CHARSET=latin1;"
mysql -u root -e "CREATE TABLE workspace.samples(LABEL varchar(100) DEFAULT NULL,RESPONSETIME varchar(45) DEFAULT NULL,MESSAGE varchar(300) DEFAULT NULL,INDIVIDUAL varchar(345) DEFAULT NULL,GENERATION varchar(45) DEFAULT NULL,TESTPLAN varchar(45) DEFAULT NULL ) ENGINE=InnoDB DEFAULT CHARSET=latin1;"
mysql -u root -e "CREATE TABLE workspace.workload (NAME varchar(330) DEFAULT NULL,  RESPONSETIME varchar(30) DEFAULT NULL,  TYPE varchar(300) DEFAULT NULL,  USERS varchar(30) DEFAULT NULL,  ERROR varchar(30) DEFAULT NULL,   FIT varchar(400) DEFAULT NULL,  FUNCTION1 varchar(30) DEFAULT NULL,  FUNCTION2 varchar(30) DEFAULT NULL,  FUNCTION3 varchar(30) DEFAULT NULL,  FUNCTION4 varchar(30) DEFAULT NULL,  FUNCTION5 varchar(30) DEFAULT NULL,  FUNCTION6 varchar(30) DEFAULT NULL,  FUNCTION7 varchar(30) DEFAULT NULL,  FUNCTION8 varchar(30) DEFAULT NULL,  FUNCTION9 varchar(30) DEFAULT NULL,  FUNCTION10 varchar(30) DEFAULT NULL,  TESTPLAN varchar(40) DEFAULT NULL,  GENERATION varchar(45) DEFAULT NULL,  ACTIVE varchar(45) DEFAULT NULL,  id int(11) NOT NULL AUTO_INCREMENT,  PERCENT90 varchar(45) DEFAULT NULL,  PERCENT80 varchar(45) DEFAULT NULL,  PERCENT70 varchar(45) DEFAULT NULL,  TOTALERROR varchar(45) DEFAULT NULL,  SEARCHMETHOD varchar(345) DEFAULT NULL,  USER1 varchar(45) DEFAULT NULL,  USER2 varchar(45) DEFAULT NULL,  USER3 varchar(45) DEFAULT NULL,  USER4 varchar(45) DEFAULT NULL,  USER5 varchar(45) DEFAULT NULL,  USER6 varchar(45) DEFAULT NULL,  USER7 varchar(45) DEFAULT NULL,  USER8 varchar(45) DEFAULT NULL,  USER9 varchar(45) DEFAULT NULL,  USER10 varchar(45) DEFAULT NULL,  MEMORY varchar(45) DEFAULT NULL,  CPUSHARE varchar(45) DEFAULT NULL,  PRIMARY KEY (id)) ENGINE=InnoDB AUTO_INCREMENT=44270 DEFAULT CHARSET=latin1; "






mysql -u root -e  "CREATE TABLE workspace.Q(responsetime varchar(245) DEFAULT NULL,  testplan varchar(245) DEFAULT NULL,  Qvalue float DEFAULT NULL,  id int(11) NOT NULL AUTO_INCREMENT,  state varchar(300) DEFAULT NULL,  PRIMARY KEY (id)) ENGINE=InnoDB AUTO_INCREMENT=34075 DEFAULT CHARSET=latin1;"





mysql -u root -e " CREATE TABLE workspace.Operation (NAME varchar(245) DEFAULT NULL,  testplan varchar(245) DEFAULT NULL,  FUNC integer DEFAULT NULL, NEWFUNC integer DEFAULT NULL, IDOLDWORKLOAD integer DEFAULT NULL,  id int(11) NOT NULL AUTO_INCREMENT,  state varchar(300) DEFAULT NULL,  PRIMARY KEY (id)) ENGINE=InnoDB AUTO_INCREMENT=34075 DEFAULT CHARSET=latin1; "



#ImportSql
#touch /sql_imported



fg