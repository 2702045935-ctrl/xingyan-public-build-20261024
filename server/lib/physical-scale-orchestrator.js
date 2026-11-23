'use strict';

const REQUIRED = [
  'prepareNode',
  'seedReplica',
  'waitReplicaCaughtUp',
  'shadowRead',
  'freezeOwner',
  'acquireLease',
  'switchRoutes',
  'switchGateway',
  'unfreezeOwner',
  'verifyOwner',
  'switchReplication',
  'soak'
];

async function attempt(operation, retries) {
  let lastError = null;
  const count = Math.max(1, Number(retries) || 1);
  for (let index = 0; index < count; index += 1) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (index + 1 < count) {
        await new Promise((resolve) => setTimeout(resolve, 80 * (index + 1)));
      }
    }
  }
  throw lastError;
}

async function executePhysicalScale(plan, adapters, options) {
  const opts = options || {};
  const reportStep = typeof opts.onStep === 'function'
    ? opts.onStep
    : () => {};
  const events = [];
  const record = (event) => {
    const row = Object.assign({ at: new Date().toISOString() }, event);
    events.push(row);
    reportStep(row);
    return row;
  };
  if (!plan || plan.ok !== true) {
    return {
      version: 1,
      ok: false,
      reason: 'scale-plan-invalid',
      failures: (plan && plan.failures) || [],
      events
    };
  }
  for (const name of REQUIRED) {
    if (!adapters || typeof adapters[name] !== 'function') {
      return {
        version: 1,
        ok: false,
        reason: 'missing-adapter:' + name,
        events
      };
    }
  }

  const retries = Math.max(1, Math.min(5, Number(opts.retries) || 2));
  const prepareRows = plan.stages.filter((row) => row.stage === 'prepare-node');
  for (const row of prepareRows) {
    record({ phase: 'prepare-node', cellId: row.cellId });
    await attempt(() => adapters.prepareNode(row), retries);
  }

  for (const move of plan.moves) {
    let frozen = false;
    let leaseAcquired = false;
    let routesSwitched = false;
    let gatewaySwitched = false;
    let replicationSwitched = false;
    try {
      record({ phase: 'seed-replica', shard: move.shard, cellId: move.toCellId });
      await attempt(() => adapters.seedReplica(move), retries);

      record({ phase: 'catch-up', shard: move.shard });
      await attempt(() => adapters.waitReplicaCaughtUp(move), retries);

      record({ phase: 'shadow-read', shard: move.shard });
      await attempt(() => adapters.shadowRead(move), retries);

      record({ phase: 'freeze-old-owner', shard: move.shard });
      await attempt(() => adapters.freezeOwner(move), retries);
      frozen = true;

      record({ phase: 'acquire-target-lease', shard: move.shard });
      await attempt(() => adapters.acquireLease(move), retries);
      leaseAcquired = true;

      record({ phase: 'switch-routes', shard: move.shard });
      await attempt(() => adapters.switchRoutes(move), retries);
      routesSwitched = true;

      record({ phase: 'switch-gateway', shard: move.shard });
      await attempt(() => adapters.switchGateway(move), retries);
      gatewaySwitched = true;

      record({ phase: 'unfreeze-target-owner', shard: move.shard });
      await attempt(() => adapters.unfreezeOwner(move), retries);

      record({ phase: 'verify-owner', shard: move.shard });
      await attempt(() => adapters.verifyOwner(move), retries);

      record({ phase: 'switch-replication', shard: move.shard });
      await attempt(() => adapters.switchReplication(move), retries);
      replicationSwitched = true;
      record({ phase: 'cutover-complete', shard: move.shard });
    } catch (error) {
      record({
        phase: 'cutover-failed',
        shard: move.shard,
        reason: String(error && error.message || error),
        gatewaySwitched,
        routesSwitched,
        leaseAcquired,
        frozen,
        replicationSwitched
      });
      try {
        if (replicationSwitched) {
          await adapters.switchReplication(Object.assign({}, move, {
            rollback: true,
            toCellId: move.fromCellId,
            toHost: move.fromHost
          }));
        }
        if (routesSwitched) {
          await adapters.switchRoutes(Object.assign({}, move, {
            rollback: true,
            toCellId: move.fromCellId,
            toHost: move.fromHost
          }));
        }
        if (gatewaySwitched || routesSwitched) {
          await adapters.switchGateway(Object.assign({}, move, {
            rollback: true,
            toCellId: move.fromCellId,
            toHost: move.fromHost
          }));
        }
        if (leaseAcquired) {
          await adapters.acquireLease(Object.assign({}, move, {
            rollback: true,
            toCellId: move.fromCellId,
            toHost: move.fromHost
          }));
        }
        if (frozen) {
          await adapters.unfreezeOwner(Object.assign({}, move, {
            rollback: true,
            toCellId: move.fromCellId,
            toHost: move.fromHost
          }));
        }
        await adapters.verifyOwner(Object.assign({}, move, {
          rollback: true,
          toCellId: move.fromCellId,
          toHost: move.fromHost
        }));
        record({ phase: 'rollback-complete', shard: move.shard });
      } catch (rollbackError) {
        record({
          phase: 'rollback-failed',
          shard: move.shard,
          reason: String(rollbackError && rollbackError.message || rollbackError)
        });
        return {
          version: 1,
          ok: false,
          reason: 'rollback-failed',
          failedShard: move.shard,
          events
        };
      }
      return {
        version: 1,
        ok: false,
        reason: 'cutover-failed',
        failedShard: move.shard,
        events
      };
    }
  }

  record({ phase: 'soak', minutes: plan.stages
    .find((row) => row.stage === 'soak')?.durationMinutes || 30 });
  await adapters.soak(plan);
  record({ phase: 'complete' });
  return {
    version: 1,
    ok: true,
    reason: 'complete',
    sourceCellCount: plan.sourceCellCount,
    targetCellCount: plan.targetCellCount,
    movedShards: plan.moves.length,
    events
  };
}

module.exports = {
  REQUIRED,
  executePhysicalScale
};
