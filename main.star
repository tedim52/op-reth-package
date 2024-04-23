prometheus = import_module("github.com/kurtosis-tech/prometheus-package/main.star")
grafana = import_module("github.com/kurtosis-tech/grafana-package/main.star")


def run(
    plan, 
    l1_rpc_url="https://eth-mainnet.g.alchemy.com/jsonrpc/demo", 
    chain="base",
    network="base-mainnet",
    sequencer_url="https://mainnet-sequencer.base.org",
):
    """Runs OP Stack with Reth using configuration from this guide: https://paradigmxyz.github.io/reth/run/optimism.html

    Args:
        l1_rpc_url(string): An archival L1 node, synced to the settlement layer of the OP Stack chain you want to sync (e.g. reth, geth, besu, nethermind, etc.)
        chain(string): Chain that op-reth will start. Defaults to base
        network(string): Name network that op node will connect to. Defaults to base-mainnet
        sequencer_url(string): The sequencer endpoint to connect to. Transactions sent to the op-reth EL are forwarded to this sequencer endpoint for inclusion, as sequencer is the entity that builds blocks on OP Stack chains. Defaults to https://mainnet-sequencer.base.org
    """
    # use same jwtsecret from ethereum-package: https://github.com/kurtosis-tech/ethereum-package/blob/9139f4b4c77bc43477740972512171d7f28bfa84/static_files/jwt/jwtsecret
    jwt_file = plan.upload_files(
        src="./jwtsecret",
        name="jwt_file"
    )

    # start op-reth
    el_rpc_port_num = 9551
    el_metrics_port_num = 9001
    op_reth_cmd_list = [
        "op-reth",
        "node",
        "--chain {0}".format(chain),
        "--rollup.sequencer-http {0}".format(sequencer_url), 
        "--http",
        "--ws",
        "--authrpc.port {0}".format(el_rpc_port_num),
        "--authrpc.jwtsecret /jwt/jwtsecret", 
        "--metrics 127.0.0.1:{0}".format(el_metrics_port_num)
    ]
    reth_node = plan.add_service(
        name="op-reth",
        config=ServiceConfig(
            image=ImageBuildSpec(
                image_name="op-reth:dev",
                build_context_dir="./reth",
            ),
            entrypoint=["/bin/sh", "-c"],
            cmd=[" ".join(op_reth_cmd_list)],
            ports={ 
                "rpc": PortSpec(
                    number=el_rpc_port_num,
                    transport_protocol="TCP",
                    application_protocol="http",
                ),
                "metrics": PortSpec(
                    number=el_metrics_port_num,
                    transport_protocol="TCP",
                    application_protocol="http",
                )
            },
            files={
                "/jwt/jwtsecret": jwt_file
            }
        )
    )
    l2_rpc_url = "http://{0}:{1}".format(reth_node.hostname, reth_node.ports["rpc"].number)
    reth_metrics_endpoint = "http://{0}:{1}".format(reth_node.hostname, reth_node.ports["metrics"].number)
    
    # start op node
    cl_rpc_port_num = 7000
    op_node_cmd_list = [
        "op-node",
        "--network=\"{0}\"".format(network),
        "--l1={0}".format(l1_rpc_url), 
        "--l2={0}".format(l2_rpc_url), 
        "--l2.jwt-secret=/jwt/jwtsecret", 
        "--rpc.addr=0.0.0.0",
        "--rpc.port={0}".format(cl_rpc_port_num),
        "--l1.trustrp",
    ]
    plan.add_service(
        name="op-node",
        config=ServiceConfig(
            image="us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:08f3dbed90faccb36135fc4bd1d40bfa8ed4066f",
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
                "/jwt/jwtsecret": jwt_file,
            }
        ),
    )
    
    # start prom and grafana with dashboards from https://github.com/paradigmxyz/reth/blob/main/etc/grafana/dashboards/overview.json
    prometheus_url = prometheus.run(plan, metrics_jobs=[{"Name": "op-reth-metrics", "Endpoint": reth_metrics_endpoint }])
    grafana.run(plan, prometheus_url, "github.com/paradigmxyz/reth/etc/grafana/dashboards")


