# Zabbix
CloudFormation to Setup Zabbix and/or Grafana Server with ELB and EC2 Servers with Agents Installed

There are several templates that you can launch from the bin directory.  

If you want to launch only a Zabbix server with agent, just run the DeployZabbix.sh script and update the paramsZabbix.json with your parameters.

If you want to launch only a Grafana server, just run the DeployGrafana.sh script and update the paramsGrafana.json with your parameters.

If you want to launch both a Grafana and Zabbix server with the Zabbix plugin and Zabbix dashboards enabled in Grafana, along with pulling data from the Zabbix server. Run the DeployZabbixGrafana.sh and update the paramsZabbixGrafan.json with your parameters.


For full integration with Zabbix and Grafana, please ensure you select AuroraRDSCluster as the DatabaseType.


1.  To deploy, just run DeployXXXXX.sh from the bin directory.
2.  Ensure your AWS creds in your profile are setup correctly.
3.  This template assumes you have a VPC setup with Public and Private subnets.
4.  Update the paramsXXXXX.json to change parameters for your VPC.
5.  ZabbixDatabaseType => LocalMySql or AuroraRDSCluster
    1. LocalMySql option will use local MySql install on Zabbix Server.
    2. AuroraRDSCluster option will create Aurora RDS Cluster.
6. The UserName and Password you choose will be the credentials set for:
    1. Grafana and Zabbix Databases
    2. The default Web Login for Grafana and Zabbix.