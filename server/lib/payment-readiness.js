'use strict';

function evaluatePaymentReadiness(input) {
  const value = input || {};
  const blockers = [];

  if (value.mode !== 'enforce') blockers.push('payment_mode_not_enforced');
  if (!value.database) blockers.push('payment_database_missing');
  else if (!value.databaseReady) blockers.push('payment_database_not_ready');
  if (!value.keyringReady) blockers.push('payment_keyring_missing');
  if (!value.provider) blockers.push('payment_provider_missing');
  else if (value.providerReady !== true) blockers.push('payment_provider_not_ready');
  if (value.amlEnabled !== true) blockers.push('aml_enforcement_disabled');
  else if (value.amlHealthy !== true) blockers.push('aml_engine_unhealthy');

  const providerBlockers = value.provider && typeof value.provider.readiness === 'function'
    ? value.provider.readiness().blockers
    : [];
  for (const code of (Array.isArray(providerBlockers) ? providerBlockers : [])) {
    if (!blockers.includes(code)) blockers.push(code);
  }

  return {
    ready: blockers.length === 0,
    blockers
  };
}

module.exports = { evaluatePaymentReadiness };
