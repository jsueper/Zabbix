# Zabbix
CloudFormation to Setup Zabbix Server with ELB and EC2 Servers with Agents Installed

1.  To deploy, just run Deploy.sh from the bin directory.
2.  Ensure your AWS creds in your profile are setup correctly.
3.  This template assumes you have a VPC setup with Public and Private subnets.
4.  Update the params.json to change parameters for your VPC.
5.  ZabbixDatabaseType => LocalMySql or AuroraRDSCluster
    1. LocalMySql option will use local MySql install on Zabbix Server.
    2. AuroraRDSCluster option will create Aurora RDS Cluster.
    3. Test