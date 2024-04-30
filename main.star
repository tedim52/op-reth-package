prometheus = import_module("github.com/kurtosis-tech/prometheus-package/main.star")
grafana = import_module("github.com/kurtosis-tech/grafana-package/main.star")

network_info = {
    "op": {
        "sequencer_url": "https://sepolia-sequencer.optimism.io",
    },
    "base": {
        "sequencer_url": "https://sepolia-sequencer.base.org",
    }
}

def run(
    plan, 
    chain="testnet",
    network="op",
    l1_quicknode_api_key="7ef4ff4201717e799198d57ab4ab548ba37b7191",
):
    """Runs OP Stack with Reth using configuration from this guide: https://paradigmxyz.github.io/reth/run/optimism.html

    Args:
        chain(string): Options are `testnet` or `alphanet`. Testnet will connect op-reth to a testnet. Alphanet will launch a local Reth Alphanet network. Defaults to testnet.
        network(string): If testnet is selected, connect to Base Sepolia or OP Sepolia network. Options are `base` or `op`. Defaults to op.
        l1_quicknode_api_key(string): If testnet is selected, api key to use for Quicknode L1 node. A default is set if not provided.
    """
    if chain != "alphanet" or chain != "testnet":
        fail("enter `testnet` or `alphanet` for chain")
    if network != "op" or network != "base":
        fail("enter `base` or `op` for network")

    sequencer_url = network_info[network]["sequencer_url"]
    l1_rpc_url = "https://hardworking-sparkling-firefly.quiknode.pro/{0}/".format(l1_quicknode_api_key)

    # using same jwtsecret from ethereum-package: https://github.com/kurtosis-tech/ethereum-package/blob/9139f4b4c77bc43477740972512171d7f28bfa84/static_files/jwt/jwtsecret
    jwt_file = plan.upload_files(
        src="./jwtsecret",
        name="jwt_file"
    )

    # start op-reth
    el_authrpc_port_num = 9551
    el_rpc_port_num = 8545
    el_metrics_port_num = 9001
    op_reth_cmd_list = [
        "op-reth",
        "node",
        "--chain {0}".format(chain),
        "--rollup.sequencer-http {0}".format(sequencer_url), 
        "--http",
        "--http.addr=0.0.0.0",
        "--http.port={0}".format(el_rpc_port_num),
        "--http.corsdomain=*",
        # WARNING: The admin info endpoint is enabled which means that users should NOT store private information in Kurtosis nodes!
        "--http.api=admin,net,eth,web3,debug,trace",
        "--ws",
        "--ws.addr=0.0.0.0",
        "--authrpc.port {0}".format(el_authrpc_port_num),
        "--authrpc.addr=0.0.0.0",
        "--authrpc.jwtsecret /jwt/jwtsecret", 
        "--metrics 0.0.0.0:{0}".format(el_metrics_port_num),
    ]
    reth_node = plan.add_service(
        name="op-reth",
        config=ServiceConfig(
            # currently uses custom built image built from reth codebase
            image="tedim52/op-reth:latest", 
            entrypoint=["/bin/sh", "-c"],
            cmd=[" ".join(op_reth_cmd_list)],
            ports={ 
                "authrpc": PortSpec(
                    number=el_authrpc_port_num,
                    transport_protocol="TCP", 
                    application_protocol="http",
                ),
                "rpc": PortSpec(
                    number=el_rpc_port_num,
                    transport_protocol="TCP",
                    application_protocol="http",
                ),
                "metrics": PortSpec(
                    number=el_metrics_port_num,
                    transport_protocol="TCP",                     
                    application_protocol="http",
                ),
                "peering": PortSpec(
                    number=30303,
                    transport_protocol="TCP"
                )
            },
            files={
                "/jwt": jwt_file
            }
        )
    )
    l2_rpc_url = "http://{0}:{1}".format(reth_node.name, reth_node.ports["rpc"].number)
    reth_metrics_endpoint = "{0}:{1}".format(reth_node.ip_address, reth_node.ports["metrics"].number)
    
    # start op node
    cl_rpc_port_num = 7000
    op_node_cmd_list = [
        "op-node",
        "--network=\"{0}\"".format(network),
        "--l1={0}".format(l1_rpc_url), 
        "--l1.beacon={0}".format(l1_rpc_url), # quicknode exposes beacon API via same URL
        "--l2={0}".format(l2_rpc_url), 
        "--l2.jwt-secret=/jwt/jwtsecret", 
        "--rpc.addr=0.0.0.0",
        "--rpc.port={0}".format(cl_rpc_port_num),
        "--l1.trustrpc",
    ]
    plan.add_service(
        name="op-node",
        config=ServiceConfig(
            image="us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.7.3",
            entrypoint=["/bin/sh","-c"],
            cmd=[" ".join(op_node_cmd_list)],
            ports={ 
                "rpc": PortSpec(
                    number=cl_rpc_port_num,
                    transport_protocol="TCP",
                    application_protocol="http",
                )
            },
            files={
                "/jwt": jwt_file,
            }
        ),
    )
    
    # start prom and grafana with dashboards from https://github.com/paradigmxyz/reth/blob/main/etc/grafana/dashboards/overview.json
    prometheus_url = prometheus.run(plan, metrics_jobs=[{"Name": "op-reth-metrics", "Endpoint": reth_metrics_endpoint, "MetricsPath": "/metrics" }], name="prom", min_cpu=0)
    grafana.run(plan, prometheus_url, "github.com/tedim52/op-reth-package/grafana/dashboards")



