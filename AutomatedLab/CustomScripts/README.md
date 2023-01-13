Here are the scripts for building different labs.

All scripts must be executed in an administrative PowerShell.

Most scripts need additional components from the CustomAssets folder.



## Docker_Databases

This lab consists of a Linux VM with CentOS-7 and docker, as well as containers with various database systems.

Currently possible:
* Microsoft SQL Server
* Oracle
* MySQL
* MariaDB (currently only version 10.9)
* PostgreSQL
* PostgreSQL with PostGIS

A test user is also created in each of the database systems and test data is loaded. Code from my GitHub repository https://github.com/andreasjordan/PowerShell-for-DBAs is used for this.

Currently possible:
* StackOverflow's database with the same schema and sample data for all database systems. All information comes from the mentioned GitHub repository.
* Polygons of country boundaries. The data is downloaded directly from https://datahub.io/core/geo-countries.

The script is currently "in progress". Additional wishes and comments are welcome.


## SQLServer_AlwaysOn

This lab is specifically intended for running the SQL Server Always On Availability Groups demos, which are stored here: https://github.com/andreasjordan/demos/tree/master/AlwaysOn

Therefore, the configuration of the lab may only be adjusted if the demo scripts are adjusted at the same time.

The lab consists of five Windows Server 2022 machines, one of which is a domain controller, one server on which the demo scripts are executed and three servers with SQL Server instances.


## Win2022_Oracle

The lab consists of three Windows Server 2022 machines. The Oracle client is installed on one server, and an Oracle server on each of the other two.


## Win2022_SQLServer

The lab consists of a Windows Server 2022 machine with an instance of SQL Server 2019 Express installed.
