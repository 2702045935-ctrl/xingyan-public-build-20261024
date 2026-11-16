'use strict';

const { verifyRoutePlan } = require('./shard-route-plan');

function normalizeAllowlist(value) {
  const rows = Array.isArray(value)
    ? value
    : value && Array.isArray(value.files)
      ? value.files
      : value && Array.isArray(value.missingUploads)
        ? value.missingUploads
        : [];
  return new Set(rows.map((row) =>
    String(row && typeof row === 'object' ? row.id : row || '')
  ).filter(Boolean));
}

function countOf(report, kind) {
  return Number(report && report.issueCounts && report.issueCounts[kind]) || 0;
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function messageAuditGate(reports, candidate) {
  const rows = Array.isArray(reports)
    ? reports.filter(Boolean)
    : (reports ? [reports] : []);
  const invalidFingerprint = rows.filter((report) =>
    !/^[a-f0-9]{64}$/i.test(String(report && report.fingerprint || ''))
  ).length;
  const messageCount = rows.reduce((sum, report) =>
    sum + (Number(report && report.counts && report.counts.messages) || 0), 0);
  return {
    present: rows.length > 0,
    readOnly: rows.length > 0 && rows.every((report) => report.readOnly === true),
    clean: rows.length > 0 && rows.every((report) =>
      report.ok === true && Number(report.errorCount) === 0
    ),
    noSuppressedIssues: rows.length > 0 && rows.every((report) =>
      Number(report.suppressedIssues) === 0
    ),
    fingerprintsValid: rows.length > 0 && invalidFingerprint === 0,
    sourcesPresent: rows.length > 0 && rows.every((report) =>
      String(report.sourceId || '').trim().length > 0
    ),
    messageCount,
    expectedMessageCount: Number(candidate && candidate.counts && candidate.counts.messages) || 0,
    reports: rows.length
  };
}

function buildReleaseReadiness(options) {
  const opts = options || {};
  const baseline = opts.baseline || {};
  const candidate = opts.candidate || {};
  const allowlist = normalizeAllowlist(opts.allowlist);
  const routePlan = opts.routePlan;
  const checks = [];
  const failures = [];
  const check = (name, ok, details) => {
    const row = { name, ok: !!ok };
    if (details !== undefined) row.details = details;
    checks.push(row);
    if (!ok) failures.push(row);
  };

  check('baseline-date', baseline.baselineDate === candidate.baselineDate, {
    baseline: baseline.baselineDate || '',
    candidate: candidate.baselineDate || ''
  });
  check('collection-counts', sameJson(baseline.counts, candidate.counts), {
    baseline: baseline.counts || {},
    candidate: candidate.counts || {}
  });
  check('upload-bytes', Number(baseline.uploadBytes) === Number(candidate.uploadBytes), {
    baseline: Number(baseline.uploadBytes) || 0,
    candidate: Number(candidate.uploadBytes) || 0
  });

  const manifestNames = new Set([
    ...Object.keys(baseline.manifests || {}),
    ...Object.keys(candidate.manifests || {})
  ]);
  const manifestDiffs = [];
  for (const name of Array.from(manifestNames).sort()) {
    if (name === 'messages') continue;
    const left = baseline.manifests && baseline.manifests[name];
    const right = candidate.manifests && candidate.manifests[name];
    if (!sameJson(left, right)) manifestDiffs.push({ name, baseline: left, candidate: right });
  }
  check('stable-collection-checksums', manifestDiffs.length === 0, manifestDiffs);

  const baselineMessageCount = Number(baseline.counts && baseline.counts.messages) || 0;
  const candidateMessageCount = Number(candidate.counts && candidate.counts.messages) || 0;
  check('message-count', baselineMessageCount === candidateMessageCount, {
    baseline: baselineMessageCount,
    candidate: candidateMessageCount
  });

  const candidateErrors = Array.isArray(candidate.errors) ? candidate.errors : [];
  const missingRows = candidateErrors.filter((row) => row.kind === 'upload-missing');
  const missingNames = new Set(missingRows.map((row) => String(row.id || '')).filter(Boolean));
  const otherErrors = candidateErrors.filter((row) => row.kind !== 'upload-missing');
  const unexpectedMedia = Array.from(missingNames).filter((name) => !allowlist.has(name));
  const absentAllowlisted = Array.from(allowlist).filter((name) => !missingNames.has(name));
  check('no-unexpected-errors', otherErrors.length === 0, otherErrors.slice(0, 100));
  check('known-media-exact', unexpectedMedia.length === 0 && absentAllowlisted.length === 0, {
    unexpected: unexpectedMedia,
    absent: absentAllowlisted
  });
  check('baseline-media-count',
    countOf(baseline, 'upload-missing') === allowlist.size,
    {
      baseline: countOf(baseline, 'upload-missing'),
      allowlist: allowlist.size,
      candidate: countOf(candidate, 'upload-missing')
    });
  check('candidate-error-count', Number(candidate.errorCount) === allowlist.size, {
    candidateErrorCount: Number(candidate.errorCount) || 0,
    allowlist: allowlist.size
  });
  check('duplicate-sequence-fixed',
    countOf(baseline, 'message-seq-duplicate') > 0
      && countOf(candidate, 'message-seq-duplicate') === 0,
    {
      baseline: countOf(baseline, 'message-seq-duplicate'),
      candidate: countOf(candidate, 'message-seq-duplicate')
    });

  const historicalKinds = [
    'orphan-message-file',
    'friendship-user',
    'group-owner',
    'chat-member',
    'chat-user-state',
    'transfer-chat',
    'read-chat'
  ];
  const warningDiffs = historicalKinds
    .filter((kind) => countOf(baseline, kind) !== countOf(candidate, kind))
    .map((kind) => ({
      kind,
      baseline: countOf(baseline, kind),
      candidate: countOf(candidate, kind)
    }));
  check('historical-warnings-unchanged', warningDiffs.length === 0, warningDiffs);

  const route = routePlan
    ? verifyRoutePlan(routePlan, {
      users: opts.users || null,
      chats: opts.chats || null
    })
    : { ok: false, failures: [{ kind: 'route-plan', message: 'route plan is required' }] };
  check('route-plan', route.ok, route.failures || []);
  if (route.ok) {
    check('route-user-count',
      route.counts.users === Number(candidate.counts && candidate.counts.users),
      {
        route: route.counts.users,
        data: Number(candidate.counts && candidate.counts.users) || 0
      });
    check('route-chat-count',
      route.counts.chats === Number(candidate.counts && candidate.counts.chats),
      {
        route: route.counts.chats,
        data: Number(candidate.counts && candidate.counts.chats) || 0
      });
    check('route-shard-count',
      route.shardCount >= 2
        && Array.isArray(routePlan.ports)
        && routePlan.ports.length === route.shardCount,
      { shardCount: route.shardCount, ports: routePlan.ports || [] });
  }

  const auditGate = messageAuditGate(
    opts.messageAudits || opts.messageAudit || [],
    candidate
  );
  if (opts.requireMessageAudit === true) {
    check('message-audit-present', auditGate.present, {
      reports: auditGate.reports
    });
    check('message-audit-read-only', auditGate.readOnly);
    check('message-audit-clean', auditGate.clean);
    check('message-audit-no-suppressed-issues', auditGate.noSuppressedIssues);
    check('message-audit-fingerprints', auditGate.fingerprintsValid);
    check('message-audit-sources', auditGate.sourcesPresent);
    check('message-audit-message-count',
      auditGate.messageCount === auditGate.expectedMessageCount,
      {
        reports: auditGate.messageCount,
        data: auditGate.expectedMessageCount
      });
  }

  const matrix = opts.messageMatrix || {};
  if (opts.requireMessageMatrix === true) {
    check('message-matrix-present', !!opts.messageMatrix);
    check('message-matrix-read-only', matrix.readOnly === true);
    check('message-matrix-clean', matrix.ok === true);
    check('message-matrix-no-suppressed-issues',
      Number(matrix.suppressedIssues) === 0);
    check('message-matrix-fingerprint',
      /^[a-f0-9]{64}$/i.test(String(matrix.fingerprint || '')));
    check('message-matrix-message-count',
      Number(matrix.messageCount) === Number(candidate.counts && candidate.counts.messages),
      {
        matrix: Number(matrix.messageCount) || 0,
        data: Number(candidate.counts && candidate.counts.messages) || 0
      });
    check('message-matrix-shard-count',
      route.ok && Number(matrix.shardCount) === route.shardCount,
      {
        matrix: Number(matrix.shardCount) || 0,
        topology: route.ok ? route.shardCount : 0
      });
  }

  const shadowRead = opts.shadowRead || null;
  if (opts.requireShadowRead === true) {
    const checked = shadowRead && shadowRead.checked || {};
    check('shadow-read-present', !!shadowRead);
    check('shadow-read-only', shadowRead && shadowRead.readOnly === true);
    check('shadow-read-clean',
      shadowRead && shadowRead.ok === true
        && Array.isArray(shadowRead.diffs)
        && shadowRead.diffs.length === 0);
    check('shadow-read-fingerprint',
      /^[a-f0-9]{64}$/i.test(String(shadowRead && shadowRead.fingerprint || '')));
    check('shadow-read-layout',
      shadowRead && shadowRead.physicalLayoutOk === true);
    check('shadow-read-route-plan',
      shadowRead && shadowRead.routePlanHash === (route.ok && route.hash));
    check('shadow-read-users',
      Number(checked.users) === Number(candidate.counts && candidate.counts.users));
    check('shadow-read-chats',
      Number(checked.chats) === Number(candidate.counts && candidate.counts.chats));
    check('shadow-read-moments',
      Number(checked.moments) === Number(candidate.counts && candidate.counts.moments));
    check('shadow-read-messages',
      Number(checked.messages) === Number(candidate.counts && candidate.counts.messages));
  }

  return {
    version: 1,
    ok: failures.length === 0,
    baseline: {
      sourceId: baseline.sourceId || '',
      baselineDate: baseline.baselineDate || '',
      counts: baseline.counts || {},
      issueCounts: baseline.issueCounts || {}
    },
    candidate: {
      sourceId: candidate.sourceId || '',
      baselineDate: candidate.baselineDate || '',
      counts: candidate.counts || {},
      issueCounts: candidate.issueCounts || {},
      errorCount: Number(candidate.errorCount) || 0,
      warningCount: Number(candidate.warningCount) || 0
    },
    knownMissingMedia: Array.from(allowlist).sort(),
    route: route.ok ? {
      topologyId: route.topologyId,
      shardCount: route.shardCount,
      hash: route.hash,
      counts: route.counts
    } : null,
    messageAudit: auditGate,
    messageMatrix: opts.requireMessageMatrix === true
      ? {
        present: !!opts.messageMatrix,
        shardCount: Number(matrix.shardCount) || 0,
        messageCount: Number(matrix.messageCount) || 0,
        fingerprint: String(matrix.fingerprint || '')
      }
      : null,
    shadowRead: opts.requireShadowRead === true ? {
      present: !!shadowRead,
      ok: !!(shadowRead && shadowRead.ok),
      fingerprint: String(shadowRead && shadowRead.fingerprint || ''),
      checked: shadowRead && shadowRead.checked || {},
      diffs: Number(shadowRead && shadowRead.diffs && shadowRead.diffs.length) || 0
    } : null,
    checks,
    failures
  };
}

module.exports = { buildReleaseReadiness };
