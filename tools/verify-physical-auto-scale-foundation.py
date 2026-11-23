#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = (ROOT / "server" / "lib" / "physical-scale-production-adapters.js").read_text(
    encoding="utf-8"
)
RUNTIME = (ROOT / "server" / "lib" / "physical-auto-scale-runtime.js").read_text(
    encoding="utf-8"
)
TARGET = (ROOT / "server" / "lib" / "physical-scale-target.js").read_text(
    encoding="utf-8"
)
ORCHESTRATOR = (ROOT / "server" / "lib" / "physical-scale-orchestrator.js").read_text(
    encoding="utf-8"
)
PROXY = (ROOT / "server" / "tools" / "dual-cell-tls-proxy.js").read_text(
    encoding="utf-8"
)
AGENT = (ROOT / "deploy" / "fleet" / "fleet-node-control.js").read_text(
    encoding="utf-8"
)
REPLICATION = (ROOT / "deploy" / "fleet" / "fleet-replication-sync.js").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
MANAGE = (ROOT / "server" / "public" / "manage.html").read_text(encoding="utf-8")
MAINT = (ROOT / "server" / "public" / "shard-maintenance.html").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("physical auto-scale foundation failed: " + message)


require(
    "createPhysicalScaleProductionAdapters" in ADAPTER
    and "prepareNode" in ADAPTER
    and "waitReplicaCaughtUp" in ADAPTER
    and "write-gateway-routing" in ADAPTER
    and "reload-gateway" in ADAPTER
    and "ownerTargets" in ADAPTER
    and "restart" not in ADAPTER,
    "production adapters must stage routing and use gateway hot reload",
)
require(
    "loadFleetControlPanel" in SERVER
    and "fleetControl: loadFleetControlPanel" in SERVER
    and "物理分片自动扩容控制面" in MANAGE
    and "自动扩容控制面" in MAINT
    and "最近扩容审计" in MANAGE,
    "the operations panel must display live fleet control state and audit",
)
require(
    "writeAtomic" in AGENT
    and "reload-gateway" in AGENT
    and "systemctl', 'kill', '--signal=HUP'" in AGENT
    and "rsync" in AGENT
    and "writeFleetPlan" in AGENT
    and "manifest" in AGENT,
    "remote cell agent must copy, verify and hot-reload without restarting the gateway",
)
require(
    "LOCAL_CELL_ID" in REPLICATION
    and "ownerShards" in REPLICATION
    and "replicaShards" in REPLICATION
    and "planSha256" in REPLICATION
    and "--checksum" in REPLICATION,
    "replication daemon must follow the active fleet owner plan",
)
require(
    "buildExpandedFleetPlan" in TARGET
    and "requireVerifiedFailureDomains: true" in TARGET
    and "deploymentEligible" in TARGET,
    "target planning must deterministically assign one owner per logical shard",
)
require(
    "process.on('SIGHUP'" in PROXY
    and "reloadGatewayRouting" in PROXY
    and "GATEWAY_ROUTING_FILE" in PROXY
    and "applyOwnerRouting(next.ownerPorts, next.ownerTargets)" in PROXY,
    "TLS gateway must atomically reload cross-host owner targets on SIGHUP",
)
rollback = ORCHESTRATOR[ORCHESTRATOR.index("} catch (error) {"):]
require(
    rollback.index("await adapters.switchRoutes(Object.assign({}, move, {")
    < rollback.index("await adapters.switchGateway(Object.assign({}, move, {"),
    "rollback must restore routing before reloading the gateway",
)
require(
    "scale-job-locked" in RUNTIME
    and "fs.openSync(lockFile, 'wx'" in RUNTIME
    and "target-plan-stale" in RUNTIME
    and "fleet metrics are stale" in RUNTIME
    and "execution-disabled" in RUNTIME
    and "promoteOnSuccess" in RUNTIME,
    "runtime must lock, reject stale inputs, stay fail-closed and promote only on success",
)
require(
    (ROOT / "deploy" / "fleet" / "physical-auto-scale.service").exists()
    and (ROOT / "deploy" / "fleet" / "physical-auto-scale.example.json").exists()
    and (ROOT / "deploy" / "fleet" / "physical-replication-sync.service").exists()
    and "ExecReload=/bin/kill -HUP $MAINPID" in (
        ROOT / "deploy" / "dual-cell" / "xingyan-dual-cell-tls-live.service"
    ).read_text(encoding="utf-8"),
    "deployable scheduler and gateway reload units are required",
)
require(
    "node server/test/physical-scale-production-adapters.test.js" in WORKFLOW
    and "node server/test/physical-scale-target.test.js" in WORKFLOW
    and "node server/test/physical-auto-scale-runtime.test.js" in WORKFLOW,
    "production adapters and runtime must run in the iOS gate",
)

print("physical-auto-scale-foundation: passed")
